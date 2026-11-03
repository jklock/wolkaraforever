// Synthetic guest against the GameController façade.
//
// This is the one fixture that must NOT link Apple's GameController: the whole point of the
// façade is that it *is* `GCController` for the guest, and linking the real framework would
// put two classes with that name in one process. So the "manager" here is a stand-in that
// publishes the same notifications the real one does, and the assertions are about what the
// guest can see:
//
//   routing off  the physical pads the host published, unchanged, with their events
//   routing on   exactly one controller - the manager's virtual one - and no physical
//                pad's connect or disconnect ever crossing into the guest
//
// The value-level end of the chain (a remapped press becoming a write on the hidden
// GCVirtualController) is proven by test_controller_manager.sh and by the routing checks in
// test_touch_gamepad_ui.sh; between them the three fixtures cover the whole path.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "../translation/AKSupport/AKSupport.h"
#include <dlfcn.h>

#include <assert.h>

// The host's channel, by value: this fixture plays the Controller Manager's part.
static NSString *const GuestViewRequest = @"AKControllerGuestViewRequest";
static NSString *const GuestViewChanged = @"AKControllerGuestViewDidChange";
static NSString *const GuestViewControllersKey = @"controllers";
static NSString *const GuestViewRoutingKey = @"routing";

// The names the façade defines and posts. Declared here because the fixture includes the
// adapter's source, not a header.
extern NSString *const GCControllerDidConnectNotification;
extern NSString *const GCControllerDidDisconnectNotification;

#define GUEST_CHECK(condition, label) do { \
    if (!(condition)) { \
        fprintf(stderr, "GAMECONTROLLER_FACADE_FAIL: %s (%s:%d)\n", (label), __FILE__, __LINE__); \
        fflush(stderr); \
        _Exit(1); \
    } \
} while (0)

#pragma mark - Stand-in hardware

@interface GuestFakePad : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isAttachedToDevice;
@end
@implementation GuestFakePad
- (NSString *)description { return self.name; }
@end

// A notification carries whatever the façade posted; naming it without messaging an
// unknown selector keeps this fixture compiling under ARC.
static NSString *GuestName(id object) {
    return [object isKindOfClass:GuestFakePad.class] ? ((GuestFakePad *)object).name : @"?";
}

#pragma mark - Stand-in manager

@interface GuestHost : NSObject
@property (nonatomic) NSArray *physical;
@property (nonatomic) NSArray *virtual;
@property (nonatomic) BOOL routing;
@property (nonatomic) NSMutableArray<NSString *> *connects;
@property (nonatomic) NSMutableArray<NSString *> *disconnects;
- (void)publish;
@end
@implementation GuestHost
- (instancetype)init {
    if ((self = [super init])) {
        _connects = [NSMutableArray array];
        _disconnects = [NSMutableArray array];
    }
    return self;
}
- (NSArray *)guestControllers {
    if (!self.routing) return self.physical ?: @[];
    return self.virtual ?: @[];
}
- (void)publish {
    [NSNotificationCenter.defaultCenter postNotificationName:GuestViewChanged
                                                     object:nil
                                                   userInfo:@{GuestViewControllersKey: self.guestControllers,
                                                              GuestViewRoutingKey: @(self.routing)}];
}
- (void)start {
    __weak GuestHost *weakSelf = self;
    [NSNotificationCenter.defaultCenter addObserverForName:GuestViewRequest object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        (void)note;
        [weakSelf publish];
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        [weakSelf.connects addObject:GuestName(note.object)];
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidDisconnectNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        [weakSelf.disconnects addObject:GuestName(note.object)];
    }];
    [self publish];
}
@end

// The façade's own class, as the guest binds it.
@interface GCController : AKStubObject
+ (NSArray *)controllers;
+ (id)current;
@end

// Declared exactly as the adapter declares them, so this fixture can ask what the guest's
// -isKindOfClass: will compare against.
@interface GCControllerButtonInput : AKStubObject
@end
@interface GCControllerAxisInput : AKStubObject
@end
@interface GCColor : AKStubObject
@end

// A standalone adapter shadows Apple's class of the same name, so a plain stub would answer NO
// to the guest's -isKindOfClass: about objects the manager hands over. These three answer
// +class with Apple's real class; this proves it, because the guest's own comparisons go
// through exactly that call.
static void CheckClassIdentity(void) {
    void *framework = dlopen("/System/Library/Frameworks/GameController.framework/GameController", RTLD_LAZY);
    GUEST_CHECK(framework != NULL, "the real GameController framework is present");
    NSArray<NSString *> *symbols = @[@"OBJC_CLASS_$_GCControllerButtonInput",
                                     @"OBJC_CLASS_$_GCControllerAxisInput",
                                     @"OBJC_CLASS_$_GCColor"];
    NSArray<Class> *bound = @[[GCControllerButtonInput class], [GCControllerAxisInput class], [GCColor class]];
    for (NSUInteger index = 0; index < symbols.count; index++) {
        Class real = (__bridge Class)dlsym(framework, symbols[index].UTF8String);
        GUEST_CHECK(real != Nil, "the real element class is exported by the framework");
        GUEST_CHECK(bound[index] == real, "the bound element class is Apple's, not the adapter's stub");
    }
}

#pragma mark - Checks

static void RunChecks(GuestHost *host) {
    CheckClassIdentity();
    GuestFakePad *bluetooth = [GuestFakePad new];
    bluetooth.name = @"Bluetooth";
    bluetooth.isAttachedToDevice = NO;
    GuestFakePad *usb = [GuestFakePad new];
    usb.name = @"USB";
    usb.isAttachedToDevice = YES;

    // --- Routing off: the direct path, unchanged -------------------------------------
    host.routing = NO;
    host.physical = @[bluetooth, usb];
    [host publish];
    GUEST_CHECK(GCController.controllers.count == 2, "routing off exposes the physical pads");
    GUEST_CHECK([GCController.controllers containsObject:bluetooth] && [GCController.controllers containsObject:usb],
                "routing off exposes both pads by identity");
    GUEST_CHECK(GCController.current == usb, "current prefers the pad the system says is attached");
    GUEST_CHECK([host.connects containsObject:@"Bluetooth"] && [host.connects containsObject:@"USB"],
                "routing off delivers the physical connect events");

    // A pad arriving while routing is off is delivered, as it always was.
    GuestFakePad *late = [GuestFakePad new];
    late.name = @"Late";
    host.physical = @[bluetooth, usb, late];
    [host.connects removeAllObjects];
    [host publish];
    GUEST_CHECK([host.connects containsObject:@"Late"], "a pad connected while routing is off reaches the guest");
    host.physical = @[bluetooth, usb];

    // --- Routing on: one virtual controller, no hardware -----------------------------
    GuestFakePad *virtual = [GuestFakePad new];
    virtual.name = @"Virtual";
    virtual.isAttachedToDevice = YES;
    host.virtual = @[virtual];
    host.routing = YES;
    [host.connects removeAllObjects];
    [host.disconnects removeAllObjects];
    [host publish];

    GUEST_CHECK(GCController.controllers.count == 1, "routing on exposes exactly one controller");
    GUEST_CHECK(GCController.controllers.firstObject == virtual, "the one controller is the manager's virtual one");
    GUEST_CHECK(GCController.current == virtual, "current is the virtual controller while routing");
    GUEST_CHECK(![GCController.controllers containsObject:bluetooth] && ![GCController.controllers containsObject:usb],
                "no physical pad is enumerated while routing");
    GUEST_CHECK([host.disconnects containsObject:@"Bluetooth"] && [host.disconnects containsObject:@"USB"],
                "the physical pads are reported as gone when routing starts");
    GUEST_CHECK([host.connects containsObject:@"Virtual"], "the virtual controller is reported as connected");
    GUEST_CHECK(![host.connects containsObject:@"Bluetooth"] && ![host.connects containsObject:@"USB"],
                "no physical pad is reported as connected while routing");

    // A physical pad arriving while routing is on must be invisible: this is the whole
    // reason the façade exists.
    GuestFakePad *intruder = [GuestFakePad new];
    intruder.name = @"Intruder";
    host.physical = @[bluetooth, usb, intruder];
    [host.connects removeAllObjects];
    [host.disconnects removeAllObjects];
    [host publish];
    GUEST_CHECK(GCController.controllers.count == 1 && GCController.controllers.firstObject == virtual,
                "a pad connected while routing does not join the guest's list");
    GUEST_CHECK(![host.connects containsObject:@"Intruder"] && ![host.disconnects containsObject:@"Virtual"],
                "a pad connected while routing produces no event for the guest");

    // The virtual controller going away leaves nothing rather than falling back to hardware.
    host.virtual = @[];
    [host.connects removeAllObjects];
    [host.disconnects removeAllObjects];
    [host publish];
    GUEST_CHECK(GCController.controllers.count == 0, "with no virtual controller the guest sees none");
    GUEST_CHECK(![host.connects containsObject:@"Bluetooth"] && ![host.connects containsObject:@"USB"],
                "losing the virtual controller does not reveal the physical pads");

    // --- Routing off again: the direct path is restored ------------------------------
    host.virtual = @[virtual];
    [host publish];
    host.routing = NO;
    host.physical = @[bluetooth, usb];
    [host.connects removeAllObjects];
    [host.disconnects removeAllObjects];
    [host publish];
    GUEST_CHECK(GCController.controllers.count == 2, "switching routing off restores the physical pads");
    GUEST_CHECK([host.disconnects containsObject:@"Virtual"], "the virtual controller is reported gone");
    GUEST_CHECK([host.connects containsObject:@"Bluetooth"] && [host.connects containsObject:@"USB"],
                "the physical pads are reported back to the guest");

    // Nothing here leaked hardware while routing ran: every physical connect the guest saw
    // happened while routing was off, which the check above proves by construction.
    puts("GAMECONTROLLER_FACADE_PASS: direct path unchanged when off, exactly one virtual controller when on, no physical pad or event crossing.");
}

#pragma mark - Host

@interface GuestFacadeScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) GuestHost *host;
@end
@implementation GuestFacadeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.07 blue:0.12 alpha:1];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(start) withObject:nil afterDelay:0.4];
}
- (void)start {
    self.host = [GuestHost new];
    [self.host start];
    RunChecks(self.host);
    fflush(stdout);
    exit(0);
}
@end

@interface GuestFacadeApp : UIResponder <UIApplicationDelegate>
@end
@implementation GuestFacadeApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"GameController façade fixture" sessionRole:session.role];
    config.delegateClass = GuestFacadeScene.class;
    return config;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            fputs("GAMECONTROLLER_FACADE_TIMEOUT\n", stderr);
            _Exit(1);
        });
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(GuestFacadeApp.class));
    }
}
