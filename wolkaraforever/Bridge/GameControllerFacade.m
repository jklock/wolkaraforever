// GameController adapter: what World of Warcraft is allowed to see.
//
// Replaces the platform's stub (translation/GameController/GameController.m, which the
// "standalone" marker keeps opt-in and which hides every controller from every
// application). This one is WolkaraForever's: it is only built for a WoW profile, and it
// exists because of a fact the note in development/technical/CONTROLLER_PROFILES.md
// established by measurement - our host and the guest share one process and one
// GameController, so anything the framework reports it reports to both. There is no
// public API that hides a physical pad from one consumer and not the other.
//
// The only lever is the class the guest binds. Because this adapter is "standalone",
// classify.py plans every GameController import for it, so the guest's
// _OBJC_CLASS_$_GCController resolves here rather than to Apple's class. Two behaviour
// modes follow from that:
//
//   routing off   +controllers returns exactly what the host published - the real,
//                 physical pads. Same objects, same order, same notifications, so the
//                 direct path WoW has always used is behaviourally unchanged.
//   routing on    +controllers returns the one hidden GCVirtualController the Controller
//                 Manager drives. Physical pads are not in it, and this adapter posts no
//                 connect or disconnect for them, so they never cross into the game.
//
// The host publishes the view and this adapter caches the answer; the Controller Manager
// (launcher/Controller) is the single owner of the decision. The channel is
// NSNotificationCenter, by name, because the manager is in the app and this file in a
// dylib the app never links. The names are spelled out in both files with a comment
// pointing at the other - the same arrangement AKTouchOwnedKeyUsagesDidChange uses.
//
// Everything else is upstream's, unchanged: the constant values, the namespaced
// notification names (the real framework is loaded beside this shim by the AppKit
// adapter, which links it for GCMouse raw input), and the empty profile classes. An
// import this file does not define is a real risk rather than a harmless stub, so
// wolkaraforever/tools/check_gamecontroller_facade.sh compares this file's definitions
// with what the application imports and fails the build when anything is uncovered.
#import "AKSupport.h"
#include <dlfcn.h>

// --- The Controller Manager's channel, by value --------------------------------------
// Declared in wolkaraforever/Controller/ControllerManager.h; spelled out here because the
// two live in different binaries.
static NSString *const AKGuestViewRequestNotification = @"AKControllerGuestViewRequest";
static NSString *const AKGuestViewDidChangeNotification = @"AKControllerGuestViewDidChange";
static NSString *const AKGuestViewControllersKey = @"controllers";
static NSString *const AKGuestViewRoutingKey = @"routing";
// Announced once when this adapter loads, and again whenever the manager asks. The host
// refuses to route until it has heard one: without this façade the guest would see the
// physical pad *and* the virtual one, and a press would arrive twice.
static NSString *const AKGuestFacadePresentNotification = @"AKControllerGuestFacadePresent";
static NSString *const AKGuestFacadeQueryNotification = @"AKControllerGuestFacadeQuery";

// Loaded when the guest's GameController imports are bound, which is before its main.
__attribute__((constructor))
static void AKGuestFacadeAnnounce(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:AKGuestFacadePresentNotification object:nil];
}

// Defined at the bottom with the rest of upstream's constants; used by the publisher
// above, so the names are declared first.
extern NSString *const GCControllerDidConnectNotification;
extern NSString *const GCControllerDidDisconnectNotification;
extern NSString *const GCControllerDidBecomeCurrentNotification;

static NSObject *AKGuestStateObject(void) {
    static NSObject *object;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ object = [NSObject new]; });
    return object;
}

// Last answer from the manager. `valid` distinguishes "the manager says no controllers"
// from "nobody has asked yet", which matters: the former is an answer and the latter has
// to be resolved before the guest is told there is no controller.
static NSArray *AKGuestControllersCache;
static BOOL AKGuestCacheValid;
static BOOL AKGuestRoutingCache;

static void AKGuestPostConnectDisconnect(NSArray *previous, NSArray *current) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // One rule for both modes: whatever left the guest's list is gone, whatever joined it
    // has arrived. While routing is on the list holds only the virtual controller, so a
    // physical pad can appear in neither the connect nor the disconnect it produces - which
    // is the whole point of the adapter. While it is off the list is the real one, so the
    // events are the real ones too, re-posted under the names the guest bound.
    for (id controller in previous)
        if (![current containsObject:controller])
            [center postNotificationName:GCControllerDidDisconnectNotification object:controller];
    for (id controller in current) {
        if ([previous containsObject:controller]) continue;
        [center postNotificationName:GCControllerDidConnectNotification object:controller];
        // The only controller the guest can see while routing is also the current one.
        if (AKGuestRoutingCache)
            [center postNotificationName:GCControllerDidBecomeCurrentNotification object:controller];
    }
}

static void AKGuestApplyView(NSDictionary *info) {
    id controllers = info[AKGuestViewControllersKey];
    NSArray *next = [controllers isKindOfClass:NSArray.class] ? [controllers copy] : @[];
    BOOL routing = [info[AKGuestViewRoutingKey] boolValue];
    NSArray *previous = nil;
    BOOL hadPrevious = NO;
    @synchronized (AKGuestStateObject()) {
        hadPrevious = AKGuestCacheValid;
        previous = AKGuestControllersCache;
        AKGuestControllersCache = next;
        AKGuestRoutingCache = routing;
        AKGuestCacheValid = YES;
    }
    // Outside the lock: posting runs the guest's observers on this thread.
    if (hadPrevious && ![previous isEqualToArray:next]) AKGuestPostConnectDisconnect(previous, next);
    else if (!hadPrevious) AKGuestPostConnectDisconnect(@[], next);
}

static void AKGuestEnsureObserving(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:AKGuestViewDidChangeNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification *note) {
            AKGuestApplyView(note.userInfo);
        }];
        // The host asks when it wants to be sure, because it may have started before this
        // adapter was loaded.
        [NSNotificationCenter.defaultCenter addObserverForName:AKGuestFacadeQueryNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification *note) {
            (void)note;
            [NSNotificationCenter.defaultCenter postNotificationName:AKGuestFacadePresentNotification object:nil];
        }];
    });
}

// The manager answers synchronously, so this returns the current view on its first call.
static NSArray *AKGuestControllers(void) {
    AKGuestEnsureObserving();
    NSArray *known = nil;
    @synchronized (AKGuestStateObject()) { if (AKGuestCacheValid) known = AKGuestControllersCache; }
    if (!known) {
        [NSNotificationCenter.defaultCenter postNotificationName:AKGuestViewRequestNotification object:nil];
        @synchronized (AKGuestStateObject()) { known = AKGuestCacheValid ? AKGuestControllersCache : @[]; }
    }
    return known;
}

@interface GCController : AKStubObject
@end

// The real controller's own answer, without importing its header: this adapter must not
// depend on Apple's declarations, because the class it names is this file's.
@protocol AKGuestAttachedController <NSObject>
- (BOOL)isAttachedToDevice;
@end

@implementation GCController
+ (NSArray *)controllers { return AKGuestControllers(); }
+ (id)current {
    NSArray *controllers = AKGuestControllers();
    // Prefer the pad the system says is attached to this device, which is what Apple's
    // -current means; fall back to the only one there is.
    for (id<AKGuestAttachedController> controller in controllers) {
        if ([controller respondsToSelector:@selector(isAttachedToDevice)] &&
            [controller isAttachedToDevice]) return controller;
    }
    return controllers.firstObject;
}
// Wireless discovery is a host feature. While a session runs there is nothing to
// discover - the Controller Manager owns pairing and delivery - so the handler is called
// at once rather than left waiting for a scan this adapter never starts.
+ (void)startWirelessControllerDiscoveryWithCompletionHandler:(void (^)(void))completionHandler {
    if (completionHandler) completionHandler();
}
+ (void)stopWirelessControllerDiscovery {}
@end

@interface GCDualSenseGamepad : AKStubObject
@end
@implementation GCDualSenseGamepad
@end

@interface GCDualShockGamepad : AKStubObject
@end
@implementation GCDualShockGamepad
@end

// --- Class identity for the element classes a guest imports --------------------------
//
// A standalone adapter shadows Apple's class of the same name for the guest. For the three
// classes measured in World of Warcraft's import list that would be worse than useless: the
// guest asks -isKindOfClass: about objects the manager hands over, those objects are Apple's,
// and a shadow answer of NO would make the game stop recognising its own buttons.
//
// So each of these answers +class with the class the *real* framework defines, found by
// symbol rather than by name - a name lookup would return whichever of the two images was
// registered first, which is exactly the ambiguity this file exists to avoid. The real
// framework is already in the process (the AppKit adapter links it), so this adds nothing.
// Measured against build/guest-probe/WorldOfWarcraft on 2026-11-03; these were the only three
// uncovered imports.
static Class AKGuestRealClass(const char *symbol) {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/Frameworks/GameController.framework/GameController", RTLD_LAZY);
    });
    return framework ? (__bridge Class)dlsym(framework, symbol) : Nil;
}

@interface GCControllerButtonInput : AKStubObject
@end
@implementation GCControllerButtonInput
+ (Class)class { return AKGuestRealClass("OBJC_CLASS_$_GCControllerButtonInput") ?: self; }
@end

@interface GCControllerAxisInput : AKStubObject
@end
@implementation GCControllerAxisInput
+ (Class)class { return AKGuestRealClass("OBJC_CLASS_$_GCControllerAxisInput") ?: self; }
@end

@interface GCColor : AKStubObject
@end
@implementation GCColor
+ (Class)class { return AKGuestRealClass("OBJC_CLASS_$_GCColor") ?: self; }
@end

// Connect, disconnect and current-controller names are deliberately namespaced:
// the real framework is loaded beside this shim and posts the real names.
NSString *const GCControllerDidConnectNotification = @"AKGCControllerDidConnectNotification";
NSString *const GCControllerDidDisconnectNotification = @"AKGCControllerDidDisconnectNotification";
NSString *const GCControllerDidBecomeCurrentNotification = @"AKGCControllerDidBecomeCurrentNotification";
NSString *const GCControllerDidStopBeingCurrentNotification = @"AKGCControllerDidStopBeingCurrentNotification";
NSString *const GCMouseDidConnectNotification = @"AKGCMouseDidConnectNotification";
NSString *const GCMouseDidDisconnectNotification = @"AKGCMouseDidDisconnectNotification";
NSString *const GCKeyboardDidConnectNotification = @"AKGCKeyboardDidConnectNotification";
NSString *const GCKeyboardDidDisconnectNotification = @"AKGCKeyboardDidDisconnectNotification";
// Everything else has its macOS value (checked against the host framework), so
// an application that keys dictionaries or compares names with them keeps working.
NSString *const GCProductCategoryDualSense = @"DualSense";
NSString *const GCProductCategoryDualShock4 = @"DualShock 4";
NSString *const GCProductCategoryXboxOne = @"Xbox One";
NSString *const GCHapticsLocalityDefault = @"Default";
NSString *const GCHapticsLocalityAll = @"All";
NSString *const GCHapticsLocalityHandles = @"Handles";
NSString *const GCHapticsLocalityLeftHandle = @"Left Handle";
NSString *const GCHapticsLocalityRightHandle = @"Right Handle";
NSString *const GCHapticsLocalityTriggers = @"Triggers";
NSString *const GCHapticsLocalityLeftTrigger = @"Left Trigger";
NSString *const GCHapticsLocalityRightTrigger = @"Right Trigger";
NSString *const GCInputButtonA = @"Button A";
NSString *const GCInputButtonB = @"Button B";
NSString *const GCInputButtonX = @"Button X";
NSString *const GCInputButtonY = @"Button Y";
NSString *const GCInputButtonMenu = @"Button Menu";
NSString *const GCInputButtonOptions = @"Button Options";
NSString *const GCInputButtonHome = @"Button Home";
NSString *const GCInputDualShockTouchpadButton = @"Touchpad Button";
NSString *const GCInputDualShockTouchpadOne = @"Touchpad 1";
NSString *const GCInputDualShockTouchpadTwo = @"Touchpad 2";
NSString *const GCInputLeftShoulder = @"Left Shoulder";
NSString *const GCInputRightShoulder = @"Right Shoulder";
NSString *const GCInputLeftTrigger = @"Left Trigger";
NSString *const GCInputRightTrigger = @"Right Trigger";
NSString *const GCInputLeftThumbstick = @"Left Thumbstick";
NSString *const GCInputRightThumbstick = @"Right Thumbstick";
NSString *const GCInputLeftThumbstickButton = @"Left Thumbstick Button";
NSString *const GCInputRightThumbstickButton = @"Right Thumbstick Button";
NSString *const GCInputDirectionPad = @"Direction Pad";
NSString *const GCInputXboxPaddleOne = @"Paddle 1";
NSString *const GCInputXboxPaddleTwo = @"Paddle 2";
NSString *const GCInputXboxPaddleThree = @"Paddle 3";
NSString *const GCInputXboxPaddleFour = @"Paddle 4";
const float GCHapticDurationInfinite = 1000000.0f;
