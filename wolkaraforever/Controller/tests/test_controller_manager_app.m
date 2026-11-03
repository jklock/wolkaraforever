// Deterministic fixture: the Controller Manager's state machine, with no hardware.
//
// It drives the same entry points the GameController handlers call -
// -reportElement:… and -reportAxis:… - and the same replies the hidden virtual controller
// sends back, so what it proves is the real pipeline rather than a copy of it. The pads are
// duck-typed objects, the same way the touch gamepad fixture builds one: this manager only
// ever asks a pad for its identity, its profile and its two "is this a pad" flags.
//
// No game, no network, no controller.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

#import "../launcher/Controller/ControllerManager.h"
#import "../launcher/Controller/ControllerProfile.h"
#import "../launcher/Controller/ControllerIdentity.h"

#include <assert.h>
#include <math.h>

#define CM_CHECK(condition, label) do { \
    if (!(condition)) { \
        fprintf(stderr, "CONTROLLER_MANAGER_FAIL: %s (%s:%d)\n", (label), __FILE__, __LINE__); \
        fflush(stderr); \
        _Exit(1); \
    } \
} while (0)

#pragma mark - Duck-typed hardware

@interface CMFakeButton : NSObject
@property (nonatomic) GCSystemGestureState preferredSystemGestureState;
@property (nonatomic) BOOL isAnalog;
@property (nonatomic, copy) id pressedChangedHandler;
@property (nonatomic, copy) id valueChangedHandler;
@end
@implementation CMFakeButton
@end

@interface CMFakeProfile : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, CMFakeButton *> *buttons;
@property (nonatomic, strong) NSMutableDictionary *axes, *dpads, *touchpads;
@property (nonatomic, strong) NSMutableDictionary *allButtons, *allAxes, *allDpads;
@end
@implementation CMFakeProfile
- (instancetype)init {
    if ((self = [super init])) {
        _buttons = [NSMutableDictionary dictionary];
        _axes = [NSMutableDictionary dictionary];
        _dpads = [NSMutableDictionary dictionary];
        _touchpads = [NSMutableDictionary dictionary];
        _allButtons = [NSMutableDictionary dictionary];
        _allAxes = [NSMutableDictionary dictionary];
        _allDpads = [NSMutableDictionary dictionary];
    }
    return self;
}
@end

@interface CMFakePad : NSObject
@property (nonatomic) BOOL isSnapshot;
@property (nonatomic, strong) id extendedGamepad, microGamepad;
@property (nonatomic, copy) NSString *vendorName, *productCategory;
@property (nonatomic, strong) CMFakeProfile *physicalInputProfile;
@end
@implementation CMFakePad
- (instancetype)initWithVendor:(NSString *)vendor category:(NSString *)category {
    if ((self = [super init])) {
        _vendorName = [vendor copy];
        _productCategory = [category copy];
        _extendedGamepad = @YES;
        _physicalInputProfile = [CMFakeProfile new];
        for (NSString *name in @[GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                                 GCInputLeftShoulder, GCInputRightShoulder,
                                 GCInputLeftTrigger, GCInputRightTrigger,
                                 GCInputButtonMenu, GCInputButtonOptions,
                                 GCInputLeftThumbstickButton]) {
            CMFakeButton *button = [CMFakeButton new];
            button.preferredSystemGestureState = GCSystemGestureStateEnabled;
            ((CMFakeProfile *)_physicalInputProfile).buttons[name] = button;
        }
    }
    return self;
}
@end

#pragma mark - Recording the manager's output

@interface CMRecorder : NSObject
@property (nonatomic) NSMutableArray<NSString *> *values;      // "element=value"
@property (nonatomic) NSMutableArray<NSString *> *positions;   // "element=x,y"
@property (nonatomic) NSUInteger releases;
@end
@implementation CMRecorder
- (instancetype)init {
    if ((self = [super init])) {
        _values = [NSMutableArray array];
        _positions = [NSMutableArray array];
    }
    return self;
}
- (void)clear { [_values removeAllObjects]; [_positions removeAllObjects]; _releases = 0; }
- (void)observe {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:AKControllerRouteValueNotification object:nil queue:nil
                    usingBlock:^(NSNotification *note) {
        [self.values addObject:[NSString stringWithFormat:@"%@=%.4f",
            note.userInfo[AKControllerRouteElementKey], [note.userInfo[AKControllerRouteValueKey] doubleValue]]];
    }];
    [center addObserverForName:AKControllerRoutePositionNotification object:nil queue:nil
                    usingBlock:^(NSNotification *note) {
        [self.positions addObject:[NSString stringWithFormat:@"%@=%.4f,%.4f",
            note.userInfo[AKControllerRouteElementKey],
            [note.userInfo[AKControllerRouteXKey] doubleValue],
            [note.userInfo[AKControllerRouteYKey] doubleValue]]];
    }];
    [center addObserverForName:AKControllerRouteReleaseNotification object:nil queue:nil
                    usingBlock:^(NSNotification *note) {
        (void)note;
        self.releases++;
    }];
}
- (BOOL)hasValue:(NSString *)value { return [self.values containsObject:value]; }
- (BOOL)hasPosition:(NSString *)position { return [self.positions containsObject:position]; }
- (void)clearDefaults { [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverControllerRouting"]; }
@end

#pragma mark - The checks

static NSString *const CMIdentity = @"fixture.vendor.fixture.category";

static void CMTestProfile(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *storageKey = [NSString stringWithFormat:@"WolkaraForeverControllerProfile.%@", CMIdentity];
    [AKControllerProfile forgetIdentity:CMIdentity defaults:defaults];
    AKControllerProfile *profile = [[AKControllerProfile alloc] initWithIdentity:CMIdentity
                                                                      vendorName:@"Fixture Vendor"
                                                                 productCategory:@"Fixture Category"
                                                                        defaults:defaults];
    CM_CHECK([[profile targetForSource:@"controller.button.a"] isEqualToString:@"virtual.button.a"],
             "default mapping is one to one");
    CM_CHECK([[profile targetForSource:@"controller.button.left.trigger"] isEqualToString:@"virtual.button.left.trigger"],
             "triggers default to triggers");
    CM_CHECK([[profile targetForSource:@"controller.axis.left.thumbstick"] isEqualToString:@"virtual.stick.left"],
             "sticks default to sticks");
    CM_CHECK([[profile targetForSource:@"dpad.dpad"] isEqualToString:@"virtual.dpad"],
             "the D-pad defaults to the D-pad");
    // A control the virtual pad has no target for is explicitly "not assigned" rather than
    // silently absent: the page has to be able to say so.
    CM_CHECK([[profile targetForSource:@"controller.button.options"] isEqualToString:AKControllerTargetNone],
             "an unavailable control defaults to nothing");
    CM_CHECK([[profile targetForSource:@"controller.button.share"] isEqualToString:AKControllerTargetNone],
             "share has no virtual target");
    CM_CHECK(!profile.customised, "a fresh profile is not customised");

    // Remapping, and the one-to-one rule that keeps two controls from fighting.
    [profile bindSource:@"controller.button.b" toTarget:@"virtual.button.a"];
    CM_CHECK([[profile targetForSource:@"controller.button.b"] isEqualToString:@"virtual.button.a"],
             "a source can be bound to another target");
    CM_CHECK([[profile targetForSource:@"controller.button.a"] isEqualToString:AKControllerTargetNone],
             "binding a target unmaps the source that had it");
    CM_CHECK(profile.customised, "a changed profile is customised");
    CM_CHECK([[profile sourceForTarget:@"virtual.button.a"] isEqualToString:@"controller.button.b"],
             "a target has exactly one source");

    // Persistence: a second instance reads the same table.
    AKControllerProfile *reloaded = [[AKControllerProfile alloc] initWithIdentity:CMIdentity
                                                                      vendorName:@"Fixture Vendor"
                                                                 productCategory:@"Fixture Category"
                                                                        defaults:defaults];
    CM_CHECK([[reloaded targetForSource:@"controller.button.b"] isEqualToString:@"virtual.button.a"],
             "a mapping survives a reload");

    [reloaded resetToDefault];
    CM_CHECK([[reloaded targetForSource:@"controller.button.a"] isEqualToString:@"virtual.button.a"],
             "reset restores the standard layout");
    CM_CHECK(!reloaded.customised, "reset clears the customised flag");
    CM_CHECK([defaults objectForKey:storageKey] == nil, "reset removes the stored table");
    puts("CONTROLLER_MANAGER_PROFILE_PASS: default layout, remap, one-to-one targets, reload, reset.");
}

static void CMTestRouting(CMRecorder *recorder, CMFakePad *pad) {
    AKControllerManager *manager = AKControllerManager.shared;
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)pad]; };
    [AKControllerProfile forgetIdentity:AKControllerIdentity((GCController *)(id)pad)
                              defaults:NSUserDefaults.standardUserDefaults];
    // A fresh profile for this pad, so the checks start from the standard layout.
    manager.enabled = NO;
    CM_CHECK(manager.state == AKControllerRoutingStateDisabled, "routing starts off");

    [recorder clear];
    [manager reportElement:@"controller.button.a" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(recorder.values.count == 0, "with routing off nothing is sent to a virtual pad");

    manager.enabled = YES;
    CM_CHECK(manager.state == AKControllerRoutingStateWaiting,
             "routing on with no virtual controller is waiting");
    CM_CHECK(manager.physicalControllerConnected, "the duck-typed pad counts as connected");

    // The virtual controller's own appearance is excluded from the hardware list.
    CMFakePad *virtual = [CMFakePad new];
    virtual.vendorName = @"Virtual";
    virtual.productCategory = @"Controller";
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)pad, (GCController *)(id)virtual]; };
    [manager noteVirtualPadConnected:(GCController *)(id)virtual];
    CM_CHECK(manager.state == AKControllerRoutingStateRouting, "a connected virtual pad means routing");

    // Analog pass-through, and the quantiser that stops a stream of identical values.
    [recorder clear];
    [manager reportElement:@"controller.button.left.trigger" value:0.5 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK([recorder hasValue:@"virtual.button.left.trigger=0.5000"], "a trigger's analog value is passed through");
    [recorder clear];
    [manager reportElement:@"controller.button.left.trigger" value:0.5001 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(recorder.values.count == 0, "a value that did not move is not resent");
    [manager reportElement:@"controller.button.left.trigger" value:0.25 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK([recorder hasValue:@"virtual.button.left.trigger=0.2500"], "a changed analog value is sent");
    [manager reportElement:@"controller.button.left.trigger" value:0 pressed:NO device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK([recorder hasValue:@"virtual.button.left.trigger=0.0000"], "a release is always sent");

    // Two sources, two targets. Both buttons are released first: the press made while
    // routing was off is still the pad's state, and it was replayed when routing started.
    [manager reportElement:@"controller.button.a" value:0 pressed:NO device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [manager reportElement:@"controller.button.b" value:0 pressed:NO device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [recorder clear];
    [manager reportElement:@"controller.button.a" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [manager reportElement:@"controller.button.b" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK([recorder hasValue:@"virtual.button.a=1.0000"] && [recorder hasValue:@"virtual.button.b=1.0000"],
             "two sources reach two targets");

    // An input the profile does not route, and one the pad has no target for.
    [recorder clear];
    [manager reportElement:@"controller.button.options" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [manager reportElement:@"controller.button.paddle1" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(recorder.values.count == 0, "an unmapped or unavailable input drives nothing");

    // Sticks and the D-pad, with the same quantiser.
    [recorder clear];
    [manager reportAxis:@"controller.axis.left.thumbstick" position:CGPointMake(0.5, -0.25) device:CMIdentity deviceName:@"Fixture"];
    CM_CHECK([recorder hasPosition:@"virtual.stick.left=0.5000,-0.2500"], "a stick position is passed through");
    [recorder clear];
    [manager reportAxis:@"controller.axis.left.thumbstick" position:CGPointMake(0.5002, -0.2501) device:CMIdentity deviceName:@"Fixture"];
    CM_CHECK(recorder.positions.count == 0, "a stick that did not move is not resent");
    [manager reportAxis:@"dpad.dpad" position:CGPointMake(-1, 1) device:CMIdentity deviceName:@"Fixture"];
    CM_CHECK([recorder hasPosition:@"virtual.dpad=-1.0000,1.0000"], "the D-pad is sent as a position");

    // Duplicate models share one profile, and the page is told how many there are.
    CMFakePad *twin = [[CMFakePad alloc] initWithVendor:pad.vendorName category:pad.productCategory];
    manager.controllersProvider = ^NSArray<GCController *> *{
        return @[(GCController *)(id)pad, (GCController *)(id)twin, (GCController *)(id)virtual];
    };
    NSArray<AKControllerModel *> *models = manager.models;
    CM_CHECK(models.count == 1, "two pads of one model are one model on the page");
    CM_CHECK(models.firstObject.count == 2, "the page can say two of them are connected");
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)pad, (GCController *)(id)virtual]; };

    puts("CONTROLLER_MANAGER_ROUTING_PASS: analog pass-through, quantisation, releases, multiple sources, unmapped inputs, axes, duplicate models.");
}

static void CMTestLifecycle(CMRecorder *recorder, CMFakePad *pad) {
    AKControllerManager *manager = AKControllerManager.shared;
    CMFakePad *virtual = [CMFakePad new];
    [manager noteVirtualPadConnected:(GCController *)(id)virtual];

    // A held button, then the pad goes away: the value must be released, never left held.
    [manager reportElement:@"controller.button.a" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [recorder clear];
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)virtual]; };
    [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidDisconnectNotification object:(GCController *)(id)pad];
    CM_CHECK(manager.state == AKControllerRoutingStateWaiting, "a disconnect leaves routing waiting");
    CM_CHECK(recorder.releases == 1, "a disconnect releases every routed value");

    // Reconnect: routing resumes without the user touching the switch.
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)pad, (GCController *)(id)virtual]; };
    [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:(GCController *)(id)pad];
    [manager noteVirtualPadConnected:(GCController *)(id)virtual];
    CM_CHECK(manager.state == AKControllerRoutingStateRouting, "a reconnect resumes routing");

    // A virtual controller that will not connect fails closed: nothing routed, nothing held.
    [recorder clear];
    [manager reportElement:@"controller.button.b" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [recorder clear];
    [manager noteVirtualPadFailed:@"fixture refused"];
    CM_CHECK(manager.state == AKControllerRoutingStateFailed, "a failed virtual controller is reported as failed");
    CM_CHECK(recorder.releases == 1, "a failure releases every routed value");
    [recorder clear];
    [manager reportElement:@"controller.button.y" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(recorder.values.count == 0, "a failed virtual controller routes nothing");

    // Backgrounding releases; coming back starts again from the pad's current state.
    [manager noteVirtualPadConnected:(GCController *)(id)virtual];
    [manager reportElement:@"controller.button.x" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [recorder clear];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    CM_CHECK(recorder.releases == 1, "backgrounding releases every routed value");
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    CM_CHECK(manager.state == AKControllerRoutingStateRouting, "coming back keeps routing on");

    // Switching off releases and gives the pad back. Every button is released first, so the
    // pad's stored state is neutral and the checks below are about the switch, not about a
    // press that was still being held.
    for (NSString *element in @[@"controller.button.a", @"controller.button.b",
                                @"controller.button.x", @"controller.button.y"])
        [manager reportElement:element value:0 pressed:NO device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [manager reportElement:@"controller.button.x" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    [recorder clear];
    manager.enabled = NO;
    CM_CHECK(recorder.releases == 1, "switching off releases every routed value");
    CM_CHECK(manager.state == AKControllerRoutingStateDisabled, "switching off is reported");
    [recorder clear];
    [manager reportElement:@"controller.button.x" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(recorder.values.count == 0, "after switching off nothing is routed");

    manager.enabled = YES;
    [manager noteVirtualPadConnected:(GCController *)(id)virtual];
    [recorder clear];
    // The routed-value cache was cleared on the way out, so the same value is a change
    // again rather than being suppressed as a repeat.
    [manager reportElement:@"controller.button.b" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK([recorder hasValue:@"virtual.button.b=1.0000"], "a fresh press after re-enabling is sent");
    puts("CONTROLLER_MANAGER_LIFECYCLE_PASS: disconnect, reconnect, virtual-connect failure, backgrounding, enable/disable and every held-state release.");
}

static void CMTestLearning(void) {
    AKControllerManager *manager = AKControllerManager.shared;
    AKControllerProfile *profile = [manager profileForIdentity:CMIdentity];
    [profile resetToDefault];

    __block NSString *learnedIdentity = nil, *learnedSource = nil;
    __block NSUInteger learnCount = 0;
    manager.onLearned = ^(NSString *identity, NSString *source) {
        learnedIdentity = identity; learnedSource = source; learnCount++;
    };

    [manager beginLearningForIdentity:CMIdentity];
    CM_CHECK(manager.learning, "learning arms");
    // A press on another controller must not rewrite this one's profile.
    [manager reportElement:@"controller.button.x" value:1 pressed:YES device:@"other.vendor.other" deviceName:@"Other" source:@"controller"];
    CM_CHECK(manager.learning && learnCount == 0, "a press on another controller is ignored");
    [manager reportElement:@"controller.button.y" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(!manager.learning, "a press on the right controller ends learning");
    CM_CHECK(learnCount == 1 && [learnedSource isEqualToString:@"controller.button.y"], "the captured source is reported");
    CM_CHECK([learnedIdentity isEqualToString:CMIdentity], "the identity is reported with it");

    // A stick counts as a source once it has actually moved.
    [manager beginLearningForIdentity:CMIdentity];
    [manager reportAxis:@"controller.axis.right.thumbstick" position:CGPointMake(0.05, 0) device:CMIdentity deviceName:@"Fixture"];
    CM_CHECK(manager.learning, "a stick inside the dead zone is not a source");
    [manager reportAxis:@"controller.axis.right.thumbstick" position:CGPointMake(0.9, 0) device:CMIdentity deviceName:@"Fixture"];
    CM_CHECK(!manager.learning && learnCount == 2 && [learnedSource isEqualToString:@"controller.axis.right.thumbstick"],
             "a stick movement beyond the dead zone is a source");

    // Explicit cancellation adopts nothing, and leaves nothing armed.
    [manager beginLearningForIdentity:CMIdentity];
    [manager cancelLearning];
    CM_CHECK(!manager.learning && learnCount == 2, "cancelling adopts nothing");
    [manager reportElement:@"controller.button.x" value:1 pressed:YES device:CMIdentity deviceName:@"Fixture" source:@"controller"];
    CM_CHECK(learnCount == 2, "a press after cancelling is not adopted");

    // Going to the background disarms it, like the voice mapper.
    [manager beginLearningForIdentity:CMIdentity];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    CM_CHECK(!manager.learning, "backgrounding cancels learning");
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    manager.onLearned = nil;
    puts("CONTROLLER_MANAGER_LEARNING_PASS: arm, wrong-controller rejection, button and stick capture, cancel, background cancellation.");
}

static void CMTestGestureReasons(void) {
    AKControllerManager *manager = AKControllerManager.shared;
    CMFakePad *pad = [[CMFakePad alloc] initWithVendor:@"Fixture Vendor" category:@"Fixture Category"];
    CMFakePad *virtual = [CMFakePad new];
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)pad, (GCController *)(id)virtual]; };
    // Toggle so the profile and gestures are re-decided for this pad, exactly as switching
    // the feature on with a controller already connected would.
    manager.enabled = NO;
    manager.enabled = YES;
    [manager noteVirtualPadConnected:(GCController *)(id)virtual];

    CMFakeButton *menu = pad.physicalInputProfile.buttons[GCInputButtonMenu];
    CMFakeButton *face = pad.physicalInputProfile.buttons[GCInputButtonA];
    // Routing a reserved button asks iPadOS to let the press through; a face button does not.
    CM_CHECK(menu.preferredSystemGestureState == GCSystemGestureStateDisabled,
             "a routed reserved button has its gesture released");
    CM_CHECK(face.preferredSystemGestureState == GCSystemGestureStateEnabled,
             "an ordinary face button's gesture is untouched");

    // The voice feature's own releases are separate: the router's "give everything back"
    // must not undo routing's release, or routing would silently stop seeing the button.
    [manager restoreAllSystemGestures];
    CM_CHECK(menu.preferredSystemGestureState == GCSystemGestureStateDisabled,
             "restoring voice gestures leaves routing's release alone");

    // A profile that no longer routes the button gives the gesture back.
    AKControllerProfile *profile = [manager profileForIdentity:CMIdentity];
    [profile bindSource:@"controller.button.menu" toTarget:AKControllerTargetNone];
    [manager applyProfileChangeForIdentity:CMIdentity];
    CM_CHECK(menu.preferredSystemGestureState == GCSystemGestureStateEnabled,
             "unrouting a reserved button gives its gesture back");

    [profile resetToDefault];
    [manager applyProfileChangeForIdentity:CMIdentity];
    manager.enabled = NO;
    CM_CHECK(menu.preferredSystemGestureState == GCSystemGestureStateEnabled,
             "switching routing off gives every gesture back");
    puts("CONTROLLER_MANAGER_GESTURE_PASS: released only for routed reserved buttons, independent of voice releases, restored on unroute and on disable.");
}

static void RunAll(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverControllerRouting"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:
        [NSString stringWithFormat:@"WolkaraForeverControllerProfile.%@", CMIdentity]];

    AKControllerManager *manager = AKControllerManager.shared;
    manager.enabled = NO;
    manager.controllersProvider = nil;

    CMRecorder *recorder = [CMRecorder new];
    [recorder observe];

    CMTestProfile();

    CMFakePad *pad = [[CMFakePad alloc] initWithVendor:@"Fixture Vendor" category:@"Fixture Category"];
    [manager begin];

    // The interlock: the guest-facing GameController adapter is what hides the physical pad,
    // and it is a separate binary. Until it is known to be in the process, routing refuses -
    // a press that reached the game twice is worse than a feature that says it cannot run.
    manager.controllersProvider = ^NSArray<GCController *> *{ return @[(GCController *)(id)pad]; };
    CM_CHECK(!manager.guestFacadePresent, "no facade is present yet");
    manager.enabled = YES;
    CM_CHECK(manager.state == AKControllerRoutingStateFailed, "routing refuses without the guest facade");
    CM_CHECK(manager.statusDetail.length > 0, "the refusal is explained");
    manager.enabled = NO;

    // In the fixture it is this call that stands in for the adapter announcing itself.
    [manager noteGuestFacadePresent];
    CM_CHECK(manager.guestFacadePresent, "the facade is present once it has announced itself");
    CMTestRouting(recorder, pad);
    CMTestLifecycle(recorder, pad);
    CMTestLearning();
    CMTestGestureReasons();

    manager.controllersProvider = nil;
    manager.enabled = NO;
    puts("CONTROLLER_MANAGER_PASS: profile, routing, lifecycle, learning and gesture ownership.");
}

#pragma mark - Host

@interface CMFixtureScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation CMFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.12 alpha:1];
    UILabel *label = [UILabel new];
    label.text = @"Controller Manager fixture";
    label.textColor = UIColor.whiteColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [root.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:root.view.centerYAnchor],
    ]];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(start) withObject:nil afterDelay:0.5];
}
- (void)start {
    RunAll();
    fflush(stdout);
    exit(0);
}
@end

@interface CMFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation CMFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Controller Manager fixture" sessionRole:session.role];
    config.delegateClass = CMFixtureScene.class;
    return config;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            fputs("CONTROLLER_MANAGER_TIMEOUT\n", stderr);
            _Exit(1);
        });
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CMFixtureApp.class));
    }
}
