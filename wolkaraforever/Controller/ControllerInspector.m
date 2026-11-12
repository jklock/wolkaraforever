// WolkaraForever layer: the controller inspector, in full.
//
// Why this exists: two buttons on the pad do nothing in this app — Share, and
// the extra top button — and we cannot tell whether the pad never sends them,
// whether iPadOS takes them for itself, or whether the game ignores them. Every
// decision we plan on top of pad input depends on which, so this reports what
// the pad has and what it does, rather than guessing.
//
// It reads. It never consumes an input, never writes to a pad, and changes
// nothing about how input reaches the game — with one deliberate exception:
// while this is active it clears the system's reservation on Share, because a
// reserved button cannot be observed at all. That is logged when it happens.

#import "ControllerInspector.h"

#import "../App/WolkaraForeverLog.h"

// One sink, not two.
//
// This used to write every line to `AKLog` and then to `WKLog` "so the console run and the file
// both see it". On a device both reach `native-guest.log`, so the 2026-11-04 run held every
// controller line twice: 12,658 in the `[ak]` channel and 12,658 in the `[input]` channel. The
// layer's own file is the one that survives the session, so that is the one used, and a
// diagnostic event is written once.
#define AKCILog(...) WKLog("input", __VA_ARGS__)

NSNotificationName const AKInputDiagnosticsDidChangeNotification = @"AKInputDiagnosticsDidChange";

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

#import "../Input/InputElement.h"

// How many events the on-screen panel keeps. The log itself is not limited.
static NSUInteger const AKCIHistoryLimit = 12;

// Stick axes stream continuously; without a threshold the panel becomes unreadable
// and the game pays for it. Values are reported when they cross into a different
// half-unit, so a stick reads as -2, -1, 0, 1, 2 rather than a river of floats.
static double const AKCIAxisBucket = 2.0;

// The model, not the device: see the header. GameController has no serial number to key a
// per-device map on, so this is the finest identity available and the docs say so.
NSString *AKControllerIdentity(GCController *pad) {
    if (!pad) return @"unknown";
    return [NSString stringWithFormat:@"%@.%@",
            AKInputIdentifierSlug(pad.vendorName ?: @"controller"),
            AKInputIdentifierSlug(pad.productCategory ?: @"unknown")];
}

// The methods the queue helpers below call. Declared here because the helpers are
// defined before the implementation, and a category on somebody else's class is the wrong
// tool for a private method.
@interface AKControllerInspector ()
- (void)markDevice:(NSString *)device name:(NSString *)name source:(NSString *)source;
- (void)noteElement:(NSString *)element value:(double)value pressed:(BOOL)pressed detail:(nullable NSString *)detail;
- (void)noteAxis:(NSString *)element value:(double)value;
- (void)noteIgnoredEvent;
- (void)noteHandoffSince:(NSTimeInterval)began;
- (void)submitContinuous:(NSString *)element value:(double)value pressed:(BOOL)pressed
                  device:(NSString *)device name:(NSString *)name source:(NSString *)source
                  detail:(nullable NSString *)detail;
- (void)flushContinuous;
@end

// Every report is delivered on the main queue, whatever thread the system called the
// handler on. This is what makes the router's state single-threaded by construction
// rather than by assumption: the audit's point was that input callbacks mutate mutable
// state while the long-press timers run on main, so one of the two had to move. Game
// Controller does not promise which thread its handlers arrive on, and the timers cannot
// be anywhere else, so the reports move.
//
// Before any of that, the interest snapshot decides whether the event exists at all. The
// check is a property read and a set lookup: no event object, no block, no log line for an
// element nobody asked about. That early return is the fix; the rest of this file is what
// keeps the remaining work small.
static void AKCIReport(AKControllerInspector *inspector, NSString *device, NSString *name,
                       NSString *source, NSString *element, double value, BOOL pressed,
                       NSString *detail) {
    if (!inspector) return;
    AKInputInterest *interest = inspector.interest;
    if (![interest admitsElement:element]) { [inspector noteIgnoredEvent]; return; }
    NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
    dispatch_async(dispatch_get_main_queue(), ^{
        [inspector noteHandoffSince:began];
        [inspector markDevice:device name:name source:source];
        [inspector noteElement:element value:value pressed:pressed detail:detail];
    });
}

// A continuous source is never forwarded as a stream. An interested one is coalesced to at most
// one pending report per source per display interval, keeping only the latest value; that is the
// only value a stick report can mean, and it is bounded work instead of unbounded work.
static void AKCIReportAxis(AKControllerInspector *inspector, NSString *device, NSString *name,
                           NSString *source, NSString *element, double value) {
    if (!inspector) return;
    AKInputInterest *interest = inspector.interest;
    if (![interest admitsElement:element]) { [inspector noteIgnoredEvent]; return; }
    [inspector submitContinuous:element value:value pressed:(value != 0)
                         device:device name:name source:source detail:nil];
}

@implementation AKControllerInspector {
    NSMutableArray<NSString *> *_history;
    NSMutableDictionary<NSString *, NSNumber *> *_axisBuckets;
    // Element ids whose system gesture this app has released, per device identity, so
    // the exact gesture can be handed back rather than guessed at.
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_releasedGestures;
    // The same, but a loan that ends when the user stops choosing a button.
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_learningRelease;
    UILabel *_panel;
    BOOL _began;
    NSString *_currentDevice;
    NSString *_currentDeviceName;
    NSString *_currentSourceName;
    // Coalescing state for continuous inputs. Guarded by @synchronized(self) because it is
    // written from GameController's threads and drained on the main queue.
    NSMutableDictionary<NSString *, NSDictionary *> *_pendingContinuous;
    BOOL _flushScheduled;
    AKTimingSamples *_callbackTiming, *_handoffTiming;
    NSUInteger _admitted, _ignored, _coalesced;
}

- (NSString *)currentDevice { return _currentDevice; }
- (NSString *)currentDeviceName { return _currentDeviceName; }
- (NSString *)currentSourceName { return _currentSourceName; }

- (AKTimingSamples *)callbackTiming { return _callbackTiming; }
- (AKTimingSamples *)handoffTiming { return _handoffTiming; }
- (NSUInteger)admittedEvents { return _admitted; }
- (NSUInteger)ignoredEvents { return _ignored; }
- (NSUInteger)coalescedEvents { return _coalesced; }

// Diagnostics are a stored preference, not a transient flag: an engineer who switches them on
// expects them to survive the relaunch that follows a crash, and a user who switches them off
// expects the app to stop writing.
static NSString *const AKCIDiagnosticsKey = @"WolkaraForeverInputDiagnostics";

- (BOOL)diagnosticsEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:AKCIDiagnosticsKey];
}
- (void)setDiagnosticsEnabled:(BOOL)enabled {
    if (enabled == self.diagnosticsEnabled) return;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:AKCIDiagnosticsKey];
    if (!enabled) [self resetDiagnostics];
    AKCILog(@"inspector: diagnostics %@", enabled ? @"on" : @"off");
    // The router owns the interest snapshot, so it has to hear about this. A notification keeps
    // the two files from importing each other.
    [NSNotificationCenter.defaultCenter postNotificationName:AKInputDiagnosticsDidChangeNotification
                                                      object:self];
}

- (void)resetDiagnostics {
    [_callbackTiming reset];
    [_handoffTiming reset];
    _admitted = 0; _ignored = 0; _coalesced = 0;
    [_axisBuckets removeAllObjects];
}

- (void)noteIgnoredEvent { _ignored += 1; }

- (void)noteHandoffSince:(NSTimeInterval)began {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (began > 0 && now >= began) [_handoffTiming record:(now - began) * 1000.0];
    _admitted += 1;
}

- (void)submitContinuous:(NSString *)element value:(double)value pressed:(BOOL)pressed
                  device:(NSString *)device name:(NSString *)name source:(NSString *)source
                  detail:(NSString *)detail {
    NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
    BOOL schedule = NO;
    @synchronized (self) {
        if (!_pendingContinuous) _pendingContinuous = [NSMutableDictionary dictionary];
        _pendingContinuous[element] = @{ @"value": @(value), @"pressed": @(pressed),
                                         @"device": device ?: @"", @"name": name ?: @"",
                                         @"source": source ?: @"", @"detail": detail ?: @"",
                                         @"began": @(began) };
        _coalesced += 1;
        if (!_flushScheduled) { _flushScheduled = YES; schedule = YES; }
    }
    if (!schedule) return;
    // One display interval at most. 120 Hz panels still get one report per interval, and a
    // source that reports a thousand times between frames still costs one.
    NSInteger rate = 60;
    if (@available(iOS 15.0, *)) rate = MAX(30, (NSInteger)UIScreen.mainScreen.maximumFramesPerSecond);
    NSTimeInterval interval = 1.0 / (double)rate;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self flushContinuous]; });
}

- (void)flushContinuous {
    NSDictionary *pending = nil;
    @synchronized (self) {
        pending = _pendingContinuous;
        _pendingContinuous = nil;
        _flushScheduled = NO;
    }
    for (NSString *element in pending) {
        NSDictionary *item = pending[element];
        [self noteHandoffSince:[item[@"began"] doubleValue]];
        [self markDevice:item[@"device"] name:item[@"name"] source:item[@"source"]];
        [self noteElement:element value:[item[@"value"] doubleValue]
                  pressed:[item[@"pressed"] boolValue] detail:item[@"detail"]];
    }
}

- (BOOL)currentControllerDeclaresShare {
    for (GCController *pad in GCController.controllers)
        if (pad.physicalInputProfile.buttons[GCInputButtonShare]) return YES;
    return NO;
}

+ (instancetype)shared {
    static AKControllerInspector *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKControllerInspector new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _history = [NSMutableArray array];
        _axisBuckets = [NSMutableDictionary dictionary];
        _releasedGestures = [NSMutableDictionary dictionary];
        _callbackTiming = [AKTimingSamples new];
        _handoffTiming = [AKTimingSamples new];
        // Nothing is interesting until something says so. The router publishes a snapshot as
        // soon as it starts; before then, an event exists only if the user asked for one.
        _interest = [AKInputInterest none];
    }
    return self;
}

#pragma mark - Start

- (void)begin {
    if (_began) { [self logInventories]; return; }
    _began = YES;

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(padsChanged:) name:GCControllerDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(padsChanged:) name:GCControllerDidDisconnectNotification object:nil];
    if (@available(iOS 14.0, *)) {
        [center addObserver:self selector:@selector(padsChanged:) name:GCKeyboardDidConnectNotification object:nil];
        [center addObserver:self selector:@selector(padsChanged:) name:GCKeyboardDidDisconnectNotification object:nil];
        [center addObserver:self selector:@selector(padsChanged:) name:GCMouseDidConnectNotification object:nil];
        [center addObserver:self selector:@selector(padsChanged:) name:GCMouseDidDisconnectNotification object:nil];
    }

    AKCILog(@"inspector: watching for controller input");

    // The pad's Share button is a Print Screen key, and iPadOS spends that key on
    // the screenshot gesture before any app is offered it. The screenshot itself
    // is announced to the app, though, so Share is reachable after all: this is
    // the only route to it that the system provides.
    [center addObserver:self selector:@selector(screenshotTaken:) name:UIApplicationUserDidTakeScreenshotNotification object:nil];
    // And the hold gesture, which the system spends on screen recording.
    [center addObserver:self selector:@selector(screenCaptureChanged:) name:UIScreenCapturedDidChangeNotification object:nil];
    [self attachEverything];
    [self logInventories];
}

- (void)screenshotTaken:(NSNotification *)notification {
    (void)notification;
    // The pad's Share button is a Print Screen key, and iPadOS spends that key on the
    // screenshot gesture before any app is offered it - so a screenshot is as close to
    // "the pad's Share was pressed" as the system gets.
    //
    // It is recorded and **not** reported as input. The first version offered it as
    // `system.screenshot` for the user to map, and the remediation review is right that
    // this is not enough: nothing in the notification says whether a pad or a thumb on
    // the screen produced it, so mapping it only moves the guess to the user. A button
    // that can start the microphone has to be one we know was pressed.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self markSystemDevice];
        // A lifecycle fact, so it stays in the durable log whether or not diagnostics are on.
        AKCILog(@"inspector: system.screenshot (recorded; not an input)");
        [self recordLine:@"system.screenshot (recorded; not an input)"];
    });
}

- (void)screenCaptureChanged:(NSNotification *)notification {
    (void)notification;
    BOOL captured = UIScreen.mainScreen.isCaptured;
    [self markSystemDevice];
    AKCILog(@"inspector: screen capture changed, captured=%d", captured);
    // Recorded, never reported as input.
    //
    // This used to go through reportLine: as "Share held", on the reasoning that
    // iPadOS spends the pad's Share hold on screen recording, so seeing a capture
    // start meant Share was held. That is only true when the pad started it, and this
    // notification cannot tell us who did. Measured on 2026-10-16: with the iPad being
    // captured from a Mac, `isCaptured` was already 1, the change fired about a tenth
    // of a second after every launch, and the launcher started dictating by itself -
    // six times in one log, with nobody touching anything.
    [self recordLine:captured ? @"system.capture on" : @"system.capture off"];
}

// A system signal belongs to no controller, but it is still attributed to the pad
// when there is one, so a per-controller choice applies to it.
- (void)markSystemDevice {
    GCController *pad = GCController.controllers.firstObject;
    [self markDevice:pad ? AKControllerIdentity(pad) : @"system"
                name:pad.vendorName ?: @"System"
              source:@"system"];
}

- (void)padsChanged:(NSNotification *)notification {
    AKCILog(@"inspector: %@", notification.name);
    if ([notification.name isEqualToString:GCControllerDidDisconnectNotification]) {
        // A released gesture belongs to a connection, not to a pad forever. Forget it
        // so a reconnect starts from the system's own behaviour, and so the router
        // re-decides from the stored mapping rather than from stale state.
        GCController *pad = notification.object;
        NSString *identity = pad ? AKControllerIdentity(pad) : nil;
        if (identity) [_releasedGestures removeObjectForKey:identity];
        else [_releasedGestures removeAllObjects];
    }
    [self attachEverything];
    [self logInventories];
}

#pragma mark - The system's gestures, released only on request

- (nullable GCControllerButtonInput *)buttonForElement:(NSString *)element device:(nullable NSString *)device inPad:(GCController *)pad {
    if (device.length && ![AKControllerIdentity(pad) isEqualToString:device]) return nil;
    for (NSString *name in pad.physicalInputProfile.buttons)
        if ([AKInputElementForControllerButton(name) isEqualToString:element])
            return pad.physicalInputProfile.buttons[name];
    return nil;
}

- (BOOL)releaseSystemGestureForElement:(NSString *)element device:(nullable NSString *)device {
    BOOL released = NO;
    for (GCController *pad in GCController.controllers) {
        GCControllerButtonInput *button = [self buttonForElement:element device:device inPad:pad];
        if (!button) continue;
        if (button.preferredSystemGestureState != GCSystemGestureStateDisabled) {
            button.preferredSystemGestureState = GCSystemGestureStateDisabled;
            AKCILog(@"inspector: released the system gesture on %@ for %@, because the user mapped it", element, AKControllerIdentity(pad));
        }
        NSString *identity = AKControllerIdentity(pad);
        if (!_releasedGestures[identity]) _releasedGestures[identity] = [NSMutableSet set];
        [_releasedGestures[identity] addObject:element];
        released = YES;
    }
    return released;
}

- (void)restoreSystemGestureForElement:(NSString *)element device:(nullable NSString *)device {
    for (GCController *pad in GCController.controllers) {
        NSString *identity = AKControllerIdentity(pad);
        if (device.length && ![identity isEqualToString:device]) continue;
        if (![_releasedGestures[identity] containsObject:element]) continue;
        GCControllerButtonInput *button = [self buttonForElement:element device:identity inPad:pad];
        // Back to what the system had, which is "the gesture is mine".
        if (button.preferredSystemGestureState == GCSystemGestureStateDisabled)
            button.preferredSystemGestureState = GCSystemGestureStateEnabled;
        [_releasedGestures[identity] removeObject:element];
        AKCILog(@"inspector: gave the system its gesture back on %@ for %@", element, identity);
    }
}

- (void)restoreAllSystemGestures {
    for (GCController *pad in GCController.controllers) {
        NSString *identity = AKControllerIdentity(pad);
        for (NSString *element in [_releasedGestures[identity] allObjects]) {
            GCControllerButtonInput *button = [self buttonForElement:element device:identity inPad:pad];
            if (button.preferredSystemGestureState == GCSystemGestureStateDisabled)
                button.preferredSystemGestureState = GCSystemGestureStateEnabled;
        }
    }
    NSUInteger count = _releasedGestures.count;
    [_releasedGestures removeAllObjects];
    if (count) AKCILog(@"inspector: every released system gesture has been given back");
}

#pragma mark - Learning: releasing enough to hear the press

// Every button of every connected pad whose press the system would keep, by name, per device.
// Kept apart from _releasedGestures on purpose: that one is the user's decisions and survives
// learning, this one is a loan that ends when the choosing does.
- (void)beginReleasingForLearning {
    if (_learningRelease) return;
    _learningRelease = [NSMutableDictionary dictionary];
    for (GCController *pad in GCController.controllers) {
        NSString *identity = AKControllerIdentity(pad);
        for (NSString *name in pad.physicalInputProfile.buttons) {
            GCControllerButtonInput *button = pad.physicalInputProfile.buttons[name];
            if (button.preferredSystemGestureState == GCSystemGestureStateDisabled) continue;
            button.preferredSystemGestureState = GCSystemGestureStateDisabled;
            if (!_learningRelease[identity]) _learningRelease[identity] = [NSMutableSet set];
            [_learningRelease[identity] addObject:AKInputElementForControllerButton(name)];
            AKCILog(@"inspector: released the system gesture on %@ for %@ while the user chooses a button",
                    AKInputElementForControllerButton(name), identity);
        }
    }
}

- (void)endReleasingForLearning {
    if (!_learningRelease) return;
    for (GCController *pad in GCController.controllers) {
        NSString *identity = AKControllerIdentity(pad);
        for (NSString *element in [_learningRelease[identity] allObjects]) {
            // A button the user went on to map keeps its release; the settings own that one
            // and would otherwise have its decision undone here.
            if ([_releasedGestures[identity] containsObject:element]) continue;
            GCControllerButtonInput *button = [self buttonForElement:element device:identity inPad:pad];
            if (button.preferredSystemGestureState == GCSystemGestureStateDisabled)
                button.preferredSystemGestureState = GCSystemGestureStateEnabled;
        }
    }
    NSUInteger count = _learningRelease.count;
    _learningRelease = nil;
    if (count) AKCILog(@"inspector: the gestures lent out for choosing a button are back with the system");
}

#pragma mark - Inventories: what does this pad actually have?

- (void)logInventories {
    NSArray<GCController *> *pads = GCController.controllers;
    AKCILog(@"inspector: %lu controller(s) connected", (unsigned long)pads.count);
    for (GCController *pad in pads) [self describe:pad];

    if (@available(iOS 14.0, *)) {
        // The SDK coalesces every connected keyboard into one object, and
        // reports the current pointing device the same way.
        GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
        GCMouse *mouse = GCMouse.current;
        AKCILog(@"inspector: keyboard=%@ mouse=%@",
                keyboard ? (keyboard.vendorName ?: @"present") : @"none",
                mouse ? (mouse.vendorName ?: @"present") : @"none");
        // Which keys does the system say this keyboard has? A GameSir pad sends
        // its Share button as a Print Screen key, so this is where we find out
        // whether that key exists to us at all, before anyone presses it.
        if (keyboard) {
            GCKeyboardInput *input = keyboard.keyboardInput;
            NSArray<NSString *> *names = [input.buttons.allKeys sortedArrayUsingSelector:@selector(compare:)];
            NSArray<NSString *> *printScreen = [names filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"SELF CONTAINS[c] 'print'"]];
            AKCILog(@"inspector: keyboard keys=%lu printScreen=%@",
                    (unsigned long)names.count,
                    printScreen.count ? [printScreen componentsJoinedByString:@","] : @"absent");
            AKCILog(@"inspector: keyboard key names=%@", [names componentsJoinedByString:@" | "]);
            // Attach to the object we just enumerated, not to whichever one
            // existed when we started: the coalesced keyboard is replaced when a
            // keyboard comes or goes, and a handler left on the old object would
            // make every press look like silence.
            [self attachKeyboard:keyboard];
        }
    }
    AKCILog(@"inspector: watching controller, keyboard, screenshot and capture");
}

- (void)describe:(GCController *)pad {
    GCPhysicalInputProfile *profile = pad.physicalInputProfile;
    AKCILog(@"inspector: pad name=%@ vendor=%@ category=%@ profile=%@",
            pad.vendorName ?: @"?", pad.vendorName ?: @"?", pad.productCategory ?: @"?", NSStringFromClass(profile.class));

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *name in profile.buttons) {
        GCControllerButtonInput *button = profile.buttons[name];
        [lines addObject:[NSString stringWithFormat:@"button %@%@", name, button.isAnalog ? @" [analog]" : @""]];
    }
    for (NSString *name in profile.axes) {
        [lines addObject:[NSString stringWithFormat:@"axis %@", name]];
    }
    for (NSString *name in profile.dpads) {
        [lines addObject:[NSString stringWithFormat:@"dpad %@", name]];
    }
    for (NSString *name in profile.touchpads) {
        [lines addObject:[NSString stringWithFormat:@"touchpad %@", name]];
    }
    AKCILog(@"inspector: elements (%lu): %@", (unsigned long)lines.count, [lines componentsJoinedByString:@", "]);

    // Aliases matter: a pad that reports the same control under two names is
    // telling us something about how it presents itself. The sets hold element
    // objects, so the difference in count is what is reportable.
    AKCILog(@"inspector: buttons=%lu (all=%lu) axes=%lu (all=%lu) dpads=%lu (all=%lu)",
            (unsigned long)profile.buttons.count, (unsigned long)profile.allButtons.count,
            (unsigned long)profile.axes.count, (unsigned long)profile.allAxes.count,
            (unsigned long)profile.dpads.count, (unsigned long)profile.allDpads.count);

    // The two buttons in question, by name and by profile property.
    GCControllerButtonInput *share = profile.buttons[GCInputButtonShare];
    AKCILog(@"inspector: share=%@ gesture=%@", share ? @"present" : @"absent",
            share ? (share.preferredSystemGestureState == GCSystemGestureStateDisabled ? @"disabled" : @"system") : @"n/a");

    if ([profile isKindOfClass:GCXboxGamepad.class]) {
        GCXboxGamepad *xbox = (GCXboxGamepad *)profile;
        NSMutableArray<NSString *> *paddles = [NSMutableArray array];
        if (xbox.paddleButton1) [paddles addObject:@"P1"];
        if (xbox.paddleButton2) [paddles addObject:@"P2"];
        if (xbox.paddleButton3) [paddles addObject:@"P3"];
        if (xbox.paddleButton4) [paddles addObject:@"P4"];
        AKCILog(@"inspector: xbox paddles=%@ share=%@", paddles.count ? [paddles componentsJoinedByString:@","] : @"none",
                xbox.buttonShare ? @"present" : @"absent");
    }
    if ([profile isKindOfClass:GCExtendedGamepad.class]) {
        GCExtendedGamepad *extended = (GCExtendedGamepad *)profile;
        AKCILog(@"inspector: menu=%@ options=%@ l3=%@ r3=%@",
                extended.buttonMenu ? @"y" : @"n",
                extended.buttonOptions ? @"y" : @"n",
                extended.leftThumbstickButton ? @"y" : @"n",
                extended.rightThumbstickButton ? @"y" : @"n");
    }
}

#pragma mark - Attaching: every element, live

- (void)attachEverything {
    for (GCController *pad in GCController.controllers) [self attachPad:pad];
    if (@available(iOS 14.0, *)) {
        GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
        if (keyboard) [self attachKeyboard:keyboard];
        GCMouse *mouse = GCMouse.current;
        if (mouse) [self attachMouse:mouse];
    }
}

- (void)attachPad:(GCController *)pad {
    GCPhysicalInputProfile *profile = pad.physicalInputProfile;
    // Carried with every report from this pad. The identity is what a mapping is
    // remembered against; the name is only ever shown to a person.
    NSString *device = AKControllerIdentity(pad);
    NSString *deviceName = pad.vendorName ?: @"Controller";
    __weak AKControllerInspector *weakSelf = self;

    for (NSString *name in profile.buttons) {
        GCControllerButtonInput *button = profile.buttons[name];
        NSString *element = AKInputElementForControllerButton(name);
        button.pressedChangedHandler = ^(GCControllerButtonInput *input, float value, BOOL pressed) {
            (void)input;
            AKCIReport(weakSelf, device, deviceName, @"controller", element, value, pressed, nil);
        };
    }
    for (NSString *name in profile.axes) {
        GCControllerAxisInput *axis = profile.axes[name];
        NSString *element = AKInputElementForControllerAxis(name);
        axis.valueChangedHandler = ^(GCControllerAxisInput *input, float value) {
            (void)input;
            AKCIReportAxis(weakSelf, device, deviceName, @"controller", element, value);
        };
    }
    for (NSString *name in profile.dpads) {
        GCControllerDirectionPad *dpad = profile.dpads[name];
        dpad.valueChangedHandler = ^(GCControllerDirectionPad *input, float x, float y) {
            (void)input;
            // The direction is the name; where the thumb actually is goes in the
            // detail. As a name it changed with every movement, so nothing learned
            // from one press could ever match the next one.
            NSString *element = AKInputElementForDirectionPad(name, x, y);
            AKCIReport(weakSelf, device, deviceName, @"controller", element, 1, (x != 0 || y != 0),
                       [NSString stringWithFormat:@"x=%.2f y=%.2f", x, y]);
        };
    }
    for (NSString *name in profile.touchpads) {
        GCControllerTouchpad *touchpad = profile.touchpads[name];
        NSString *down = AKInputElementForTouchpad(name, @"down");
        NSString *up = AKInputElementForTouchpad(name, @"up");
        NSString *moved = AKInputElementForTouchpad(name, @"moved");
        touchpad.touchDown = ^(GCControllerTouchpad *input, float x, float y, float buttonValue, BOOL buttonPressed) {
            (void)input; (void)buttonValue;
            AKCIReport(weakSelf, device, deviceName, @"touchpad", down, 1, YES,
                       [NSString stringWithFormat:@"x=%.2f y=%.2f button=%d", x, y, buttonPressed]);
        };
        touchpad.touchUp = ^(GCControllerTouchpad *input, float x, float y, float buttonValue, BOOL buttonPressed) {
            (void)input; (void)buttonValue;
            AKCIReport(weakSelf, device, deviceName, @"touchpad", up, 0, NO,
                       [NSString stringWithFormat:@"x=%.2f y=%.2f button=%d", x, y, buttonPressed]);
        };
        touchpad.touchMoved = ^(GCControllerTouchpad *input, float x, float y, float buttonValue, BOOL buttonPressed) {
            (void)input; (void)buttonValue; (void)buttonPressed;
            AKCIReport(weakSelf, device, deviceName, @"touchpad", moved, 0, NO,
                       [NSString stringWithFormat:@"x=%.2f y=%.2f", x, y]);
        };
    }

    // The inventory is read-only. This used to disable Share's system gesture here,
    // for every pad that declared one, at startup - which changed how the controller
    // behaved before the user had asked for anything, and is the second of the
    // audit's release blockers. The gesture is now released only by
    // -releaseSystemGestureForElement:device:, which the router calls because the
    // user mapped that element, and it is given back afterwards.
    GCControllerButtonInput *share = profile.buttons[GCInputButtonShare];
    if (share) {
        AKCILog(@"inspector: %@ declares Share; its system gesture is %@ until mapped",
                deviceName,
                share.preferredSystemGestureState == GCSystemGestureStateDisabled ? @"already released" : @"still the system's");
    }
}

- (void)attachKeyboard:(GCKeyboard *)keyboard API_AVAILABLE(ios(14.0)) {
    __weak AKControllerInspector *weakSelf = self;
    // Read before the block: capturing the keyboard itself in its own handler is a
    // retain cycle, and the handler only needs its name.
    NSString *name = keyboard.vendorName ?: @"Keyboard";
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *input, GCDeviceButtonInput *key, GCKeyCode keyCode, BOOL pressed) {
        (void)input; (void)key;
        AKCIReport(weakSelf, @"keyboard", name, @"keyboard",
                   AKInputElementForKeyboardKey(keyCode), (pressed ? 1 : 0), pressed, nil);
    };
}

- (void)attachMouse:(GCMouse *)mouse API_AVAILABLE(ios(14.0)) {
    __weak AKControllerInspector *weakSelf = self;
    GCMouseInput *input = mouse.mouseInput;
    NSString *name = mouse.vendorName ?: @"Mouse";
    // The AppKit bridge owns movement and per-button callbacks. Observe the profile
    // separately so refreshing the inspector cannot disconnect held-button dragging.
    input.valueDidChangeHandler = ^(GCPhysicalInputProfile *profile, GCControllerElement *element) {
        GCMouseInput *mouseInput = (GCMouseInput *)profile;
        NSString *buttonName = element == mouseInput.leftButton ? @"left" :
                               element == mouseInput.rightButton ? @"right" :
                               element == mouseInput.middleButton ? @"middle" : nil;
        if (!buttonName) return;
        GCControllerButtonInput *button = (GCControllerButtonInput *)element;
        AKCIReport(weakSelf, @"mouse", name, @"mouse", AKInputElementForMouseButton(buttonName),
                   button.value, button.isPressed, nil);
    };
}

#pragma mark - Reporting

// Called from the input handlers so that every report carries the device it came
// from. A message to a weak reference is safe where reading an ivar through one is
// not. The identity is what a mapping is stored against; the name is for people.
- (void)markDevice:(NSString *)device name:(NSString *)name source:(NSString *)source {
    _currentDevice = device;
    _currentDeviceName = name;
    _currentSourceName = source;
}

- (void)noteElement:(NSString *)element value:(double)value pressed:(BOOL)pressed detail:(nullable NSString *)detail {
    NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
    NSString *line = [NSString stringWithFormat:@"%@ %@=%.2f", element, pressed ? @"pressed" : @"value", value];
    if (detail.length) line = [line stringByAppendingFormat:@" %@", detail];
    [self noteAdmission:began];
    [self reportLine:line element:element value:value pressed:pressed];
}

- (void)noteAxis:(NSString *)element value:(double)value {
    NSInteger bucket = (NSInteger)lround(value * AKCIAxisBucket);
    NSNumber *last = _axisBuckets[element];
    if (last && last.integerValue == bucket) return;
    _axisBuckets[element] = @(bucket);
    [self reportLine:[NSString stringWithFormat:@"%@=%.2f", element, value]
              element:element value:value pressed:(bucket != 0)];
}

- (void)noteAdmission:(NSTimeInterval)began {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (began > 0 && now >= began) [_callbackTiming record:(now - began) * 1000.0];
}

- (void)reportLine:(NSString *)line element:(NSString *)element value:(double)value pressed:(BOOL)pressed {
    [self recordLine:line];
    if (self.onInput) self.onInput(element, value, pressed);
}

// The panel's own history and the log, without pretending to be an input. Some of
// what the inspector sees is a fact about the system rather than a button, and a
// fact must not start dictation.
//
// Two rules, both from the 2026-11-04 run:
//   * One sink, and only while diagnostics are on. In ordinary play nothing here is written.
//   * The panel is updated only while it is on screen. The old code enqueued a main-queue block
//     for a panel that did not exist, once per event, which is a quarter of the work in that
//     run's log for no output at all.
- (void)recordLine:(NSString *)line {
    if (self.diagnosticsEnabled) AKCILog(@"%@", line);
    if (!self.panelVisible) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_panel) return;
        [self->_history addObject:line];
        while (self->_history.count > AKCIHistoryLimit) [self->_history removeObjectAtIndex:0];
        self->_panel.text = [self->_history componentsJoinedByString:@"\n"];
        [self->_panel sizeToFit];
    });
}

#pragma mark - On-screen panel

- (void)showPanel:(BOOL)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!visible) {
            [self->_panel removeFromSuperview];
            self->_panel = nil;
            self.panelVisible = NO;
            [self->_history removeAllObjects];
            return;
        }
        if (self->_panel) return;
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        UILabel *label = [UILabel new];
        label.numberOfLines = AKCIHistoryLimit;
        label.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        label.userInteractionEnabled = NO;
        label.text = @"controller inspector: waiting for input";
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [window addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:8],
            [label.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-8],
        ]];
        self->_panel = label;
        // Set last: from this moment the history is worth maintaining.
        self.panelVisible = YES;
    });
}

@end
