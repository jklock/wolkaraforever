#import "ControllerManager.h"

#import "ControllerIdentity.h"

#import "../App/WolkaraForeverLog.h"
#import "../Input/InputElement.h"

// When the handler was entered, for the latency measurement. Thread-local because handlers for
// different pads can run on different threads at the same moment.
static _Thread_local uint64_t AKCMEntryTicks;


#import <GameController/GameController.h>
#include <mach/mach_time.h>
#import <UIKit/UIKit.h>

#if __has_include("AKSupport.h")
#import "AKSupport.h"
#define AKCMLog(...) do { AKLog(__VA_ARGS__); WKLog("input", __VA_ARGS__); } while (0)
#else
#define AKCMLog(...) do { NSLog(@"[ak] %@", [NSString stringWithFormat:__VA_ARGS__]); WKLog("input", __VA_ARGS__); } while (0)
#endif

NSNotificationName const AKControllerManagerDidChangeNotification = @"AKControllerManagerDidChange";

NSNotificationName const AKControllerRouteStateNotification = @"AKControllerRouteState";
NSNotificationName const AKControllerRouteQueryNotification = @"AKControllerRouteQuery";
NSNotificationName const AKControllerRouteValueNotification = @"AKControllerRouteValue";
NSNotificationName const AKControllerRoutePositionNotification = @"AKControllerRoutePosition";
NSNotificationName const AKControllerRouteReleaseNotification = @"AKControllerRouteRelease";
NSString *const AKControllerRouteElementKey = @"element";
NSString *const AKControllerRouteValueKey = @"value";
NSString *const AKControllerRouteXKey = @"x";
NSString *const AKControllerRouteYKey = @"y";
NSString *const AKControllerRouteEnabledKey = @"enabled";

NSNotificationName const AKControllerVirtualPadDidChangeNotification = @"AKControllerVirtualPadDidChange";
NSString *const AKControllerVirtualPadConnectedKey = @"connected";
NSString *const AKControllerVirtualPadControllerKey = @"controller";
NSString *const AKControllerVirtualPadErrorKey = @"error";

NSNotificationName const AKControllerGuestViewRequestNotification = @"AKControllerGuestViewRequest";
NSNotificationName const AKControllerGuestViewDidChangeNotification = @"AKControllerGuestViewDidChange";
NSString *const AKControllerGuestViewControllersKey = @"controllers";
NSString *const AKControllerGuestViewRoutingKey = @"routing";
NSNotificationName const AKControllerGuestFacadePresentNotification = @"AKControllerGuestFacadePresent";
NSNotificationName const AKControllerGuestFacadeQueryNotification = @"AKControllerGuestFacadeQuery";

// Where the switch and the remembered model names live. WolkaraForever's own defaults:
// nothing here reads or writes WoW's bindings, GamePadConfig_*.json or Config.wtf.
static NSString *const AKControllerRoutingDefaultsKey = @"WolkaraForeverControllerRouting";
static NSString *const AKControllerModelsDefaultsKey = @"WolkaraForeverControllerModels";

// A stick has to be moved this far before a learn press counts as "the user moved it".
// The same 0.35 InputElement uses to call a D-pad direction a direction, so the log and
// the learn flow agree about when a stick has actually moved.
static double const AKControllerLearnAxisThreshold = 0.35;

// Routing a stick streams continuously; one notification per sample would flood the
// adapter for a value the guest cannot show. One part in 128 is finer than an axis
// reports and coarse enough to stop the stream being a queue.
static double const AKControllerAxisQuantum = 1.0 / 128.0;

// Buttons iPadOS may claim for a system gesture. Only these are ever released for
// routing; an ordinary face button needs nothing from us, and releasing gestures the
// feature does not need is what the 2026-10-16 audit called out.
static NSSet<NSString *> *AKControllerReservedElements(void) {
    static NSSet<NSString *> *reserved;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reserved = [NSSet setWithArray:@[@"controller.button.menu", @"controller.button.options",
                                         @"controller.button.home", @"controller.button.share"]];
    });
    return reserved;
}

static BOOL AKControllerElementIsReserved(NSString *element) {
    return [AKControllerReservedElements() containsObject:element];
}

// Declared before the report helpers below, which send them from GameController's own
// threads. They are private: the public header is the page's and the fixture's contract.
@interface AKControllerManager ()
- (void)noteButtonValue:(double)value element:(NSString *)element device:(NSString *)device;
- (void)noteAxisPosition:(CGPoint)position element:(NSString *)element device:(NSString *)device;
- (void)learnFromSource:(NSString *)source device:(NSString *)device;
@end

// GameController does not promise which thread a handler arrives on, and every piece of
// state here is touched by UIKit notifications on main. Reports move to main, as they did
// in the inspector, so all of this state is single-threaded by construction.
// Straight through, on the thread GameController called us on. The queue hop that used to be
// here was a whole main-queue turn before the adapter wrote the value - on a queue that is also
// servicing the UI and the guest. Routing is measured (--selftest=controller-latency) precisely
// so this cannot quietly come back.
static void AKCMReport(AKControllerManager *manager, NSString *device, NSString *name,
                       NSString *source, NSString *element, double value, BOOL pressed) {
    [manager reportElement:element value:value pressed:pressed
                    device:device deviceName:name source:source];
}

static void AKCMReportAxis(AKControllerManager *manager, NSString *device, NSString *name,
                           NSString *stableElement, CGPoint position) {
    [manager reportAxis:stableElement position:position device:device deviceName:name];
}

#pragma mark - Model

// Built here and read by the page, so the write side stays in this file.
@interface AKControllerModel ()
@property (nonatomic, copy, readwrite) NSString *identity;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, readwrite) NSUInteger count;
@property (nonatomic, copy, readwrite) NSArray<AKControllerBinding *> *bindings;
@property (nonatomic, readwrite) BOOL customised;
@end

@implementation AKControllerModel
@end

#pragma mark - Manager

@implementation AKControllerManager {
    BOOL _began;
    BOOL _enabled;
    BOOL _virtualFailed;
    BOOL _awaitingVirtualPad;
    // Set when the guest-facing GameController adapter announces itself. Routing cannot
    // start without it: the guest would see both pads.
    BOOL _guestFacadePresent;
    // What was connected when the adapter was asked for the virtual pad. Anything that
    // appears during that window is ours, not hardware - which is how a pad that only
    // exists because this feature asked for one is kept out of the hardware list.
    NSArray<GCController *> *_controllersWhenAsking;
    GCController *_virtualController;
    NSString *_virtualError;

    // What the pad is doing now, per model. Buttons keep their last value so a routing
    // change mid-press can replay it rather than guess; sticks keep their position.
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *_buttonValues;
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSValue *> *> *_axisValues;
    // The last value actually sent to the virtual pad, so a change is a change.
    NSMutableDictionary<NSString *, NSNumber *> *_routedButtons;
    NSMutableDictionary<NSString *, NSValue *> *_routedAxes;

    // Gesture release, by reason. A gesture is released while any reason wants it and
    // given back when the last one lets go - which is why routing's release survives the
    // input router's -restoreAllSystemGestures.
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_voiceReleased;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_routingReleased;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_learningReleased;

    NSMutableDictionary<NSString *, AKControllerProfile *> *_profiles;

    // The routing hot path runs on whatever thread GameController calls a handler on, so the
    // state it touches is behind this lock, and nothing on it creates a profile object or
    // touches UIKit. This is where "as fast as it is today" is actually spent.
    NSRecursiveLock *_hot;
    // Source element -> target element, per controller model. Rebuilt on the main thread when a
    // profile, a pad or the switch changes, then read by the routing path.
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *_routes;
    // Every model this session has seen, so the rebuild knows what to build.
    NSMutableSet<NSString *> *_knownIdentities;

    BOOL _learning;
    NSString *_learningIdentity;

    NSString *_currentDevice;
    NSString *_currentDeviceName;
    NSString *_currentSourceName;
}

+ (instancetype)shared {
    static AKControllerManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKControllerManager new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _buttonValues = [NSMutableDictionary dictionary];
        _axisValues = [NSMutableDictionary dictionary];
        _routedButtons = [NSMutableDictionary dictionary];
        _routedAxes = [NSMutableDictionary dictionary];
        _voiceReleased = [NSMutableDictionary dictionary];
        _routingReleased = [NSMutableDictionary dictionary];
        _profiles = [NSMutableDictionary dictionary];
        _hot = [NSRecursiveLock new];
        _routes = [NSMutableDictionary dictionary];
        _knownIdentities = [NSMutableSet set];
    }
    return self;
}

- (NSString *)currentDevice { [_hot lock]; NSString *value=[_currentDevice copy]; [_hot unlock]; return value; }
- (NSString *)currentDeviceName { [_hot lock]; NSString *value=[_currentDeviceName copy]; [_hot unlock]; return value; }
- (NSString *)currentSourceName { [_hot lock]; NSString *value=[_currentSourceName copy]; [_hot unlock]; return value; }
- (BOOL)learning { return _learning; }
- (NSString *)learningIdentity { return _learningIdentity; }

#pragma mark - Start

- (void)begin {
    NSAssert(NSThread.isMainThread, @"Controller discovery belongs on the main thread");
    if (_began) { [self refreshRouting]; return; }
    _began = YES;

    [_hot lock];
    _enabled = [NSUserDefaults.standardUserDefaults boolForKey:AKControllerRoutingDefaultsKey];
    [_hot unlock];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(padsChanged:) name:GCControllerDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(padsChanged:) name:GCControllerDidDisconnectNotification object:nil];
    if (@available(iOS 14.0, *)) {
        [center addObserver:self selector:@selector(padsChanged:) name:GCKeyboardDidConnectNotification object:nil];
        [center addObserver:self selector:@selector(padsChanged:) name:GCKeyboardDidDisconnectNotification object:nil];
        [center addObserver:self selector:@selector(padsChanged:) name:GCMouseDidConnectNotification object:nil];
        [center addObserver:self selector:@selector(padsChanged:) name:GCMouseDidDisconnectNotification object:nil];
    }
    [center addObserver:self selector:@selector(virtualPadChanged:)
                   name:AKControllerVirtualPadDidChangeNotification object:nil];
    // The adapter asks once when it creates the virtual pad. Answered synchronously, so a
    // session started while routing was already on is not left without input.
    [center addObserver:self selector:@selector(routingStateRequested:) name:AKControllerRouteQueryNotification object:nil];
    // The guest façade announces itself when it loads, which can be before or after this.
    // Asked for here as well, so a build whose adapter is already loaded is discovered
    // without waiting for a pad to connect.
    [center addObserver:self selector:@selector(noteGuestFacadePresent)
                   name:AKControllerGuestFacadePresentNotification object:nil];
    [center postNotificationName:AKControllerGuestFacadeQueryNotification object:nil];
    // The app going away releases every virtual value: a button held while iPadOS
    // suspends us must not come back held, and the guest must never be left with a stick
    // at full deflection because the app was backgrounded mid-press.
    [center addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    // The guest façade may load after this: it asks once and is answered synchronously.
    [center addObserver:self selector:@selector(guestViewRequested:) name:AKControllerGuestViewRequestNotification object:nil];

    [self attachEverything];
    [self rememberModels];
    [self logInventories];
    [self refreshRouting];
    [self publishGuestView];
    AKCMLog(@"manager: watching physical controllers; routing is %@", _enabled ? @"on" : @"off");
}

- (void)padsChanged:(NSNotification *)notification {
    AKCMLog(@"manager: %@", notification.name);
    // A pad appearing or going away is the natural moment to try the virtual controller
    // again: the previous attempt's failure may have been about the pad, and a user who
    // reconnected should not have to toggle the switch to be routed.
    _virtualFailed = NO;
    _virtualError = nil;
    if ([notification.name isEqualToString:GCControllerDidDisconnectNotification]) {
        GCController *pad = notification.object;
        NSString *identity = pad ? AKControllerIdentity(pad) : nil;
        if (identity) [self forgetIdentity:identity];
        else {
            [_voiceReleased removeAllObjects];
            [_routingReleased removeAllObjects];
            [_hot lock];
            [_buttonValues removeAllObjects];
            [_axisValues removeAllObjects];
            [_hot unlock];
        }
        // The pad that was being used to learn has gone, so the armed state cannot be
        // satisfied any more. Only an identity-wide disconnect cancels the voicing
        // mapper, which the router decides for itself.
        if (_learning && (!identity || [_learningIdentity isEqualToString:identity])) [self cancelLearning];
    }
    [self attachEverything];
    [self rememberModels];
    [self logInventories];
    [self refreshRouting];
    [self publishGuestView];
    [self postChange];
}

- (void)virtualPadChanged:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    if ([info[AKControllerVirtualPadConnectedKey] boolValue]) {
        [self noteVirtualPadConnected:info[AKControllerVirtualPadControllerKey]];
    } else if ([info[AKControllerVirtualPadErrorKey] isKindOfClass:NSString.class]) {
        [self noteVirtualPadFailed:info[AKControllerVirtualPadErrorKey]];
    } else {
        [self noteVirtualPadDisconnected];
    }
}

- (void)willResignActive:(NSNotification *)notification {
    (void)notification;
    // Release, but stay armed: coming back re-routes from the pad's current state.
    [self releaseVirtualValues:@"the app resigned active"];
    [self cancelLearning];
}

- (void)didBecomeActive:(NSNotification *)notification {
    (void)notification;
    [self attachEverything];
    [self refreshRouting];
    [self publishGuestView];
}

- (void)didEnterBackground:(NSNotification *)notification {
    (void)notification;
    [self releaseVirtualValues:@"the app went to the background"];
}

#pragma mark - The switch

- (BOOL)enabled { [_hot lock]; BOOL value=_enabled; [_hot unlock]; return value; }

- (void)setEnabled:(BOOL)enabled {
    [_hot lock];
    if (_enabled == enabled) { [_hot unlock]; return; }
    _enabled = enabled;
    [_hot unlock];
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:AKControllerRoutingDefaultsKey];
    AKCMLog(@"manager: routing %@", enabled ? @"on" : @"off");
    if (!enabled) {
        [self cancelLearning];
        // Ask for every value back before the adapter lets the pad go, and give back
        // every gesture routing asked for.
        [self clearRoutingGestures];
        [self releaseVirtualValues:@"routing was switched off"];
        [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRouteStateNotification
                                                         object:nil
                                                       userInfo:@{AKControllerRouteEnabledKey: @NO}];
        _virtualFailed = NO; _virtualError = nil; _awaitingVirtualPad = NO;
    } else {
        [self refreshRouting];
    }
    [self postChange];
}

- (AKControllerRoutingState)state {
    if (!_enabled) return AKControllerRoutingStateDisabled;
    // Refused rather than degraded: without the façade the guest sees both pads.
    if (!self.guestFacadeAvailable) return AKControllerRoutingStateFailed;
    if (_virtualFailed) return AKControllerRoutingStateFailed;
    if (!self.physicalControllerConnected) return AKControllerRoutingStateWaiting;
    return _virtualController ? AKControllerRoutingStateRouting : AKControllerRoutingStateWaiting;
}

- (BOOL)guestFacadePresent { return _guestFacadePresent; }

- (BOOL)guestFacadeAvailable {
    if (_guestFacadePresent) return YES;
    // The adapter is a dylib the runtime loads for a guest session, so in the launcher it has
    // not announced itself yet even in a build that carries it. The bundle is the honest
    // answer to "can this build do it at all".
    static BOOL carried;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dylib = [NSBundle.mainBundle.bundlePath
            stringByAppendingPathComponent:@"Frameworks/akGameController.dylib"];
        carried = [NSFileManager.defaultManager fileExistsAtPath:dylib];
    });
    return carried;
}

- (void)noteGuestFacadePresent {
    if (_guestFacadePresent) return;
    _guestFacadePresent = YES;
    AKCMLog(@"manager: the guest GameController facade is loaded");
    if (_enabled) [self refreshRouting];
    [self postChange];
}

- (NSString *)statusDetail {
    switch (self.state) {
        case AKControllerRoutingStateDisabled:
            return @"routing is off; physical controllers reach the game directly";
        case AKControllerRoutingStateWaiting:
            if (!_guestFacadePresent)
                return @"routing is on; it starts when a guest session loads the guest controller facade";
            return self.physicalControllerConnected
                ? @"waiting for the virtual controller to connect"
                : @"routing is on; no physical controller is connected";
        case AKControllerRoutingStateRouting:
            return _virtualController
                ? [NSString stringWithFormat:@"routing %lu physical control(s) through one virtual controller",
                   (unsigned long)[AKControllerProfile sourceElements].count]
                : @"routing";
        case AKControllerRoutingStateFailed:
            if (!self.guestFacadeAvailable)
                return @"this build has no guest GameController facade, so a physical pad "
                        "would reach the game as well as its virtual replacement";
            return _virtualError.length ? _virtualError : @"the virtual controller could not connect";
    }
    return @"";
}

#pragma mark - What is connected

- (NSArray<GCController *> *)connectedControllers {
    if (self.controllersProvider) return self.controllersProvider();
    return GCController.controllers;
}

// A controller that is hardware rather than something this process made. Snapshots are
// app-created state; the virtual pad is ours, and counting it would make "a pad is
// connected" true with no pad in anyone's hands.
- (BOOL)isPhysical:(GCController *)pad {
    if (!pad || pad.isSnapshot) return NO;
    if (pad == _virtualController) return NO;
    if (!(pad.extendedGamepad || pad.microGamepad)) return NO;
    // The virtual pad reports itself as a controller too. Until the adapter tells us which
    // object it is, a controller that exists now but did not when we asked for ours can
    // only be ours; anything that was already there is hardware.
    if (_awaitingVirtualPad && _controllersWhenAsking && ![_controllersWhenAsking containsObject:pad]) return NO;
    return YES;
}

- (NSArray<GCController *> *)physicalControllers {
    NSMutableArray<GCController *> *pads = [NSMutableArray array];
    for (GCController *pad in self.connectedControllers) if ([self isPhysical:pad]) [pads addObject:pad];
    return pads;
}

- (BOOL)physicalControllerConnected { return self.physicalControllers.count > 0; }

- (BOOL)currentControllerDeclaresShare {
    for (GCController *pad in self.physicalControllers)
        if (pad.physicalInputProfile.buttons[GCInputButtonShare]) return YES;
    return NO;
}

// Remember the display names of every model seen, so a profile made on a pad that is not
// connected right now still reads as "Xbox Bluetooth Gamepad — Xbox One" rather than as a
// slug. The map itself is keyed by identity and never removed by a disconnect.
- (void)rememberModels {
    NSMutableDictionary *stored = [[NSUserDefaults.standardUserDefaults dictionaryForKey:AKControllerModelsDefaultsKey] mutableCopy];
    if (!stored) stored = [NSMutableDictionary dictionary];
    BOOL changed = NO;
    for (GCController *pad in self.physicalControllers) {
        NSString *identity = AKControllerIdentity(pad);
        NSDictionary *names = @{@"vendor": pad.vendorName ?: @"Controller",
                                @"category": pad.productCategory ?: @""};
        if (![stored[identity] isEqual:names]) { stored[identity] = names; changed = YES; }
    }
    if (changed) [NSUserDefaults.standardUserDefaults setObject:stored forKey:AKControllerModelsDefaultsKey];
}

- (nullable NSDictionary *)rememberedNamesForIdentity:(NSString *)identity {
    id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:AKControllerModelsDefaultsKey][identity];
    return [stored isKindOfClass:NSDictionary.class] ? stored : nil;
}

- (NSArray<AKControllerModel *> *)models {
    NSMutableDictionary<NSString *, NSMutableArray<GCController *> *> *byIdentity = [NSMutableDictionary dictionary];
    for (GCController *pad in self.physicalControllers) {
        NSString *identity = AKControllerIdentity(pad);
        if (!byIdentity[identity]) byIdentity[identity] = [NSMutableArray array];
        [byIdentity[identity] addObject:pad];
    }
    NSMutableArray<AKControllerModel *> *models = [NSMutableArray array];
    for (NSString *identity in byIdentity) {
        NSArray<GCController *> *pads = byIdentity[identity];
        AKControllerProfile *profile = [self profileForIdentity:identity];
        NSDictionary *available = [self availabilityForPads:pads];
        NSMutableDictionary<NSString *, NSNumber *> *reserved = [NSMutableDictionary dictionary];
        for (NSString *source in [AKControllerProfile sourceElements])
            reserved[source] = @(AKControllerElementIsReserved(source));
        AKControllerModel *model = [AKControllerModel new];
        model.identity = identity;
        model.displayName = profile.displayName;
        model.count = pads.count;
        model.bindings = [profile bindingsWithAvailability:available reserved:reserved];
        model.customised = profile.customised;
        [models addObject:model];
    }
    [models sortUsingComparator:^NSComparisonResult(AKControllerModel *a, AKControllerModel *b) {
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    return models;
}

// Which of the profile's sources this pad actually has. A source is available when the
// pad reports a button with that element id, or when it reports the stick or D-pad the
// axis source names.
- (NSDictionary<NSString *, NSNumber *> *)availabilityForPads:(NSArray<GCController *> *)pads {
    NSMutableDictionary<NSString *, NSNumber *> *available = [NSMutableDictionary dictionary];
    for (GCController *pad in pads) {
        GCPhysicalInputProfile *profile = pad.physicalInputProfile;
        for (NSString *name in profile.buttons)
            available[AKInputElementForControllerButton(name)] = @YES;
        for (NSString *name in profile.axes)
            available[AKInputElementForControllerAxis(name)] = @YES;
        for (NSString *name in profile.dpads) {
            NSString *stable = [self stableAxisElementForName:name];
            if (stable.length) available[stable] = @YES;
        }
    }
    return available;
}

- (NSString *)stableAxisElementForName:(NSString *)name {
    if ([name isEqualToString:GCInputLeftThumbstick]) return @"controller.axis.left.thumbstick";
    if ([name isEqualToString:GCInputRightThumbstick]) return @"controller.axis.right.thumbstick";
    if ([name isEqualToString:GCInputDirectionPad]) return @"dpad.dpad";
    return AKInputElementForControllerAxis(name);
}

#pragma mark - Profiles

- (nullable AKControllerProfile *)profileForIdentity:(NSString *)identity {
    if (!identity.length) return nil;
    AKControllerProfile *profile = _profiles[identity];
    if (profile) return profile;
    NSDictionary *names = [self rememberedNamesForIdentity:identity];
    profile = [[AKControllerProfile alloc] initWithIdentity:identity
                                                 vendorName:names[@"vendor"]
                                            productCategory:names[@"category"]
                                                   defaults:NSUserDefaults.standardUserDefaults];
    _profiles[identity] = profile;
    return profile;
}

- (void)resetProfileForIdentity:(NSString *)identity {
    [self rebuildRoutes];
    [[self profileForIdentity:identity] resetToDefault];
    [self applyProfileChangeForIdentity:identity];
}

- (void)applyProfileChangeForIdentity:(NSString *)identity {
    [self rebuildRoutes];
    (void)identity;
    // The gestures routing asked for are a consequence of the profile, so they follow it.
    [self applyRoutingGestures];
    [self routeCurrentStateAfterProfileChange];
    [self postChange];
}

- (void)forgetIdentity:(NSString *)identity {
    [_voiceReleased removeObjectForKey:identity];
    [_routingReleased removeObjectForKey:identity];
    [_hot lock];
    [_buttonValues removeObjectForKey:identity];
    [_axisValues removeObjectForKey:identity];
    [_hot unlock];
}

#pragma mark - Learning a source

- (void)beginLearningForIdentity:(NSString *)identity {
    if (!identity.length) return;
    _learning = YES;
    _learningIdentity = [identity copy];
    // A reserved button that becomes a source cannot be seen at all unless its gesture is
    // lent back for as long as the choosing lasts.
    [self beginReleasingForLearning];
    AKCMLog(@"manager: learning a new source for %@ — press or move the control", identity);
    [self postChange];
}

- (void)cancelLearning {
    if (!_learning) return;
    _learning = NO;
    _learningIdentity = nil;
    [self endReleasingForLearning];
    AKCMLog(@"manager: learning cancelled; nothing was changed");
    [self postChange];
}

- (void)learnFromSource:(NSString *)source device:(NSString *)device {
    // Learning is page state and gesture bookkeeping, so it belongs on main; the routing above it
    // does not wait for this.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self learnFromSource:source device:device]; });
        return;
    }
    if (!_learning || ![device isEqualToString:_learningIdentity]) return;
    _learning = NO;
    NSString *identity = _learningIdentity;
    _learningIdentity = nil;
    [self endReleasingForLearning];
    AKCMLog(@"manager: learned %@ on %@", source, identity);
    if (self.onLearned) self.onLearned(identity, source);
    [self postChange];
}

#pragma mark - The event stream

- (void)reportElement:(NSString *)element value:(double)value pressed:(BOOL)pressed
               device:(NSString *)device deviceName:(NSString *)name source:(NSString *)source {
    // Deliberately no main-thread assertion: this is the hot path and it runs where the
    // framework calls it. The parts that need main (learning, the router's own observing, the
    // page's refresh) defer themselves.
    [_hot lock];
    _currentDevice = device;
    _currentDeviceName = name;
    _currentSourceName = source;
    [_hot unlock];
    AKCMEntryTicks = mach_absolute_time();

    if ([source isEqualToString:@"controller"]) {
        [self noteButtonValue:value element:element device:device];
        if (pressed) [self learnFromSource:element device:device];
        [self routeButton:element value:value pressed:pressed device:device];
    }

    void (^event)(NSString *, double, BOOL, NSString *, NSString *, NSString *) = self.onEvent;
    if (event) {
        // The router is main-thread code. The routing above is not, and must not wait for this.
        if (NSThread.isMainThread) event(element, value, pressed, device, name, source);
        else dispatch_async(dispatch_get_main_queue(), ^{
            event(element, value, pressed, device, name, source);
        });
    }
}

- (void)reportAxis:(NSString *)stableElement position:(CGPoint)point
            device:(NSString *)device deviceName:(NSString *)name {
    [_hot lock];
    _currentDevice = device;
    _currentDeviceName = name;
    _currentSourceName = @"controller";
    [_hot unlock];
    [self noteAxisPosition:point element:stableElement device:device];
    if (hypot(point.x, point.y) > AKControllerLearnAxisThreshold)
        [self learnFromSource:stableElement device:device];
    [self routeAxis:stableElement position:point device:device];
}

- (void)noteButtonValue:(double)value element:(NSString *)element device:(NSString *)device {
    if (!device.length || !element.length) return;
    [_hot lock];
    NSMutableDictionary *values = _buttonValues[device];
    if (!values) { values = [NSMutableDictionary dictionary]; _buttonValues[device] = values; }
    values[element] = @(value);
    [_hot unlock];
}

- (void)noteAxisPosition:(CGPoint)position element:(NSString *)element device:(NSString *)device {
    if (!device.length || !element.length) return;
    [_hot lock];
    NSMutableDictionary *values = _axisValues[device];
    if (!values) { values = [NSMutableDictionary dictionary]; _axisValues[device] = values; }
    values[element] = [NSValue valueWithCGPoint:position];
    [_hot unlock];
}

// The hot path cannot build a profile object, so it reads this: source element -> target element
// for every model this session has seen. Rebuilt whenever a profile, a pad or the switch changes,
// on the main thread, and swapped in whole so a reader never sees half a table.
- (void)rebuildRoutes {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self rebuildRoutes]; });
        return;
    }
    // Everything connected right now counts as known, whether or not discovery has attached it
    // yet: a pad that starts reporting before it is attached must not have its first press
    // dropped.
    for (GCController *pad in self.connectedControllers) [_knownIdentities addObject:AKControllerIdentity(pad)];
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *table =
        [NSMutableDictionary dictionary];
    for (NSString *identity in [_knownIdentities copy]) {
        AKControllerProfile *profile = [self profileForIdentity:identity];
        if (!profile) continue;
        NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
        // Availability is about what a pad can physically produce, which does not change the
        // mapping itself: routing asks only "what does this source drive".
        for (AKControllerBinding *binding in [profile bindingsWithAvailability:@{} reserved:@{}]) {
            if (!binding.source.length) continue;
            map[binding.source] = binding.target.length ? binding.target : AKControllerTargetNone;
        }
        table[identity] = map;
    }
    [_hot lock];
    _routes = table;
    [_hot unlock];
}

#pragma mark - Routing into the virtual pad

- (void)routeButton:(NSString *)element value:(double)value pressed:(BOOL)pressed device:(NSString *)device {
    NSString *target = nil;
    [_hot lock];
    // Nothing is sent before the virtual controller is connected: a value aimed at a pad that is
    // not there is a value the adapter drops, and reporting routing as running while it drops
    // everything is the kind of half-state this feature must not have.
    if (_enabled && _virtualController) {
        target = _routes[device][element];
        if (target.length && ![target isEqualToString:AKControllerTargetNone]) {
            // A released button is always sent, even if the value did not change: the one thing
            // that must never be missed is "this is no longer pressed".
            double out = pressed ? value : 0;
            NSNumber *last = _routedButtons[target];
            if (last && pressed && fabs(last.doubleValue - out) < 1.0 / 255.0) target = nil;
            else _routedButtons[target] = @(out);
            if (target) value = out;
        } else target = nil;
    }
    [_hot unlock];
    if (!target) return;
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRouteValueNotification
                                                     object:nil
                                                   userInfo:@{AKControllerRouteElementKey: target,
                                                              AKControllerRouteValueKey: @(value)}];
    if (self.routeLatencyObserver) self.routeLatencyObserver(AKCMEntryTicks);
}

- (void)routeAxis:(NSString *)element position:(CGPoint)position device:(NSString *)device {
    NSString *target = nil;
    [_hot lock];
    if (_enabled && _virtualController) {
        target = _routes[device][element];
        if (target.length && ![target isEqualToString:AKControllerTargetNone]) {
            NSValue *last = _routedAxes[target];
            if (last) {
                CGPoint previous = last.CGPointValue;
                if (fabs(previous.x - position.x) < AKControllerAxisQuantum &&
                    fabs(previous.y - position.y) < AKControllerAxisQuantum) target = nil;
            }
            if (target) _routedAxes[target] = [NSValue valueWithCGPoint:position];
        } else target = nil;
    }
    [_hot unlock];
    if (!target) return;
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRoutePositionNotification
                                                     object:nil
                                                   userInfo:@{AKControllerRouteElementKey: target,
                                                              AKControllerRouteXKey: @(position.x),
                                                              AKControllerRouteYKey: @(position.y)}];
}

- (void)releaseVirtualValues:(NSString *)why {
    [_hot lock];
    if (!_routedButtons.count && !_routedAxes.count) { [_hot unlock]; return; }
    NSUInteger count = _routedButtons.count + _routedAxes.count;
    [_routedButtons removeAllObjects];
    [_routedAxes removeAllObjects];
    [_hot unlock];
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRouteReleaseNotification object:nil];
    AKCMLog(@"manager: released %lu virtual value(s) because %@", (unsigned long)count, why);
}

// Re-send what the pad is doing now. Used when routing starts, when a profile changes and
// when the app comes back, so a stick that is already deflected is not silently ignored
// until the user moves it.
- (void)routeCurrentStateAfterProfileChange {
    [_hot lock];
    if (!_enabled) { [_hot unlock]; return; }
    [_routedButtons removeAllObjects];
    [_routedAxes removeAllObjects];
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *buttons=[NSMutableDictionary dictionary];
    for (NSString *device in _buttonValues) buttons[device]=[_buttonValues[device] copy];
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *axes=[NSMutableDictionary dictionary];
    for (NSString *device in _axisValues) axes[device]=[_axisValues[device] copy];
    [_hot unlock];
    for (NSString *device in buttons) {
        AKControllerProfile *profile = [self profileForIdentity:device];
        NSDictionary *values = buttons[device];
        for (NSString *element in [AKControllerProfile sourceElements]) {
            NSString *target = [profile targetForSource:element];
            if (!target.length || [target isEqualToString:AKControllerTargetNone]) continue;
            NSNumber *value = values[element];
            if (value) [self routeButton:element value:value.doubleValue pressed:value.doubleValue > 0 device:device];
        }
    }
    for (NSString *device in axes) {
        AKControllerProfile *profile = [self profileForIdentity:device];
        NSDictionary *values = axes[device];
        for (NSString *element in [AKControllerProfile sourceElements]) {
            NSString *target = [profile targetForSource:element];
            if (!target.length || [target isEqualToString:AKControllerTargetNone]) continue;
            NSValue *value = values[element];
            if (value) [self routeAxis:element position:value.CGPointValue device:device];
        }
    }
}

#pragma mark - Routing lifecycle

- (void)refreshRouting {
    NSAssert(NSThread.isMainThread, @"Routing decisions belong on the main thread");
    if (!_enabled) return;
    // Ask again: the guest's session may have started since the last decision.
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerGuestFacadeQueryNotification object:nil];
    if (!_guestFacadePresent) {
        // Nothing may be routed, and no virtual pad may be asked for: the guest would see
        // the physical pad and the virtual one at once.
        AKCMLog(@"manager: routing refused — the guest GameController facade is not in this build");
        [self clearRoutingGestures];
        [self releaseVirtualValues:@"this build has no guest GameController facade"];
        [self postChange];
        return;
    }
    BOOL wanted = self.physicalControllerConnected;
    if (!wanted) {
        // No hardware to route: give the virtual pad back so the guest is not offered a
        // controller that does nothing.
        [self clearRoutingGestures];
        [self releaseVirtualValues:@"no physical controller is connected"];
        if (_virtualController || _awaitingVirtualPad) {
            [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRouteStateNotification
                                                             object:nil
                                                           userInfo:@{AKControllerRouteEnabledKey: @NO}];
            _awaitingVirtualPad = NO;
        }
        [self postChange];
        return;
    }

    [self applyRoutingGestures];
    if (!_virtualController && !_awaitingVirtualPad && !_virtualFailed) {
        _awaitingVirtualPad = YES;
        _controllersWhenAsking = [self.connectedControllers copy];
        AKCMLog(@"manager: asking the adapter for the virtual controller");
        [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRouteStateNotification
                                                         object:nil
                                                       userInfo:@{AKControllerRouteEnabledKey: @YES}];
    }
    [self routeCurrentStateAfterProfileChange];
    [self postChange];
}

- (void)noteVirtualPadConnected:(GCController *)controller {
    if (controller) {
        [_knownIdentities addObject:AKControllerIdentity(controller)];
        [self rebuildRoutes];
    }
    [_hot lock];
    _virtualController = controller;
    [_hot unlock];
    _awaitingVirtualPad = NO;
    _virtualFailed = NO;
    _virtualError = nil;
    AKCMLog(@"manager: virtual controller connected (vendor=%@)", controller.vendorName ?: @"?");
    [self routeCurrentStateAfterProfileChange];
    [self publishGuestView];
    [self postChange];
}

- (void)noteVirtualPadFailed:(NSString *)error {
    [_hot lock];
    _virtualController = nil;
    [_hot unlock];
    _awaitingVirtualPad = NO;
    _virtualFailed = YES;
    _virtualError = [error copy];
    // A failed connection routes nothing. The physical pads are left exactly as they
    // were, which is the state the page reports so the user is not silently without input.
    [self releaseVirtualValues:@"the virtual controller could not connect"];
    AKCMLog(@"manager: virtual controller failed: %@", error);
    [self publishGuestView];
    [self postChange];
}

- (void)noteVirtualPadDisconnected {
    [_hot lock];
    _virtualController = nil;
    _awaitingVirtualPad = NO;
    [_routedButtons removeAllObjects];
    [_routedAxes removeAllObjects];
    [_hot unlock];
    [self publishGuestView];
    [self postChange];
}

#pragma mark - System gestures, by reason

- (nullable GCControllerButtonInput *)buttonForElement:(NSString *)element
                                                device:(nullable NSString *)device
                                                 inPad:(GCController *)pad {
    if (device.length && ![AKControllerIdentity(pad) isEqualToString:device]) return nil;
    for (NSString *name in pad.physicalInputProfile.buttons)
        if ([AKInputElementForControllerButton(name) isEqualToString:element])
            return pad.physicalInputProfile.buttons[name];
    return nil;
}

- (BOOL)anyReasonWants:(NSString *)element device:(NSString *)identity {
    return [_voiceReleased[identity] containsObject:element] ||
           [_routingReleased[identity] containsObject:element] ||
           [_learningReleased[identity] containsObject:element];
}

- (void)refreshGestureForElement:(NSString *)element device:(NSString *)identity {
    for (GCController *pad in self.physicalControllers) {
        if (![AKControllerIdentity(pad) isEqualToString:identity]) continue;
        GCControllerButtonInput *button = [self buttonForElement:element device:identity inPad:pad];
        if (!button) continue;
        BOOL wanted = [self anyReasonWants:element device:identity];
        GCSystemGestureState state = wanted ? GCSystemGestureStateDisabled : GCSystemGestureStateEnabled;
        if (button.preferredSystemGestureState == state) continue;
        button.preferredSystemGestureState = state;
        AKCMLog(@"manager: %@ the system gesture on %@ for %@",
                wanted ? @"released" : @"gave back", element, identity);
    }
}

- (BOOL)releaseSystemGestureForElement:(NSString *)element device:(nullable NSString *)device {
    // A nil device means "every pad that has this element", which is how the voice
    // settings ask when they know the element but not the pad.
    if (!device.length) {
        BOOL released = NO;
        for (GCController *pad in self.physicalControllers)
            released |= [self releaseSystemGestureForElement:element device:AKControllerIdentity(pad)];
        return released;
    }
    if (!_voiceReleased[device]) _voiceReleased[device] = [NSMutableSet set];
    [_voiceReleased[device] addObject:element];
    BOOL hadButton = NO;
    for (GCController *pad in self.physicalControllers)
        if ([self buttonForElement:element device:device inPad:pad]) hadButton = YES;
    [self refreshGestureForElement:element device:device];
    return hadButton;
}

- (void)restoreSystemGestureForElement:(NSString *)element device:(nullable NSString *)device {
    for (NSString *identity in [_voiceReleased allKeys]) {
        if (device.length && ![identity isEqualToString:device]) continue;
        if (![_voiceReleased[identity] containsObject:element]) continue;
        [_voiceReleased[identity] removeObject:element];
        [self refreshGestureForElement:element device:identity];
    }
}

- (void)restoreAllSystemGestures {
    // Only the voice feature's releases. Routing's releases are this manager's own
    // decision and survive this call, which the input router makes whenever a voice
    // mapping changes; undoing them here would silently stop routing a mapped button.
    NSUInteger count = 0;
    for (NSString *identity in _voiceReleased) count += _voiceReleased[identity].count;
    [_voiceReleased removeAllObjects];
    // Re-decide every button of every pad rather than trusting the count above: an
    // element may still be released because routing or the learn loan wants it.
    for (GCController *pad in self.physicalControllers) {
        NSString *identity = AKControllerIdentity(pad);
        for (NSString *name in pad.physicalInputProfile.buttons)
            [self refreshGestureForElement:AKInputElementForControllerButton(name) device:identity];
    }
    if (count) AKCMLog(@"manager: gave the system its gesture back on %lu voice-mapped element(s)",
                       (unsigned long)count);
}

- (void)beginReleasingForLearning {
    if (_learningReleased) return;
    _learningReleased = [NSMutableDictionary dictionary];
    for (GCController *pad in self.physicalControllers) {
        NSString *identity = AKControllerIdentity(pad);
        for (NSString *name in pad.physicalInputProfile.buttons) {
            NSString *element = AKInputElementForControllerButton(name);
            if (!AKControllerElementIsReserved(element)) continue;
            if ([self anyReasonWants:element device:identity]) continue;
            if (!_learningReleased[identity]) _learningReleased[identity] = [NSMutableSet set];
            [_learningReleased[identity] addObject:element];
            [self refreshGestureForElement:element device:identity];
        }
    }
}

- (void)endReleasingForLearning {
    if (!_learningReleased) return;
    NSUInteger count = 0;
    for (NSString *identity in _learningReleased) count += _learningReleased[identity].count;
    _learningReleased = nil;
    // A button the user went on to route keeps its release: routing's set is separate and
    // -refreshGestureForElement: asks every reason, so nothing mapped is given back here.
    for (GCController *pad in self.physicalControllers) {
        NSString *identity = AKControllerIdentity(pad);
        for (NSString *name in pad.physicalInputProfile.buttons)
            [self refreshGestureForElement:AKInputElementForControllerButton(name) device:identity];
    }
    if (count) AKCMLog(@"manager: the %lu gesture(s) lent out for choosing a source are back with the system",
                       (unsigned long)count);
}

// Release the gesture of every source this profile routes that iPadOS keeps. Nothing else:
// a face button needs no help and giving a gesture back is the system's business unless
// the user asked us to route that control.
- (void)applyRoutingGestures {
    if (!_enabled) return;
    for (GCController *pad in self.physicalControllers) {
        NSString *identity = AKControllerIdentity(pad);
        AKControllerProfile *profile = [self profileForIdentity:identity];
        NSMutableSet<NSString *> *wanted = [NSMutableSet set];
        for (NSString *source in [AKControllerProfile sourceElements]) {
            if (!AKControllerElementIsReserved(source)) continue;
            NSString *target = [profile targetForSource:source];
            if (!target.length || [target isEqualToString:AKControllerTargetNone]) continue;
            [wanted addObject:source];
        }
        NSMutableSet<NSString *> *current = _routingReleased[identity];
        if (![current isEqualToSet:wanted]) {
            // Re-decide the union of what was released and what should be: a source that
            // just stopped being routed has to be refreshed too, or its gesture would stay
            // released for a mapping the user has removed.
            NSMutableSet<NSString *> *touched = [NSMutableSet setWithSet:current ?: [NSSet set]];
            [touched unionSet:wanted];
            _routingReleased[identity] = wanted;
            for (NSString *source in touched) [self refreshGestureForElement:source device:identity];
        }
    }
}

- (void)clearRoutingGestures {
    NSArray<NSString *> *identities = _routingReleased.allKeys;
    [_routingReleased removeAllObjects];
    // Every controller that carries one of those elements, not only the ones this manager still
    // counts as hardware. A gesture must be given back wherever it was held: a pad can leave the
    // hardware list while its elements exist (it is disconnecting, or it has just been adopted as
    // the virtual pad), and leaving the release behind would change how that pad behaves after
    // routing is switched off. Found by the device self-test, whose single controller is both.
    for (GCController *pad in self.connectedControllers) {
        NSString *identity = AKControllerIdentity(pad);
        if (![identities containsObject:identity]) continue;
        for (NSString *name in pad.physicalInputProfile.buttons) {
            NSString *element = AKInputElementForControllerButton(name);
            if ([self anyReasonWants:element device:identity]) continue;
            GCControllerButtonInput *button = pad.physicalInputProfile.buttons[name];
            if (button.preferredSystemGestureState == GCSystemGestureStateEnabled) continue;
            button.preferredSystemGestureState = GCSystemGestureStateEnabled;
            AKCMLog(@"manager: gave the system gesture back on %@ for %@", element, identity);
        }
    }
}

#pragma mark - The guest's view

// Exactly what the guest may enumerate. Disabled: the real pads, unchanged. Enabled: the
// one virtual controller, and nothing else - which is the whole point of the façade.
- (NSArray<GCController *> *)guestControllers {
    if (!_enabled) return self.connectedControllers;
    return _virtualController ? @[_virtualController] : @[];
}

- (void)guestViewRequested:(NSNotification *)notification {
    (void)notification;
    [self publishGuestView];
}
- (void)publishGuestView {
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerGuestViewDidChangeNotification
                                                     object:nil
                                                   userInfo:@{AKControllerGuestViewControllersKey: [self guestControllers],
                                                              AKControllerGuestViewRoutingKey: @(_enabled)}];
}

// The adapter's question, answered on the spot. Two notifications rather than a stored
// value on each side: there is one answer and one owner of it, and a stale copy in the
// adapter is exactly how a pad ends up routed after the user switched routing off.
- (void)routingStateRequested:(NSNotification *)notification {
    (void)notification;
    BOOL shouldRoute = _enabled && self.physicalControllerConnected;
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerRouteStateNotification
                                                     object:nil
                                                   userInfo:@{AKControllerRouteEnabledKey: @(shouldRoute)}];
}

#pragma mark - Attaching handlers

- (void)attachEverything {
    for (GCController *pad in self.physicalControllers) [self attachPad:pad];
    if (@available(iOS 14.0, *)) {
        GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
        if (keyboard) [self attachKeyboard:keyboard];
        GCMouse *mouse = GCMouse.current;
        if (mouse) [self attachMouse:mouse];
    }
}

- (void)attachPad:(GCController *)pad {
    [_knownIdentities addObject:AKControllerIdentity(pad)];
    [self rebuildRoutes];
    GCPhysicalInputProfile *profile = pad.physicalInputProfile;
    NSString *device = AKControllerIdentity(pad);
    NSString *deviceName = pad.vendorName ?: @"Controller";
    __weak AKControllerManager *weakSelf = self;

    for (NSString *name in profile.buttons) {
        GCControllerButtonInput *button = profile.buttons[name];
        NSString *element = AKInputElementForControllerButton(name);
        // The press edge is what the voice feature has always consumed; it is also what
        // tells routing that a button is now down.
        button.pressedChangedHandler = ^(GCControllerButtonInput *input, float value, BOOL pressed) {
            (void)input;
            AKCMReport(weakSelf, device, deviceName, @"controller", element, value, pressed);
        };
        // The analog value is what routing needs: a trigger is not a switch. It is a
        // separate handler so the published event stream keeps exactly the shape the
        // voice router was built against.
        button.valueChangedHandler = ^(GCControllerButtonInput *input, float value, BOOL pressed) {
            (void)input; (void)pressed;
            AKControllerManager *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf noteButtonValue:value element:element device:device];
            [strongSelf routeButton:element value:value pressed:value > 0 device:device];
        };
    }
    for (NSString *name in profile.axes) {
        GCControllerAxisInput *axis = profile.axes[name];
        NSString *element = AKInputElementForControllerAxis(name);
        NSString *stable = [self stableAxisElementForName:name];
        axis.valueChangedHandler = ^(GCControllerAxisInput *input, float value) {
            (void)input;
            AKCMReport(weakSelf, device, deviceName, @"controller", element, value, value != 0);
            AKCMReportAxis(weakSelf, device, deviceName, stable, CGPointMake(value, 0));
        };
    }
    for (NSString *name in profile.dpads) {
        GCControllerDirectionPad *dpad = profile.dpads[name];
        NSString *stable = [self stableAxisElementForName:name];
        dpad.valueChangedHandler = ^(GCControllerDirectionPad *input, float x, float y) {
            (void)input;
            // The direction is the name a voice trigger matches; the position is what
            // routing sends. Both come out of the same sample.
            AKCMReport(weakSelf, device, deviceName, @"controller",
                       AKInputElementForDirectionPad(name, x, y), 1, (x != 0 || y != 0));
            AKCMReportAxis(weakSelf, device, deviceName, stable, CGPointMake(x, y));
        };
    }
    for (NSString *name in profile.touchpads) {
        GCControllerTouchpad *touchpad = profile.touchpads[name];
        NSString *down = AKInputElementForTouchpad(name, @"down");
        NSString *up = AKInputElementForTouchpad(name, @"up");
        NSString *moved = AKInputElementForTouchpad(name, @"moved");
        touchpad.touchDown = ^(GCControllerTouchpad *input, float x, float y, float buttonValue, BOOL buttonPressed) {
            (void)input; (void)buttonValue; (void)x; (void)y; (void)buttonPressed;
            AKCMReport(weakSelf, device, deviceName, @"touchpad", down, 1, YES);
        };
        touchpad.touchUp = ^(GCControllerTouchpad *input, float x, float y, float buttonValue, BOOL buttonPressed) {
            (void)input; (void)buttonValue; (void)x; (void)y; (void)buttonPressed;
            AKCMReport(weakSelf, device, deviceName, @"touchpad", up, 0, NO);
        };
        touchpad.touchMoved = ^(GCControllerTouchpad *input, float x, float y, float buttonValue, BOOL buttonPressed) {
            (void)input; (void)buttonValue; (void)buttonPressed; (void)x; (void)y;
            AKCMReport(weakSelf, device, deviceName, @"touchpad", moved, 0, NO);
        };
    }

    // Read-only: a gesture is released only by a reason the user created.
    GCControllerButtonInput *share = profile.buttons[GCInputButtonShare];
    if (share) {
        AKCMLog(@"manager: %@ declares Share; its system gesture is %@",
                deviceName,
                [self anyReasonWants:@"controller.button.share" device:device] ? @"released" : @"the system's");
    }
}

- (void)attachKeyboard:(GCKeyboard *)keyboard API_AVAILABLE(ios(14.0)) {
    __weak AKControllerManager *weakSelf = self;
    NSString *name = keyboard.vendorName ?: @"Keyboard";
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *input, GCDeviceButtonInput *key, GCKeyCode keyCode, BOOL pressed) {
        (void)input; (void)key;
        AKCMReport(weakSelf, @"keyboard", name, @"keyboard",
                   AKInputElementForKeyboardKey(keyCode), (pressed ? 1 : 0), pressed);
    };
}

- (void)attachMouse:(GCMouse *)mouse API_AVAILABLE(ios(14.0)) {
    __weak AKControllerManager *weakSelf = self;
    GCMouseInput *input = mouse.mouseInput;
    NSString *name = mouse.vendorName ?: @"Mouse";
    input.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        AKCMReport(weakSelf, @"mouse", name, @"mouse", AKInputElementForMouseButton(@"left"), value, pressed);
    };
    input.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        AKCMReport(weakSelf, @"mouse", name, @"mouse", AKInputElementForMouseButton(@"right"), value, pressed);
    };
    input.middleButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
        (void)button;
        AKCMReport(weakSelf, @"mouse", name, @"mouse", AKInputElementForMouseButton(@"middle"), value, pressed);
    };
    input.mouseMovedHandler = ^(GCMouseInput *mouseInput, float deltaX, float deltaY) {
        (void)mouseInput; (void)deltaX; (void)deltaY;
        // Movement streams; the log would never settle. The click is what matters.
    };
}

#pragma mark - Inventory

- (void)logInventories {
    NSArray<GCController *> *pads = self.connectedControllers;
    AKCMLog(@"inspector: %lu controller(s) connected", (unsigned long)pads.count);
    for (GCController *pad in pads) [self describe:pad];

    if (@available(iOS 14.0, *)) {
        GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
        GCMouse *mouse = GCMouse.current;
        AKCMLog(@"inspector: keyboard=%@ mouse=%@",
                keyboard ? (keyboard.vendorName ?: @"present") : @"none",
                mouse ? (mouse.vendorName ?: @"present") : @"none");
        if (keyboard) {
            GCKeyboardInput *input = keyboard.keyboardInput;
            NSArray<NSString *> *names = [input.buttons.allKeys sortedArrayUsingSelector:@selector(compare:)];
            AKCMLog(@"inspector: keyboard keys=%lu names=%@",
                    (unsigned long)names.count, [names componentsJoinedByString:@" | "]);
            [self attachKeyboard:keyboard];
        }
    }
    AKCMLog(@"inspector: routing=%@ state=%ld", _enabled ? @"on" : @"off", (long)self.state);
}

- (void)describe:(GCController *)pad {
    GCPhysicalInputProfile *profile = pad.physicalInputProfile;
    AKCMLog(@"inspector: pad name=%@ vendor=%@ category=%@ profile=%@",
            pad.vendorName ?: @"?", pad.vendorName ?: @"?", pad.productCategory ?: @"?",
            NSStringFromClass(profile.class));

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *name in profile.buttons) {
        GCControllerButtonInput *button = profile.buttons[name];
        [lines addObject:[NSString stringWithFormat:@"button %@%@", name, button.isAnalog ? @" [analog]" : @""]];
    }
    for (NSString *name in profile.axes) [lines addObject:[NSString stringWithFormat:@"axis %@", name]];
    for (NSString *name in profile.dpads) [lines addObject:[NSString stringWithFormat:@"dpad %@", name]];
    for (NSString *name in profile.touchpads) [lines addObject:[NSString stringWithFormat:@"touchpad %@", name]];
    AKCMLog(@"inspector: elements (%lu): %@", (unsigned long)lines.count, [lines componentsJoinedByString:@", "]);

    AKCMLog(@"inspector: buttons=%lu (all=%lu) axes=%lu (all=%lu) dpads=%lu (all=%lu)",
            (unsigned long)profile.buttons.count, (unsigned long)profile.allButtons.count,
            (unsigned long)profile.axes.count, (unsigned long)profile.allAxes.count,
            (unsigned long)profile.dpads.count, (unsigned long)profile.allDpads.count);

    GCControllerButtonInput *share = profile.buttons[GCInputButtonShare];
    AKCMLog(@"inspector: share=%@ gesture=%@", share ? @"present" : @"absent",
            share ? (share.preferredSystemGestureState == GCSystemGestureStateDisabled ? @"disabled" : @"system") : @"n/a");

    if ([profile isKindOfClass:GCXboxGamepad.class]) {
        GCXboxGamepad *xbox = (GCXboxGamepad *)profile;
        NSMutableArray<NSString *> *paddles = [NSMutableArray array];
        if (xbox.paddleButton1) [paddles addObject:@"P1"];
        if (xbox.paddleButton2) [paddles addObject:@"P2"];
        if (xbox.paddleButton3) [paddles addObject:@"P3"];
        if (xbox.paddleButton4) [paddles addObject:@"P4"];
        AKCMLog(@"inspector: xbox paddles=%@ share=%@",
                paddles.count ? [paddles componentsJoinedByString:@","] : @"none",
                xbox.buttonShare ? @"present" : @"absent");
    }
    if ([profile isKindOfClass:GCExtendedGamepad.class]) {
        GCExtendedGamepad *extended = (GCExtendedGamepad *)profile;
        AKCMLog(@"inspector: menu=%@ options=%@ l3=%@ r3=%@",
                extended.buttonMenu ? @"y" : @"n", extended.buttonOptions ? @"y" : @"n",
                extended.leftThumbstickButton ? @"y" : @"n", extended.rightThumbstickButton ? @"y" : @"n");
    }
}

#pragma mark - Telling the page

- (void)postChange {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self postChange]; });
        return;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerManagerDidChangeNotification object:self];
}

@end
