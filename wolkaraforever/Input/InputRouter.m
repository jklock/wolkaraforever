// WolkaraForever: the one input stream, and the patterns a trigger can match on.

#import "InputRouter.h"

#import "../App/WolkaraForeverLog.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// One sink, for the same reason as the inspector's: `AKLog` and `WKLog` both reach the same
// file on device, so writing to both put every line there twice.
#define AKIRLog(...) WKLog("input", __VA_ARGS__)

#import "../Controller/ControllerInspector.h"
#import "../Voice/VoiceSettings.h"
#import "InputElement.h"
#import "InputInterest.h"
#import "ControllerCommandIngress.h"

NSNotificationName const AKInputRouterLearningDidExpireNotification = @"AKInputRouterLearningDidExpire";

// One queue for every piece of input state. Game Controller does not promise which
// thread its handlers arrive on, the long-press timers run on the main queue, and both
// touch the same dictionaries - so the inspector marshals every report onto the main
// queue and this asserts it rather than hoping. The audit's point: callbacks mutating
// state while timers run on main is a race waiting for the right load.
static void AKAssertInputQueue(void) {
    dispatch_assert_queue(dispatch_get_main_queue());
}

static AKInputSource AKInputSourceFromName(NSString *name) {
    if ([name isEqualToString:@"keyboard"]) return AKInputSourceKeyboard;
    if ([name isEqualToString:@"mouse"]) return AKInputSourceMouse;
    if ([name isEqualToString:@"touchpad"]) return AKInputSourceTouchpad;
    if ([name isEqualToString:@"system"]) return AKInputSourceSystem;
    return AKInputSourceController;
}

@implementation AKInputEvent
- (NSString *)description {
    return [NSString stringWithFormat:@"%@/%@ %@=%.2f", self.device, self.element,
            self.pressed ? @"pressed" : @"released", self.value];
}
@end

// Per element state, so patterns can be measured rather than guessed.
@interface AKInputElementState : NSObject
@property (nonatomic) BOOL down;
// Set after push-to-talk begins so its release ends it exactly once.
@property (nonatomic) BOOL consumed;
@end
@implementation AKInputElementState
@end

// Read-write inside this file; the header exposes them read-only. `interest` is atomic so a
// GameController callback on another thread sees one whole snapshot, never a half-replaced one.
@interface AKInputRouter ()
@property (atomic, copy, readwrite) AKInputInterest *interest;
@property (atomic, strong, readwrite) AKTimingSamples *pointerTiming;
@property (nonatomic) NSTimeInterval pointerStart;
@end

// A display link needs an object to send its selector to; a block would be tidier and this is
// the smallest thing that works without one.
@interface AKPointerTickBox : NSObject
@property (nonatomic, copy) void (^block)(void);
+ (instancetype)boxWithBlock:(void (^)(void))block;
- (void)tick:(CADisplayLink *)link;
@end
@implementation AKPointerTickBox
+ (instancetype)boxWithBlock:(void (^)(void))block {
    AKPointerTickBox *box = [AKPointerTickBox new];
    box.block = block;
    return box;
}
- (void)tick:(CADisplayLink *)link { (void)link; if (self.block) self.block(); }
@end

@implementation AKInputRouter {
    NSMutableDictionary<NSString *, AKInputElementState *> *_states;  // "device|element"
    NSMutableSet<NSString *> *_down;                                  // "device|element", for chords
    BOOL _began;
    BOOL _learning;
    NSString *_learningDevice;
    // Every arming gets a number, so a deadline set for one arming cannot cancel a
    // later one that replaced it.
    NSUInteger _learningGeneration;
}

+ (instancetype)shared {
    static AKInputRouter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKInputRouter new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _states = [NSMutableDictionary dictionary];
        _down = [NSMutableSet set];
        _learningTimeout = 20.0;
        self.interest = [AKInputInterest none];
        self.pointerTiming = [AKTimingSamples new];
    }
    return self;
}

#pragma mark - What is worth reporting at all

// The snapshot the inspector asks about, rebuilt whenever the answer can have changed.
//
// The order matters: diagnostics admits everything (so an engineer sees the stream), an armed
// learner admits presses (so the user can choose a button), and otherwise only a mapped element
// exists at all. With voice off there is no mapping, so nothing is admitted - which is the state
// the app spends almost all of its time in.
- (void)refreshInterest {
    AKAssertInputQueue();
    AKInputInterest *snapshot;
    AKControllerInspector *inspector = AKControllerInspector.shared;
    if (inspector.diagnosticsEnabled) {
        snapshot = [AKInputInterest diagnostic];
    } else if (_learning) {
        snapshot = [AKInputInterest learning];
    } else if (!AKVoiceSettings.shared.enabled) {
        snapshot = [AKInputInterest none];
    } else {
        NSMutableSet<NSString *> *elements = [NSMutableSet set];
        // Every mapping that could apply: one keyed to a specific pad, and the one keyed to any
        // device. Being generous here is the safe direction - the router still checks the exact
        // trigger before it fires, and a mapped button that never arrives is dictation that
        // silently does not work.
        AKTrigger *any = [AKVoiceSettings.shared triggerForDevice:nil];
        if (any.element.length) [elements addObject:any.element];
        for (GCController *pad in GCController.controllers) {
            AKTrigger *trigger = [AKVoiceSettings.shared triggerForDevice:AKControllerIdentity(pad)];
            if (trigger.element.length) [elements addObject:trigger.element];
        }
        snapshot = elements.count ? [AKInputInterest mappedWithElements:elements] : [AKInputInterest none];
    }
    self.interest = snapshot;
    inspector.interest = snapshot;
}

#pragma mark - Pointer latency

// Pointer dispatch to the next opportunity to draw.
//
// This is not the Metal present timestamp - the performance overlay owns that number, from the
// adapter. It is the interval from the moment a pointer event reaches this app to the moment the
// display link that drives its UI ticks next, which is the upper bound on when that event could
// first have been on screen. It costs one display link while at most one pointer event is
// outstanding and nothing at all when no pointer is moving.
- (void)notePointerEvent {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (self) {
        if (_pointerStart > 0) {
            // A second event inside the same window measures the same frame; only the first
            // one is the interesting interval.
            return;
        }
        _pointerStart = now;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        __block CADisplayLink *link = nil;
        link = [CADisplayLink displayLinkWithTarget:[AKPointerTickBox boxWithBlock:^{
            NSTimeInterval end = NSProcessInfo.processInfo.systemUptime;
            NSTimeInterval start;
            @synchronized (self) { start = self->_pointerStart; self->_pointerStart = 0; }
            if (start > 0 && end >= start) [self->_pointerTiming record:(end - start) * 1000.0];
            [link invalidate];
        }] selector:@selector(tick:)];
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    });
}

- (BOOL)learning { return _learning; }

#pragma mark - Ownership

#pragma mark - Start

- (void)begin {
    AKAssertInputQueue();
    if (_began) return;
    _began = YES;

    __weak AKInputRouter *weakSelf = self;
    // The inspector already watches every element of every connected controller,
    // the keyboard and the mouse, and reports the system's Share signals. It is
    // the source this router does not have to duplicate.
    AKControllerInspector.shared.onInput = ^(NSString *element, double value, BOOL pressed) {
        AKControllerInspector *inspector = AKControllerInspector.shared;
        [weakSelf reportElement:element value:value pressed:pressed
                         device:inspector.currentDevice
                         source:AKInputSourceFromName(inspector.currentSourceName)];
    };
    [AKControllerInspector.shared begin];

    // The command path's destination. A mapped controller button arrives here through the bounded
    // ingress rather than through `onInput`: the same entry point and the same trigger semantics,
    // but one main-queue trip for the whole batch instead of one per event, with the diagnostics
    // behind it rather than in front of it. `onInput` still carries every other source.
    AKControllerCommandIngress.shared.deliver = ^(AKControllerCommand *command) {
        [weakSelf reportElement:command.element value:command.value pressed:command.pressed
                         device:command.device source:AKInputSourceController];
    };

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // A mapping is armed by a screen and lives here. Everything that can make the
    // armed state wrong clears it: the app going away, a pad going away, and the
    // deadline below.
    [center addObserver:self selector:@selector(appDidBackground:)
                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(padConnected:)
                   name:GCControllerDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(padDisconnected:)
                   name:GCControllerDidDisconnectNotification object:nil];
    // Any change to what the user has chosen re-decides which system gestures are
    // ours to hold. This is the only place that decides it.
    [center addObserver:self selector:@selector(applyMappings)
                   name:AKVoiceSettingsDidChangeNotification object:nil];
    // Switching diagnostics on or off changes what may reach the router at all.
    [center addObserver:self selector:@selector(refreshInterest)
                   name:AKInputDiagnosticsDidChangeNotification object:nil];
    [self applyMappings];
    [self refreshInterest];
    AKIRLog(@"input: router watching every source");
}

// A pad arriving means the stored mapping for it may now need its gesture released.
// It does NOT disarm the mapper: the user may be sitting there waiting to press a
// button on the pad that just connected, and cancelling then would make mapping
// impossible. Measured in the fixture on 2026-10-16, where a controller connects a
// moment after launch and the second mapping attempt was silently cancelled.
- (void)padConnected:(NSNotification *)notification {
    AKIRLog(@"input: %@", notification.name);
    [self applyMappings];
    [self refreshInterest];
}

// A pad leaving does disarm it: the element that was being learned no longer exists.
- (void)padDisconnected:(NSNotification *)notification {
    AKIRLog(@"input: %@", notification.name);
    [self cancelLearning];
    // A claimed button belongs to a connection, not to the app: when the pad goes, whatever was
    // being held back goes with it, immediately, rather than waiting for a setting to change.
    [AKVoiceSettings.shared releaseClaimsWithReason:@"disconnect"];
    [self applyMappings];
    [self refreshInterest];
}

// The app is going away. Nothing may be left held back, and nothing may be left listening: the
// two facts the completion gate asks to be proved for the background boundary.
- (void)appDidBackground:(NSNotification *)notification {
    (void)notification;
    AKIRLog(@"input: %@", notification.name);
    [self cancelLearning];
    [AKVoiceSettings.shared releaseClaimsWithReason:@"background"];
}

#pragma mark - Which system gestures are ours to hold

- (void)applyMappings {
    AKAssertInputQueue();
    AKControllerInspector *inspector = AKControllerInspector.shared;
    // Start from the system's own behaviour every time, then hand over only what the
    // user actually asked for. Any other order leaves a gesture released for a mapping
    // that no longer exists, or for a feature that is switched off.
    [inspector restoreAllSystemGestures];
    [self refreshInterest];
    if (!AKVoiceSettings.shared.enabled) return;

    for (GCController *pad in GCController.controllers) {
        NSString *device = AKControllerIdentity(pad);
        [AKVoiceSettings.shared adoptLegacyMappingForDevice:device vendor:pad.vendorName];
        AKTrigger *trigger = [AKVoiceSettings.shared triggerForDevice:device];
        if (!trigger) continue;
        // Only a controller button can have a system gesture to give up. A keyboard
        // key or a mouse button needs nothing from us.
        if (![trigger.element hasPrefix:@"controller.button."]) continue;
        // The claim the page cannot offer. A record written by a build that could claim is
        // honoured here or it is not, and either way the log says which: refusing is not a
        // failure of this build, it is the measurement in VoiceSettings.h said at the moment it
        // applies. The record is kept, so a build with a seam restores the player's choice.
        if ([AKVoiceSettings.shared isElement:trigger.element claimedForDevice:device]) {
            if (AKVoiceSettings.controllerClaimIsAvailable) {
                [AKVoiceSettings.shared claimElement:trigger.element device:device];
            } else {
                [AKControllerCommandIngress trace:@"claim restore element=%@ reason=route-failure",
                                              trigger.element];
            }
        }
        [inspector releaseSystemGestureForElement:trigger.element device:device];
    }

    // Two pads of the same model cannot be told apart by GameController, so one mapping
    // applies to both. That is a property of the platform, not a bug to fix quietly: say it
    // where someone will see it, because the alternative is a user wondering why the spare
    // pad starts dictation too.
    NSMutableDictionary<NSString *, NSNumber *> *models = [NSMutableDictionary dictionary];
    for (GCController *pad in GCController.controllers) {
        NSString *device = AKControllerIdentity(pad);
        models[device] = @([models[device] integerValue] + 1);
    }
    for (NSString *device in models) {
        if (models[device].integerValue < 2) continue;
        WKLog("input", @"%@ controllers of the same model are connected, so the mapping for %@",
              models[device], device);
        WKLog("input", @"applies to all of them: GameController does not identify individual pads");
        break;
    }
}

#pragma mark - Learning

// Long enough to find a button, short enough that a forgotten mapper is not left
// listening. The screen that armed it is told, so it can say so.
static NSTimeInterval const AKLearningTimeoutDefault = 20.0;

- (void)beginLearning {
    AKAssertInputQueue();
    _learning = YES;
    _learningDevice = nil;
    _learningGeneration++;
    [self refreshInterest];
    NSUInteger generation = _learningGeneration;
    NSTimeInterval timeout = _learningTimeout > 0 ? _learningTimeout : AKLearningTimeoutDefault;
    AKIRLog(@"input: learning — press the button you want to use");
    // A button iPadOS keeps for itself never reaches this router, so the page that asks for a
    // press would show nothing at all. The gestures are lent back the moment the choosing ends.
    [AKControllerInspector.shared beginReleasingForLearning];
    __weak AKInputRouter *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AKInputRouter *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_learningGeneration != generation) return;
        if (!strongSelf->_learning) return;
        [strongSelf cancelLearning];
        [NSNotificationCenter.defaultCenter postNotificationName:AKInputRouterLearningDidExpireNotification
                                                         object:strongSelf];
    });
}

- (void)cancelLearning {
    AKAssertInputQueue();
    if (!_learning) return;
    _learning = NO;
    _learningDevice = nil;
    // Bumped so the outstanding deadline cannot fire against a later arming.
    _learningGeneration++;
    [self refreshInterest];
    [AKControllerInspector.shared endReleasingForLearning];
    AKIRLog(@"input: learning cancelled; nothing was saved");
}

#pragma mark - The one entry point for every source

- (void)reportElement:(NSString *)element
                value:(double)value
              pressed:(BOOL)pressed
               device:(nullable NSString *)device
               source:(AKInputSource)source {
    AKAssertInputQueue();
    if (!element.length) return;
    if (source == AKInputSourceMouse || source == AKInputSourceTouchpad) [self notePointerEvent];

    AKInputEvent *event = [AKInputEvent new];
    event.source = source;
    event.device = device.length ? device : @"?";
    event.element = element;
    event.value = value;
    event.pressed = pressed;
    event.time = NSProcessInfo.processInfo.systemUptime;

    if (_learning && pressed) {
        // Whatever arrives first is what the user wants. This is how any button on any
        // controller becomes usable without a line of per-device code.
        AKTrigger *learned = [AKTrigger new];
        learned.element = element;
        // Only a placeholder: the pattern belongs to the mode, and the settings decide
        // it when they store this. The router does not write anything itself, so there
        // is one owner of what is remembered.
        learned.pattern = AKTriggerPatternPress;
        _learning = NO;
        _learningDevice = event.device;
        // The deadline that was armed for this mapping has nothing left to do.
        _learningGeneration++;
        [self refreshInterest];
        // The mapped element keeps its release - applyMappings decides that - and everything
        // else that was lent out goes back to the system.
        [AKControllerInspector.shared endReleasingForLearning];
        AKIRLog(@"input: learned %@ on %@", element, event.device);
        if (self.onLearned) self.onLearned(learned, event.device);
        return;
    }

    NSString *key = [NSString stringWithFormat:@"%@|%@", event.device, element];
    AKInputElementState *state = _states[key];
    if (!state) { state = [AKInputElementState new]; _states[key] = state; }

    if (pressed) { [self handlePress:event element:element key:key state:state]; }
    else { [self handleRelease:event element:element key:key state:state]; }
}

#pragma mark - Patterns

- (void)handlePress:(AKInputEvent *)event element:(NSString *)element key:(NSString *)key state:(AKInputElementState *)state {
    if (state.down) return; // Repeated samples are not another physical press.
    state.down = YES;
    [_down addObject:key];

    AKTrigger *trigger = [self triggerForDevice:event.device];
    // Nothing mapped, or the feature is off: the event is still tracked, so a release
    // still clears it, but nothing fires.
    if (!trigger) return;
    if (![trigger watchesElement:element]) return;

    switch (trigger.pattern) {
        case AKTriggerPatternPress:
            [self fire:trigger event:event];
            break;

        case AKTriggerPatternPushToTalk:
            // Press starts it; the release below finishes it. Marked as consumed
            // so the pair cannot overlap.
            if (state.consumed) return;
            state.consumed = YES;
            AKIRLog(@"input: trigger %@ began from %@", [trigger summary], event);
            if (self.onTriggerBegan) self.onTriggerBegan(trigger, event);
            break;


    }
}

- (void)handleRelease:(AKInputEvent *)event element:(NSString *)element key:(NSString *)key state:(AKInputElementState *)state {
    AKTrigger *trigger = [self triggerForDevice:event.device];
    if (state.consumed && trigger && trigger.pattern == AKTriggerPatternPushToTalk &&
        [trigger watchesElement:element]) {
        AKIRLog(@"input: trigger %@ ended from %@", [trigger summary], event);
        if (self.onTriggerEnded) self.onTriggerEnded(trigger, event);
    }
    state.down = NO;
    state.consumed = NO;
    [_down removeObject:key];
}

- (void)fire:(AKTrigger *)trigger event:(AKInputEvent *)event {
    AKIRLog(@"input: trigger %@ from %@", [trigger summary], event);
    if (self.onTrigger) self.onTrigger(trigger, event);
}

#pragma mark - Which trigger applies

- (AKTrigger *)triggerForDevice:(nullable NSString *)device {
    // The choice, and what happens before one is made, both belong to the voice
    // settings: they are what the user edits in the launcher.
    return [AKVoiceSettings.shared triggerForDevice:device];
}

@end
