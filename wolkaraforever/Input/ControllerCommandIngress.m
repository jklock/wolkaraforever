// WolkaraForever: the bounded command path, in full.

#import "ControllerCommandIngress.h"
#import "InputElement.h"

#import "../App/WolkaraForeverLog.h"
#import "../Controller/ControllerInspector.h"

// One line per event is what a human reads; sixteen is already more presses than a person can
// make between two main-queue turns, and the drain is scheduled on the first one. A queue that
// can grow past that is a queue whose latency is not bounded, which is the whole thing this file
// exists to prevent. Overflow is counted and is a failed run, not something to absorb quietly.
static NSUInteger const AKCommandCapacity = 16;

// What a fresh investigation starts with. Two lines per press with diagnostics on, one line per
// rare event otherwise: at 200 presses a sweep, 400 is more than a five-minute run needs and far
// less than the 12,658 lines the 2026-11-04 device log held for one channel.
static NSUInteger const AKTraceBudget = 400;

// Stored, so "was the fix on?" can be answered from a log taken after the fact.
static NSString *const AKControllerIngressEnabledKey = @"AKControllerIngressEnabled";

@implementation AKControllerCommand
- (instancetype)initWithSequence:(uint64_t)sequence element:(NSString *)element value:(double)value
                         pressed:(BOOL)pressed device:(NSString *)device
                        admitted:(NSTimeInterval)admitted {
    if ((self = [super init])) {
        _sequence = sequence;
        _element = [element copy];
        _value = value;
        _pressed = pressed;
        _device = [device copy];
        _admitted = admitted;
    }
    return self;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"#%llu %@ %@", (unsigned long long)_sequence,
            _element, _pressed ? @"down" : @"up"];
}
@end

@implementation AKControllerCommandIngress {
    NSMutableArray<AKControllerCommand *> *_pending;
    // The last state the ingress *saw*, not the last it delivered. A pad that reports the same
    // state twice has not produced a second press, and the router's own duplicate suppression
    // only helps if the sample reaches it - which the FIFO would have to carry first.
    NSMutableDictionary<NSString *, NSNumber *> *_held;
    uint64_t _nextSequence;
    BOOL _drainScheduled;
    BOOL _enabled;
    NSUInteger _admitted, _delivered, _rejected, _overflow, _drains;
    NSTimeInterval _lastAdmitted;
    AKTimingSamples *_latency;
}

+ (instancetype)shared {
    static AKControllerCommandIngress *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKControllerCommandIngress new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pending = [NSMutableArray array];
        _held = [NSMutableDictionary dictionary];
        _latency = [AKTimingSamples new];
        _nextSequence = 1;
        // On. This class changes no behaviour the user can see: the same edge reaches the same
        // router and fires the same trigger. What it changes is how much work stands in front of
        // that, which is the defect. Off is the escape hatch, not the default.
        NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:AKControllerIngressEnabledKey];
        _enabled = [stored isKindOfClass:NSNumber.class] ? stored.boolValue : YES;
    }
    return self;
}

#pragma mark - The flag

- (BOOL)enabled { @synchronized (self) { return _enabled; } }
- (void)setEnabled:(BOOL)enabled {
    BOOL changed = NO;
    @synchronized (self) {
        changed = (_enabled != enabled);
        _enabled = enabled;
    }
    [NSUserDefaults.standardUserDefaults setObject:@(enabled) forKey:AKControllerIngressEnabledKey];
    if (!changed) return;
    // A product switch, so it is written even with diagnostics off: "was the fix on?" has to be
    // answerable from a log taken after the fact.
    [AKControllerCommandIngress trace:@"ingress edge=%s", enabled ? "on" : "off"];
}

#pragma mark - Counters

- (NSUInteger)admittedCount { @synchronized (self) { return _admitted; } }
- (NSUInteger)deliveredCount { @synchronized (self) { return _delivered; } }
- (NSUInteger)rejectedCount { @synchronized (self) { return _rejected; } }
- (NSUInteger)overflowCount { @synchronized (self) { return _overflow; } }
- (NSUInteger)drainCount { @synchronized (self) { return _drains; } }
- (AKTimingSamples *)latency { return _latency; }
- (NSTimeInterval)lastAdmitted { @synchronized (self) { return _lastAdmitted; } }

- (void)resetCounters {
    NSUInteger queued = 0;
    @synchronized (self) {
        queued = _pending.count;
        [_pending removeAllObjects];
        [_held removeAllObjects];
        _admitted = _delivered = _rejected = _overflow = _drains = 0;
        _lastAdmitted = 0;
        _drainScheduled = NO;
        _nextSequence = 1;
    }
    [_latency reset];
    if (queued) WKLog("controller-input", @"%lu command(s) were still queued when the counters were reset",
                      (unsigned long)queued);
}

#pragma mark - Admission

- (BOOL)submitElement:(NSString *)element value:(double)value pressed:(BOOL)pressed
               device:(nullable NSString *)device rejection:(nullable AKControllerCommandRejection *)rejection {
    AKControllerCommandRejection why = AKControllerCommandRejectionNone;
    BOOL taken = NO;

    if (!element.length || ![element hasPrefix:@"controller.button."]) {
        // An axis, a d-pad position, a touch-pad sample, a key, a click: not a command, and
        // never queued. The caller's ordinary path is what these use, exactly as before.
        why = AKControllerCommandRejectionNotAPress;
    } else if (!self.enabled) {
        // Not a rejection: the feature is off, so the inspector keeps the edge. Said out loud so
        // "zero admissions" cannot be confused with "nothing was pressed".
        why = AKControllerCommandRejectionNoRoute;
    } else if (!self.deliver) {
        // Nothing to deliver to yet. Handing the edge back keeps the input alive; queueing it
        // would be queueing against a router that has not started and may never start.
        why = AKControllerCommandRejectionNoRoute;
    } else {
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        BOOL schedule = NO;
        uint64_t admittedSequence = 0;
        NSUInteger depth = 0;
        @synchronized (self) {
            NSNumber *held = _held[element];
            if (held && held.boolValue == pressed) {
                why = AKControllerCommandRejectionRepeat;
                _rejected += 1;
                taken = YES; // deliberately swallowed: the caller must not deliver it either
            } else if (_pending.count >= AKCommandCapacity) {
                why = AKControllerCommandRejectionOverflow;
                _rejected += 1;
                _overflow += 1;
                taken = YES; // and counted: an overflow is a failed run, not a silent drop
            } else {
                _held[element] = @(pressed);
                [_pending addObject:[[AKControllerCommand alloc] initWithSequence:_nextSequence++
                                                                         element:element
                                                                           value:value
                                                                         pressed:pressed
                                                                          device:device ?: @"?"
                                                                        admitted:now]];
                _admitted += 1;
                _lastAdmitted = now;
                taken = YES;
                admittedSequence = _nextSequence - 1;
                depth = _pending.count;
                if (!_drainScheduled) { _drainScheduled = YES; schedule = YES; }
            }
        }
        if (admittedSequence) {
            [AKControllerCommandIngress traceSequence:@"admit seq=%llu element=%@ edge=%s q=%lu",
                                                 (unsigned long long)admittedSequence, element,
                                                 pressed ? "down" : "up", (unsigned long)depth];
        }
        if (schedule) {
            __weak AKControllerCommandIngress *weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf drain]; });
        }
    }

    if (why == AKControllerCommandRejectionRepeat) {
        [AKControllerCommandIngress traceSequence:@"reject reason=repeat element=%@", element];
    } else if (why == AKControllerCommandRejectionOverflow) {
        [AKControllerCommandIngress trace:@"drop reason=overflow element=%@ overflows=%lu", element,
                                     (unsigned long)self.overflowCount];
    } else if (why == AKControllerCommandRejectionNotAPress) {
        [AKControllerCommandIngress traceSequence:@"reject reason=not-a-press element=%@", element];
    }

    if (rejection) *rejection = why;
    return taken;
}

// One block for the whole batch, whatever the pad did between two main-queue turns. Delivering
// in the block is what the router already expected; coalescing is what stops N presses from
// costing N trips through a run loop that may be busy with something else.
- (void)drain {
    NSArray<AKControllerCommand *> *batch = nil;
    NSUInteger drains = 0;
    @synchronized (self) {
        batch = _pending;
        _pending = [NSMutableArray array];
        _drainScheduled = NO;
        _drains += 1;
        drains = _drains;
    }
    if (!batch.count) return;

    NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
    double worstWait = 0;
    uint64_t first = 0, last = 0;
    void (^deliver)(AKControllerCommand *) = self.deliver;
    for (AKControllerCommand *command in batch) {
        double wait = (began - command.admitted) * 1000.0;
        if (wait > worstWait) worstWait = wait;
        if (!first) first = command.sequence;
        last = command.sequence;
        [_latency record:wait];
        @synchronized (self) { _delivered += 1; }
        if (deliver) deliver(command);
    }
    double spent = (NSProcessInfo.processInfo.systemUptime - began) * 1000.0;
    [AKControllerCommandIngress traceSequence:@"drain seq=%llu..%llu n=%lu wait_ms=%.1f drain_ms=%.1f drains=%lu",
                                         (unsigned long long)first, (unsigned long long)last,
                                         (unsigned long)batch.count, worstWait, spent,
                                         (unsigned long)drains];
}

#pragma mark - Bounded tracing

static NSUInteger _traceRemaining = AKTraceBudget;
static BOOL _tracingEnabled = YES;

+ (BOOL)tracingEnabled { return _tracingEnabled; }
+ (void)setTracingEnabled:(BOOL)enabled { _tracingEnabled = enabled; }
+ (void)resetTrace { @synchronized (self) { _traceRemaining = AKTraceBudget; } }

+ (BOOL)takeTraceSlot {
    @synchronized (self) {
        if (_traceRemaining == 0) return NO;
        if (_traceRemaining == 1) {
            _traceRemaining = 0;
            // One note, once, and then the channel is silent. A cap that says nothing looks
            // exactly like a fault.
            WKLog("controller-input", @"trace budget spent (%lu lines); counters continue",
                  (unsigned long)AKTraceBudget);
            return NO;
        }
        _traceRemaining -= 1;
        return YES;
    }
}

+ (void)trace:(NSString *)format, ... {
    if (!_tracingEnabled) return;
    if (![self takeTraceSlot]) return;
    va_list ap; va_start(ap, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    WKLog("controller-input", @"%@", message);
}

// The per-edge trail exists only while someone asked to read the stream. Without that, a press
// still works and nothing more is written - the rule the inspector's own diagnostics follow.
+ (void)traceSequence:(NSString *)format, ... {
    if (!_tracingEnabled) return;
    if (!AKControllerInspector.shared.diagnosticsEnabled) return;
    if (![self takeTraceSlot]) return;
    va_list ap; va_start(ap, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    WKLog("controller-input", @"%@", message);
}

NSInteger const AKControllerCommandComposerSourceController = 2;

+ (void)traceComposerOpenOutcome:(NSString *)outcome source:(NSInteger)source {
    // A toolbar press or a keyboard press is the adapter's own entry point. Reporting it here
    // would make the channel about the Composer rather than about the mapped button.
    if (source != AKControllerCommandComposerSourceController) return;
    AKControllerCommandIngress *ingress = AKControllerCommandIngress.shared;
    double elapsedMs = -1;
    if (ingress.enabled) {
        NSTimeInterval admitted = ingress.lastAdmitted;
        if (admitted > 0) {
            double elapsed = (NSProcessInfo.processInfo.systemUptime - admitted) * 1000.0;
            // A stale stamp is not a measurement.
            if (elapsed >= 0 && elapsed < 5000) elapsedMs = elapsed;
        }
    }
    if (elapsedMs >= 0) {
        [self trace:@"composer open outcome=%@ ms=%.1f", outcome ?: @"unknown", elapsedMs];
    } else {
        [self trace:@"composer open outcome=%@ ms=n/a", outcome ?: @"unknown"];
    }
}

@end
