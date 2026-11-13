// Focused tests for the bounded controller command path.
//
// The controller-input plan asks for five things to be provable, and this file is where they are:
//
//   1. ordering - a press, its release and the next press reach the router in that order, each
//      exactly once, with the sequence numbers the log will show;
//   2. rejection - an axis, a d-pad position and a touch-pad sample never enter the command FIFO,
//      and a held sample is not a second press;
//   3. bounds - the FIFO is sixteen deep, overflow is counted rather than absorbed, and one batch
//      costs one drain whatever it holds;
//   4. the flag - turning the ingress off gives every edge back to the ordinary path, and a router
//      that has not started is never queued against;
//   5. the claim - the record is read but never invented, this build refuses to claim because
//      there is no seam, and every restore path gives a held button back with its own reason.
//
// Plus the log contract itself: the `controller-input` lines carry element ids, sequence numbers,
// counts and milliseconds, and never a device identity.
//
//   wolkaraforever/tools/test_controller_input.sh

#import <UIKit/UIKit.h>

#import "../launcher/Input/ControllerCommandIngress.h"
#import "../launcher/Input/InputElement.h"
#import "../launcher/Input/InputRouter.h"
#import "../launcher/Input/Trigger.h"
#import "../launcher/Voice/VoiceSettings.h"
#import "../launcher/Controller/ControllerInspector.h"

#import "../launcher/App/WolkaraForeverLog.h"

// AKCIDiagnosticsKey in ControllerInspector.m. Spelled out rather than imported: the fixture is
// asserting the *stored preference* the property reads, which is what a support log depends on.
static NSString *const AKTestDiagnosticsKey = @"WolkaraForeverInputDiagnostics";

// A device identity that must never appear in a `controller-input` line. Deliberately shaped like
// the real thing, so a line that leaked it would be recognisable.
static NSString *const AKTestDevice = @"synthetic.vendor.product";

static NSUInteger checks, failures;

static void Check(BOOL condition, NSString *what) {
    checks++;
    if (condition) return;
    failures++;
    fprintf(stderr, "FAIL: %s\n", what.UTF8String);
}
#define CHECK(condition, ...) Check((condition), [NSString stringWithFormat:__VA_ARGS__])

// Runs the run loop, because the drain is asynchronous on purpose: one block per batch is the
// point, so a fixture that delivered synchronously would be testing something else.
static void Pump(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

#pragma mark - What the ingress delivers

// The recorder the `deliver` block writes into. Nothing here reads the pad: the ingress is handed
// edges directly, which is exactly the interface the inspector calls from GameController's thread.
@interface TestSink : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *delivered;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *sequences;
@end

@implementation TestSink
- (instancetype)init {
    if ((self = [super init])) {
        _delivered = [NSMutableArray array];
        _sequences = [NSMutableArray array];
    }
    return self;
}
- (void)clear { [self.delivered removeAllObjects]; [self.sequences removeAllObjects]; }
- (NSString *)description { return [self.delivered componentsJoinedByString:@","]; }
@end

static TestSink *InstallSink(void) {
    TestSink *sink = [TestSink new];
    AKControllerCommandIngress.shared.deliver = ^(AKControllerCommand *command) {
        [sink.sequences addObject:@(command.sequence)];
        [sink.delivered addObject:[NSString stringWithFormat:@"%@:%@", command.element,
                                   command.pressed ? @"down" : @"up"]];
    };
    return sink;
}

static BOOL Submit(NSString *element, BOOL pressed) {
    return [AKControllerCommandIngress.shared submitElement:element value:(pressed ? 1 : 0)
                                                    pressed:pressed device:AKTestDevice rejection:NULL];
}

static void Reset(void) {
    AKControllerCommandIngress.shared.enabled = YES;
    [AKControllerCommandIngress.shared resetCounters];
    [AKControllerCommandIngress resetTrace];
    InstallSink();
}

#pragma mark - Ordering

// The contract the router depends on: what the pad did, in the order it did it, once each.
static void TestOrdering(void) {
    Reset();
    TestSink *sink = InstallSink();
    NSString *a = @"controller.button.share";
    NSString *b = @"controller.button.menu";
    CHECK(Submit(a, YES), @"a mapped press is taken by the ingress");
    CHECK(Submit(a, NO), @"its release is taken too");
    CHECK(Submit(b, YES), @"and the next button's press");
    Pump(0.15);

    CHECK(sink.delivered.count == 3, @"three edges are delivered, got %@", sink);
    CHECK([sink.delivered isEqualToArray:(@[@"controller.button.share:down",
                                            @"controller.button.share:up",
                                            @"controller.button.menu:down"])],
          @"and in the order the pad produced them, got %@", sink);
    CHECK([sink.sequences isEqualToArray:(@[@1, @2, @3])], @"with sequence numbers 1, 2, 3, got %@",
          sink.sequences);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 3, @"three admissions, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.admittedCount);
    CHECK(AKControllerCommandIngress.shared.deliveredCount == 3, @"three deliveries, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.deliveredCount);
    CHECK(AKControllerCommandIngress.shared.latency.count == 3, @"and three latency samples");
    CHECK(AKControllerCommandIngress.shared.latency.maximum >= 0, @"whose worst value is a duration");
}

// A held press is one press. The pad's own handler only fires on a change, but a value change on
// an analog button can report the same state again, and the FIFO must not carry it.
static void TestDuplicateSuppression(void) {
    Reset();
    TestSink *sink = InstallSink();
    NSString *a = @"controller.button.share";
    AKControllerCommandRejection why = AKControllerCommandRejectionNone;
    CHECK(Submit(a, YES), @"the first press is admitted");
    BOOL again = [AKControllerCommandIngress.shared submitElement:a value:1 pressed:YES
                                                           device:AKTestDevice rejection:&why];
    CHECK(again, @"the repeat is swallowed by the ingress, not handed back to the caller");
    CHECK(why == AKControllerCommandRejectionRepeat, @"and reported as a repeat, got %ld", (long)why);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 1, @"one admission for one press, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.admittedCount);
    CHECK(AKControllerCommandIngress.shared.rejectedCount == 1, @"one rejection, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.rejectedCount);
    Pump(0.15);
    CHECK(sink.delivered.count == 1, @"and one delivery, got %@", sink);

    // A real release still gets through after the suppressed repeat, so the pair is never stuck.
    CHECK(Submit(a, NO), @"the release after a suppressed repeat is admitted");
    Pump(0.15);
    CHECK(sink.delivered.count == 2, @"so the pair is complete, got %@", sink);
}

// Axes, d-pads and touch-pads are not commands. They are also not this class's business: the
// caller is told to use its ordinary path, which is what keeps diagnostics working for them.
static void TestRejection(void) {
    Reset();
    TestSink *sink = InstallSink();
    NSArray<NSString *> *notPresses = @[
        AKInputElementForControllerAxis(@"Left Thumbstick"),
        AKInputElementForDirectionPad(@"Direction Pad", 0.5, -1.0),
        AKInputElementForTouchpad(@"Touchpad", @"moved"),
        AKInputElementForKeyboardKey(36),
        @"mouse.button.left",
        @"",
    ];
    for (NSString *element in notPresses) {
        AKControllerCommandRejection why = AKControllerCommandRejectionNone;
        BOOL taken = [AKControllerCommandIngress.shared submitElement:element value:1 pressed:YES
                                                               device:AKTestDevice rejection:&why];
        CHECK(!taken, @"%@ is not taken by the command ingress", element);
        CHECK(why == AKControllerCommandRejectionNotAPress, @"%@ is refused as not-a-press, got %ld",
              element, (long)why);
    }
    Pump(0.15);
    CHECK(sink.delivered.count == 0, @"and nothing reached the router, got %@", sink);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 0, @"with no admissions");
    CHECK(AKControllerCommandIngress.shared.overflowCount == 0, @"and no overflow");
}

// Sixteen is the bound, and the seventeenth edge is counted rather than queued. A run with a
// non-zero overflow count is a failed run, so it has to be visible.
static void TestOverflow(void) {
    Reset();
    TestSink *sink = InstallSink();
    for (NSUInteger index = 0; index < 16; index++)
        CHECK(Submit([NSString stringWithFormat:@"controller.button.k%lu", (unsigned long)index], YES),
              @"edge %lu fits in the FIFO", (unsigned long)index);
    AKControllerCommandRejection why = AKControllerCommandRejectionNone;
    BOOL taken = [AKControllerCommandIngress.shared submitElement:@"controller.button.seventeen"
                                                            value:1 pressed:YES
                                                           device:AKTestDevice rejection:&why];
    CHECK(taken, @"the seventeenth is swallowed rather than handed to the ordinary path");
    CHECK(why == AKControllerCommandRejectionOverflow, @"and named as an overflow, got %ld", (long)why);
    CHECK(AKControllerCommandIngress.shared.overflowCount == 1, @"one overflow, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.overflowCount);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 16, @"sixteen admissions, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.admittedCount);
    Pump(0.2);
    CHECK(sink.delivered.count == 16, @"and the sixteen that fitted are delivered, got %lu",
          (unsigned long)sink.delivered.count);
    CHECK(AKControllerCommandIngress.shared.drainCount == 1, @"in one drain, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.drainCount);
}

// One block per batch. This is the whole reason the class exists: N presses must not cost N trips
// through a run loop that may be busy with diagnostics.
static void TestOneDrain(void) {
    Reset();
    InstallSink();
    for (NSUInteger index = 0; index < 5; index++) {
        NSString *element = [NSString stringWithFormat:@"controller.button.d%lu", (unsigned long)index];
        Submit(element, YES);
        Submit(element, NO);
    }
    CHECK(AKControllerCommandIngress.shared.drainCount == 0, @"nothing is delivered synchronously");
    Pump(0.2);
    CHECK(AKControllerCommandIngress.shared.drainCount == 1, @"ten edges cost one drain, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.drainCount);
    CHECK(AKControllerCommandIngress.shared.deliveredCount == 10, @"and all ten are delivered, got %lu",
          (unsigned long)AKControllerCommandIngress.shared.deliveredCount);
}

// The completion gate asks that turning the flag off restores the behaviour that was there before.
// It has to restore it for the *caller*, not by delivering anyway.
static void TestFeatureFlag(void) {
    Reset();
    TestSink *sink = InstallSink();
    AKControllerCommandIngress.shared.enabled = NO;
    AKControllerCommandRejection why = AKControllerCommandRejectionNone;
    BOOL taken = [AKControllerCommandIngress.shared submitElement:@"controller.button.share"
                                                            value:1 pressed:YES
                                                           device:AKTestDevice rejection:&why];
    CHECK(!taken, @"with the ingress off the edge is handed back to the inspector's own path");
    CHECK(why == AKControllerCommandRejectionNoRoute, @"and says so, got %ld", (long)why);
    Pump(0.15);
    CHECK(sink.delivered.count == 0, @"nothing is delivered behind the caller's back, got %@", sink);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 0, @"and nothing is admitted");

    // And off means off across a rebuild of the object's stored flag, which is what a relaunch does.
    CHECK(![NSUserDefaults.standardUserDefaults boolForKey:@"AKControllerIngressEnabled"] == NO ||
          [NSUserDefaults.standardUserDefaults objectForKey:@"AKControllerIngressEnabled"] != nil,
          @"the flag is stored, so 'was the fix on?' is answerable from a later log");
    AKControllerCommandIngress.shared.enabled = YES;
    CHECK(Submit(@"controller.button.share", YES), @"and back on, the edge is taken again");
    Pump(0.15);
    CHECK(sink.delivered.count == 1, @"and delivered, got %@", sink);
}

// A router that has not started has nowhere to put a command. Queueing against it would be
// queueing an input that may never be delivered.
static void TestNoRoute(void) {
    Reset();
    AKControllerCommandIngress.shared.deliver = nil;
    AKControllerCommandRejection why = AKControllerCommandRejectionNone;
    BOOL taken = [AKControllerCommandIngress.shared submitElement:@"controller.button.share"
                                                            value:1 pressed:YES
                                                           device:AKTestDevice rejection:&why];
    CHECK(!taken, @"a command with no destination is handed back");
    CHECK(why == AKControllerCommandRejectionNoRoute, @"with the reason that says why, got %ld", (long)why);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 0, @"and is not counted as admitted");
    InstallSink();
}

// Counters are per run. Resetting must also forget the held state, or one case's press would make
// the next case's press look like a repeat.
static void TestCountersReset(void) {
    Reset();
    TestSink *sink = InstallSink();
    Submit(@"controller.button.share", YES);
    Pump(0.15);
    CHECK(AKControllerCommandIngress.shared.admittedCount == 1, @"one admission before the reset");
    [AKControllerCommandIngress.shared resetCounters];
    CHECK(AKControllerCommandIngress.shared.admittedCount == 0, @"admissions are cleared");
    CHECK(AKControllerCommandIngress.shared.deliveredCount == 0, @"deliveries are cleared");
    CHECK(AKControllerCommandIngress.shared.rejectedCount == 0, @"rejections are cleared");
    CHECK(AKControllerCommandIngress.shared.overflowCount == 0, @"overflows are cleared");
    CHECK(AKControllerCommandIngress.shared.drainCount == 0, @"drains are cleared");
    CHECK(AKControllerCommandIngress.shared.latency.count == 0, @"and the latency ring is cleared");
    [sink clear];
    CHECK(Submit(@"controller.button.share", YES), @"the held state is forgotten, so the same press "
          @"is admitted again rather than suppressed as a repeat");
    Pump(0.15);
    CHECK(sink.delivered.count == 1, @"and delivered, got %@", sink);
}

#pragma mark - The two intervals the performance contract names

// The half of "pad callback to Composer visible" a simulator can carry: the moment the edge reaches
// this app to the moment the app's own trigger handler runs - which is the step that opens the
// Composer. A simulator has no pad, so the edge is submitted at exactly the point the inspector
// submits it; the number is the routing cost, and the Composer's own state update on top of it is
// reported by the shell as `composer open outcome=... ms=...` in a real app run.
//
// Reported as p50, p95 and the maximum, which is what the completion specification asks for, and
// with the overflow count printed beside them because any overflow at all is a failed run.
static void TestLatencies(void) {
    Reset();
    AKControllerCommandIngress *ingress = AKControllerCommandIngress.shared;
    AKVoiceSettings *settings = AKVoiceSettings.shared;
    // The app's own wiring, put back because Reset() replaced it with a recorder: a measurement of
    // the queue alone would not be a measurement of the path a mapped button takes.
    ingress.deliver = ^(AKControllerCommand *command) {
        [AKInputRouter.shared reportElement:command.element value:command.value
                                    pressed:command.pressed device:command.device
                                     source:AKInputSourceController];
    };

    // A real mapping, so the router actually fires: this is the path a mapped button takes to
    // dictation, not a measurement of the queue on its own.
    settings.enabled = YES;
    [settings setLearnedElement:@"controller.button.share" forDevice:AKTestDevice];

    AKTimingSamples *triggerLatency = [AKTimingSamples new];
    __block NSUInteger fired = 0, released = 0;
    AKInputRouter.shared.onTriggerBegan = ^(AKTrigger *trigger, AKInputEvent *event) {
        (void)trigger; (void)event;
        NSTimeInterval admitted = ingress.lastAdmitted;
        if (admitted > 0)
            [triggerLatency record:(NSProcessInfo.processInfo.systemUptime - admitted) * 1000.0];
        fired++;
    };
    AKInputRouter.shared.onTriggerEnded = ^(AKTrigger *trigger, AKInputEvent *event) {
        (void)trigger; (void)event;
        released++;
    };

    NSUInteger rounds = 40;
    for (NSUInteger index = 0; index < rounds; index++) {
        Submit(@"controller.button.share", YES);
        Pump(0.02);
        Submit(@"controller.button.share", NO);
        Pump(0.02);
    }

    CHECK(fired == rounds, @"every press reached the trigger handler, got %lu of %lu",
          (unsigned long)fired, (unsigned long)rounds);
    CHECK(released == rounds, @"and every release ended it, got %lu", (unsigned long)released);
    CHECK(ingress.overflowCount == 0, @"no overflow, got %lu", (unsigned long)ingress.overflowCount);
    CHECK(ingress.admittedCount == rounds * 2, @"and nothing but those edges was admitted, got %lu",
          (unsigned long)ingress.admittedCount);
    CHECK(ingress.latency.count == rounds * 2, @"a sample per edge, got %lu",
          (unsigned long)ingress.latency.count);
    CHECK(triggerLatency.count == rounds, @"a trigger sample per press, got %lu",
          (unsigned long)triggerLatency.count);

    printf("CONTROLLER-INPUT LATENCY enqueue_ms p50=%.2f p95=%.2f max=%.2f n=%lu"
           " | trigger_ms p50=%.2f p95=%.2f max=%.2f n=%lu"
           " | overflows=%lu admissions=%lu\n",
           [ingress.latency percentile:0.50], [ingress.latency percentile:0.95],
           ingress.latency.maximum, (unsigned long)ingress.latency.count,
           [triggerLatency percentile:0.50], [triggerLatency percentile:0.95],
           triggerLatency.maximum, (unsigned long)triggerLatency.count,
           (unsigned long)ingress.overflowCount, (unsigned long)ingress.admittedCount);
    fflush(stdout);

    // Back to the state this fixture found, so nothing leaks into another case.
    AKInputRouter.shared.onTriggerBegan = nil;
    AKInputRouter.shared.onTriggerEnded = nil;
    [settings clearMappingForDevice:AKTestDevice];
    settings.enabled = NO;
    [AKControllerCommandIngress.shared resetCounters];
    InstallSink();
}

#pragma mark - The claim

// This build has no seam, and the answer is a property of the route rather than a guess.
static void TestClaimAvailability(void) {    CHECK(!AKVoiceSettings.controllerClaimIsAvailable,
          @"no controller-button claim is available in this build");
    BOOL claimed = [AKVoiceSettings.shared claimElement:@"controller.button.share" device:AKTestDevice];
    CHECK(!claimed, @"and asking for one is refused rather than stored");
    CHECK(![AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:AKTestDevice],
          @"so nothing is recorded for it");
    CHECK(AKVoiceSettings.shared.claimedElements.count == 0, @"and nothing is held back");

    // Not a controller button: refused for its own reason, even with a seam.
    [AKVoiceSettings setControllerClaimSeamAvailableForTesting:YES];
    CHECK(![AKVoiceSettings.shared claimElement:AKInputElementForKeyboardKey(36) device:AKTestDevice],
          @"a keyboard key is not a controller button, so it is never claimed here");
    CHECK(![AKVoiceSettings.shared claimElement:@"system.screenshot" device:AKTestDevice],
          @"and neither is a system signal");
    [AKVoiceSettings setControllerClaimSeamAvailableForTesting:NO];
}

// An installation from before this feature has no record at all. The answer is "not claimed", and
// nothing is written merely by asking.
static void TestClaimMigration(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"AKControllerClaims"];
    CHECK(![AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:AKTestDevice],
          @"a missing record reads as not claimed");
    CHECK(![AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:nil],
          @"for a named controller and for any controller alike");
    CHECK([defaults objectForKey:@"AKControllerClaims"] == nil,
          @"and asking does not invent one");

    // A record written by a build that could claim is read, not overwritten.
    [defaults setObject:@{ AKTestDevice: @{ @"element": @"controller.button.share", @"claimed": @YES } }
                 forKey:@"AKControllerClaims"];
    CHECK([AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:AKTestDevice],
          @"a stored record is read back");
    CHECK(![AKVoiceSettings.shared isElement:@"controller.button.menu" claimedForDevice:AKTestDevice],
          @"and only for the element it names");
    CHECK(AKVoiceSettings.shared.claimedElements.count == 0,
          @"but it is not in force in a build that cannot honour it");
    [defaults removeObjectForKey:@"AKControllerClaims"];
}

// Every boundary the gate names, each with its own reason, proved with the seam forced on so the
// paths are exercised now rather than written blind.
static void TestClaimRestorePaths(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"AKControllerClaims"];
    [AKVoiceSettings setControllerClaimSeamAvailableForTesting:YES];

    NSArray<NSString *> *reasons = @[@"disable", @"disconnect", @"background", @"route-failure", @"exit"];
    for (NSString *reason in reasons) {
        CHECK([AKVoiceSettings.shared claimElement:@"controller.button.share" device:AKTestDevice],
              @"a claim can be made for a controller button (%@)", reason);
        CHECK(AKVoiceSettings.shared.claimedElements.count == 1, @"and is in force (%@)", reason);
        CHECK([AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:AKTestDevice],
              @"and is stored (%@)", reason);
        [AKVoiceSettings.shared releaseClaimsWithReason:reason];
        CHECK(AKVoiceSettings.shared.claimedElements.count == 0,
              @"%@ gives the button back, got %lu still held", reason,
              (unsigned long)AKVoiceSettings.shared.claimedElements.count);
        CHECK([AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:AKTestDevice],
              @"and keeps the record for a later re-enable (%@)", reason);
    }

    // A release is idempotent: giving back something that is not held says nothing and changes
    // nothing.
    [AKVoiceSettings.shared releaseClaimsWithReason:@"background"];
    CHECK(AKVoiceSettings.shared.claimedElements.count == 0, @"a second release is harmless");

    [AKVoiceSettings.shared releaseClaimForElement:@"controller.button.share" device:AKTestDevice];
    CHECK(![AKVoiceSettings.shared isElement:@"controller.button.share" claimedForDevice:AKTestDevice],
          @"and an explicit release forgets the record");
    [AKVoiceSettings setControllerClaimSeamAvailableForTesting:NO];
    [defaults removeObjectForKey:@"AKControllerClaims"];
}

#pragma mark - The log contract

// The lines this feature writes, and the ones it must never write.
static NSArray<NSString *> *ControllerInputLines(void) {
    NSString *log = [NSString stringWithContentsOfFile:WKLogPath() encoding:NSUTF8StringEncoding error:NULL];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [log ?: @"" componentsSeparatedByString:@"\n"])
        if ([line containsString:@"[controller-input]"]) [lines addObject:line];
    return lines;
}

static BOOL AnyLineContains(NSArray<NSString *> *lines, NSString *fragment) {
    for (NSString *line in lines) if ([line containsString:fragment]) return YES;
    return NO;
}

static void TestTraceEvents(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // The per-edge trail follows the inspector's own diagnostics switch, which is the stored
    // preference the property reads.
    [defaults setBool:YES forKey:AKTestDiagnosticsKey];
    Reset();
    InstallSink();

    Submit(@"controller.button.share", YES);
    // A repeat, so the rejection line is in the same run.
    [AKControllerCommandIngress.shared submitElement:@"controller.button.share" value:1 pressed:YES
                                              device:AKTestDevice rejection:NULL];
    Pump(0.2);
    Submit(@"controller.button.share", NO);
    Pump(0.2);
    // An overflow line, which does not depend on diagnostics being on.
    [AKControllerCommandIngress.shared resetCounters];
    for (NSUInteger index = 0; index < 17; index++)
        [AKControllerCommandIngress.shared submitElement:[NSString stringWithFormat:@"controller.button.o%lu",
                                                          (unsigned long)index]
                                                   value:1 pressed:YES device:AKTestDevice rejection:NULL];
    Pump(0.3);
    // And a claim event, with the seam forced on for this half of the test only.
    [AKVoiceSettings setControllerClaimSeamAvailableForTesting:YES];
    [AKVoiceSettings.shared claimElement:@"controller.button.share" device:AKTestDevice];
    [AKVoiceSettings.shared releaseClaimsWithReason:@"disconnect"];
    [AKVoiceSettings setControllerClaimSeamAvailableForTesting:NO];
    // The Composer's answer, from the entry point the adapter reports it on - and the same answer
    // from a toolbar press, which is not this feature's event and must not appear. The toolbar's
    // answer carries a word of its own, so the assertion cannot be satisfied by the controller's
    // line in a log that a previous run already wrote to.
    [AKControllerCommandIngress traceComposerOpenOutcome:@"opened"
                                                  source:AKControllerCommandComposerSourceController];
    [AKControllerCommandIngress traceComposerOpenOutcome:@"not-a-mapped-button" source:0];

    NSArray<NSString *> *lines = ControllerInputLines();
    CHECK(lines.count > 0, @"the controller-input channel carries lines");
    CHECK(AnyLineContains(lines, @"admit seq=1 element=controller.button.share edge=down"),
          @"an admission names the element and the edge");
    CHECK(AnyLineContains(lines, @"drain seq=1..1 n=1 wait_ms="), @"a drain names the sequence range and the wait");
    CHECK(AnyLineContains(lines, @"reject reason=repeat element=controller.button.share"),
          @"a suppressed repeat says so");
    CHECK(AnyLineContains(lines, @"drop reason=overflow element=controller.button.o16"),
          @"an overflow names the edge that did not fit");
    CHECK(AnyLineContains(lines, @"claim take element=controller.button.share"), @"a claim says which button");
    CHECK(AnyLineContains(lines, @"claim restore element=controller.button.share reason=disconnect"),
          @"and the restore says why it was given back");
    CHECK(AnyLineContains(lines, @"claim refused reason=no-route element="),
          @"a refusal in the shipping build says which reason applies");
    CHECK(AnyLineContains(lines, @"composer open outcome=opened ms="),
          @"the Composer's answer carries its outcome and its milliseconds");
    CHECK(!AnyLineContains(lines, @"not-a-mapped-button"),
          @"and a toolbar press never reaches this channel");

    // The one thing the channel must never carry. The device identity is the finest thing
    // GameController offers, and it is not the command: the lines above carry element ids and
    // numbers, and the pad's identity never appears in them.
    CHECK(!AnyLineContains(lines, AKTestDevice), @"no controller-input line carries a device identity");
    CHECK(!AnyLineContains(lines, @"synthetic"), @"and nothing shaped like one");
    // The invariant is about the lines this run wrote, so the tail is what it judges: the app's log
    // survives between launches and a previous run's lines are not this run's business.
    NSUInteger from = lines.count > 40 ? lines.count - 40 : 0;
    for (NSUInteger index = from; index < lines.count; index++) {
        NSString *line = lines[index];
        NSUInteger at = [line rangeOfString:@"[controller-input]"].location + @"[controller-input]".length;
        NSString *payload = at < line.length ? [line substringFromIndex:at] : @"";
        CHECK(![payload containsString:@"synthetic"], @"every payload is free of device text: %@", payload);
    }

    // Bounded: the budget is handed back, and the note that says it ran out is written once rather
    // than the channel simply stopping.
    [AKControllerCommandIngress resetTrace];
    BOOL sawAdmissionAfterReset = NO;
    Submit(@"controller.button.share", YES);
    Pump(0.15);
    for (NSString *line in ControllerInputLines())
        if ([line containsString:@"admit seq="]) sawAdmissionAfterReset = YES;
    CHECK(sawAdmissionAfterReset, @"a fresh budget produces lines again");

    [defaults setBool:NO forKey:AKTestDiagnosticsKey];
    [defaults removeObjectForKey:@"AKControllerClaims"];
}

#pragma mark - Running them

@interface TestDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic) UIWindow *window;
@end

@implementation TestDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    WKLogStart();
    WKLog("test", @"controller-input suite starting");
    // A fixture that can hang is not a test.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        fprintf(stderr, "CONTROLLER-INPUT TIMEOUT\n");
        _Exit(1);
    });
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];

    // The real router, so a delivered command goes through the trigger semantics the app has
    // rather than through a second implementation written for the test.
    [AKInputRouter.shared begin];
    // The sink above is installed after the router, deliberately: these cases read what the
    // ingress did, and the router's own block is what proves the wiring exists in the app.
    CHECK(AKControllerCommandIngress.shared.deliver != nil,
          @"the input router publishes the ingress's destination when it starts");

    TestOrdering();
    TestDuplicateSuppression();
    TestRejection();
    TestOverflow();
    TestOneDrain();
    TestFeatureFlag();
    TestNoRoute();
    TestCountersReset();
    TestLatencies();
    TestClaimAvailability();
    TestClaimMigration();
    TestClaimRestorePaths();
    TestTraceEvents();

    if (failures == 0) {
        printf("CONTROLLER-INPUT PASS: %lu checks\n", (unsigned long)checks);
        fflush(stdout);
        exit(0);
    }
    printf("CONTROLLER-INPUT FAIL: %lu of %lu checks failed\n", (unsigned long)failures,
           (unsigned long)checks);
    fflush(stdout);
    exit(1);
}
@end

// A scene-based app needs to say which object is the scene's delegate; without this the scene
// never connects and the suite silently does nothing.
@interface TestApp : UIResponder <UIApplicationDelegate>
@end

@implementation TestApp
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Controller input tests"
                                                                        sessionRole:session.role];
    configuration.delegateClass = TestDelegate.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TestApp.class));
    }
}
