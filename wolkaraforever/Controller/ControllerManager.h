// WolkaraForever layer: the one host-side owner of physical controller input.
//
// Before this file there were two readers of the same pads: the inspector (which logged
// and forwarded them to the voice router) and, separately, nothing else. Routing a pad
// through a virtual controller needs a single owner that knows which physical control is
// down, which virtual control it drives, and who asked iPadOS to stop keeping a press -
// because three owners of that state is exactly how a held button is left stuck.
//
// So the manager owns:
//   * discovery of physical controllers, and every handler installed on their elements;
//   * normalized state (what is down, where the sticks are), per model identity;
//   * remap profiles (see ControllerProfile) and the learn/reassign/cancel flow;
//   * system-gesture release, tagged by *reason*, so the voice feature's releases and
//     routing's releases cannot undo each other;
//   * the routing decision and its lifecycle - enable, disable, model change, pad
//     disconnect, backgrounding - and releasing every virtual value on each of them;
//   * one published view of "what the guest may see", which the GameController façade
//     reads so that physical pads never reach World of Warcraft.
//
// The inspector and the input router consume -onEvent: and nothing else. They no longer
// install handlers, which is what stops the two of them competing for the same element.
//
// This file is the *app's* half. The hidden GCVirtualController itself lives in
// translation/AppKit/TouchGamepad.m, inside the AppKit adapter dylib, which the app never
// links; the two halves talk over NSNotificationCenter by the names below. That is the
// same channel AKTouchOwnedKeyUsagesDidChange uses, and for the same reason.

#import <Foundation/Foundation.h>

#import "ControllerProfile.h"

NS_ASSUME_NONNULL_BEGIN

@class GCController;

typedef NS_ENUM(NSInteger, AKControllerRoutingState) {
    /// The user has not asked for routing; physical pads reach the guest directly.
    AKControllerRoutingStateDisabled = 0,
    /// Routing is on and this is not the reason it is not running: no pad, or the
    /// virtual controller is still connecting.
    AKControllerRoutingStateWaiting,
    /// The virtual controller is connected and physical input is being routed into it.
    AKControllerRoutingStateRouting,
    /// The virtual controller refused to connect. Nothing is routed, and the physical
    /// pads are left exactly as they were.
    AKControllerRoutingStateFailed,
};

/// Posted whenever anything the Controller Manager page shows has changed: the switch,
/// the state, the connected models, a mapping, or the learn flow.
FOUNDATION_EXPORT NSNotificationName const AKControllerManagerDidChangeNotification;

// --- The adapter channel -------------------------------------------------------------
//
// Observed by translation/AppKit/TouchGamepad.m. Every name is spelled out on both sides
// because the adapter is a signed dylib the app does not link; the companion comment is
// in wolkaraforever/Touch/TouchGamepad.m.
//
// `enabled` (BOOL)       routing on or off. Turning it on asks for the virtual pad;
//                        turning it off releases every value and gives the pad back.
// `element` (NSString)   a virtual target id from ControllerProfile
//                        ("virtual.button.a", "virtual.stick.left"); `value` (double).
// `element`, `x`, `y`    a virtual axis target and its position.
// (no payload)           release every virtual value. Sent on disable, on the active
//                        controller going away, on backgrounding, and before the pad is
//                        disconnected, so no button is ever left held.
FOUNDATION_EXPORT NSNotificationName const AKControllerRouteStateNotification;
// Posted *by* the adapter when it creates the virtual pad - which can be long after this
// manager made its decision, because the AppKit adapter only loads for a guest session.
// The answer is the AKControllerRouteStateNotification above, posted synchronously while
// this notification is being delivered, so the adapter is never left guessing.
FOUNDATION_EXPORT NSNotificationName const AKControllerRouteQueryNotification;
// Posted *by* the guest-facing GameController façade when it loads, and again when asked.
// It is a safety interlock, not a nicety: without the façade the guest sees the physical pad
// and the virtual one at once, so every press would arrive twice. The manager does not ask
// for a virtual pad until it has heard this, and the page says why when it has not.
FOUNDATION_EXPORT NSNotificationName const AKControllerGuestFacadePresentNotification;
FOUNDATION_EXPORT NSNotificationName const AKControllerGuestFacadeQueryNotification;
FOUNDATION_EXPORT NSNotificationName const AKControllerRouteValueNotification;
FOUNDATION_EXPORT NSNotificationName const AKControllerRoutePositionNotification;
FOUNDATION_EXPORT NSNotificationName const AKControllerRouteReleaseNotification;
FOUNDATION_EXPORT NSString *const AKControllerRouteElementKey;
FOUNDATION_EXPORT NSString *const AKControllerRouteValueKey;
FOUNDATION_EXPORT NSString *const AKControllerRouteXKey;
FOUNDATION_EXPORT NSString *const AKControllerRouteYKey;
FOUNDATION_EXPORT NSString *const AKControllerRouteEnabledKey;

// Posted *by* the adapter, observed here. `connected` (BOOL), `controller` (the real
// GCController once connected, else absent), `error` (NSString when the connection
// failed). It is how the manager knows whether routing can be reported as running and
// which controller the guest may see.
FOUNDATION_EXPORT NSNotificationName const AKControllerVirtualPadDidChangeNotification;
FOUNDATION_EXPORT NSString *const AKControllerVirtualPadConnectedKey;
FOUNDATION_EXPORT NSString *const AKControllerVirtualPadControllerKey;
FOUNDATION_EXPORT NSString *const AKControllerVirtualPadErrorKey;

// --- The guest façade channel --------------------------------------------------------
//
// Observed by the GameController façade in the prepared tree (translation/GameController,
// which our overlay owns). The façade is loaded by the runtime when the guest first needs
// GameController, which can be after this manager began, so it asks once and is answered
// synchronously - NSNotificationCenter delivers on the posting thread.
FOUNDATION_EXPORT NSNotificationName const AKControllerGuestViewRequestNotification;
FOUNDATION_EXPORT NSNotificationName const AKControllerGuestViewDidChangeNotification;
FOUNDATION_EXPORT NSString *const AKControllerGuestViewControllersKey;  // NSArray of GCController
FOUNDATION_EXPORT NSString *const AKControllerGuestViewRoutingKey;      // @YES when routing

/// One controller model that is connected now, as the page lists it.
@interface AKControllerModel : NSObject
@property (nonatomic, copy, readonly) NSString *identity;
@property (nonatomic, copy, readonly) NSString *displayName;
/// How many pads of this model are connected. More than one is why the page says the
/// mapping is shared: GameController does not identify individual pads.
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, copy, readonly) NSArray<AKControllerBinding *> *bindings;
@property (nonatomic, readonly) BOOL customised;
@end

@interface AKControllerManager : NSObject

+ (instancetype)shared;

/// Start watching. Safe to call more than once. Reads the stored switch and applies it.
- (void)begin;

/// The user's choice, persisted to WolkaraForever's own defaults. Setting it starts or
/// stops routing; it never touches WoW's bindings, GamePadConfig_*.json or Config.wtf.
@property (nonatomic) BOOL enabled;

@property (nonatomic, readonly) AKControllerRoutingState state;
/// A technical sentence for the log. The page words the state itself, so this is not
/// user-facing text.
@property (nonatomic, copy, readonly) NSString *statusDetail;
/// The controllers that are hardware: not a snapshot this process made, and not the
/// hidden virtual pad. This is the only list anything else should enumerate a pad from;
/// GCController.controllers includes the virtual pad and would make "a pad is connected"
/// true with nothing in anyone's hands.
@property (nonatomic, readonly) NSArray<GCController *> *physicalControllers;
@property (nonatomic, readonly) BOOL physicalControllerConnected;
/// Whether this build's guest has a GameController façade that can hide a physical pad.
/// True when the adapter announced itself, or when the bundle carries it - the latter is
/// what lets the launcher say "starts with the game" instead of claiming the build cannot
/// do it, because the adapter only loads when a guest session needs it.
@property (nonatomic, readonly) BOOL guestFacadeAvailable;
/// Whether it has actually announced itself in this process. Only then can a virtual pad be
/// asked for, because until then there is nothing to ask.
@property (nonatomic, readonly) BOOL guestFacadePresent;

/// Every model connected now, sorted by display name. Empty when no pad is connected.
@property (nonatomic, readonly) NSArray<AKControllerModel *> *models;
/// Exactly what the guest is offered: the devices themselves while routing is off, and the one
/// virtual controller while it is on. This is the input to the GameController façade, and the
/// promise of the whole feature is in one sentence - with routing on, nothing in this list is
/// the hardware the manager is reading.
@property (nonatomic, readonly) NSArray<GCController *> *guestControllers;
/// Called on the routing thread, with the tick at which the handler was entered, every time a
/// routed value is actually sent. A test uses it to measure what this feature adds; production
/// leaves it nil and pays one nil check.
@property (nonatomic, copy, nullable) void (^routeLatencyObserver)(uint64_t enteredAt);
- (nullable AKControllerProfile *)profileForIdentity:(NSString *)identity;
- (void)resetProfileForIdentity:(NSString *)identity;
/// Re-apply a profile the page has just edited: the gestures routing asked for follow the
/// new table, and a stick that is already deflected is sent again rather than ignored
/// until it moves.
- (void)applyProfileChangeForIdentity:(NSString *)identity;

/// Learn a new source for one model: the user presses or moves the control they want to
/// reassign, and is then offered the virtual targets. The next button pressed or stick
/// moved *on that model* is captured; anything else is ignored, so a press on another pad
/// cannot rewrite this profile. Cancelled by -cancelLearning, by a pad going away, and by
/// the app going to the background.
///
/// The order is source-then-target on purpose: the user already knows which physical
/// control they can reach, and asking them to choose a virtual button before touching
/// anything makes the screen a menu of names instead of a press.
- (void)beginLearningForIdentity:(NSString *)identity;
- (void)cancelLearning;
@property (nonatomic, readonly) BOOL learning;
@property (nonatomic, copy, readonly, nullable) NSString *learningIdentity;
/// Called once with the captured source. The page then binds it to whichever virtual
/// target the user picks with -[AKControllerProfile bindSource:toTarget:].
@property (nonatomic, copy, nullable) void (^onLearned)(NSString *identity, NSString *source);

/// Every physical control change, normalized: what the inspector used to install
/// handlers for itself. `element` is a canonical id from InputElement.h, `device` is a
/// model identity, `source` is "controller", "keyboard", "mouse", "touchpad" or "system".
@property (nonatomic, copy, nullable) void (^onEvent)(NSString *element, double value, BOOL pressed,
                                                      NSString *device, NSString *deviceName, NSString *source);

/// Which device reported the event being delivered, for a consumer reading inside
/// -onEvent:.
@property (nonatomic, copy, readonly, nullable) NSString *currentDevice;
@property (nonatomic, copy, readonly, nullable) NSString *currentDeviceName;
@property (nonatomic, copy, readonly, nullable) NSString *currentSourceName;

// --- System gestures, released by reason --------------------------------------------
//
// The voice feature releases the gesture of a button the *user mapped for dictation*;
// routing releases the gesture of a button *this profile routes*. They are separate
// reasons on purpose: -restoreAllSystemGestures is what the input router calls whenever
// the voice mapping changes, and it must not silently undo routing's release. A gesture
// is given back only when no reason wants it any more.
- (BOOL)releaseSystemGestureForElement:(NSString *)element device:(nullable NSString *)device;
- (void)restoreSystemGestureForElement:(NSString *)element device:(nullable NSString *)device;
- (void)restoreAllSystemGestures;
@property (nonatomic, readonly) BOOL currentControllerDeclaresShare;

/// Lend every reserved button out while the user picks one, because the press that is
/// supposed to create the mapping is exactly the press iPadOS would keep.
- (void)beginReleasingForLearning;
- (void)endReleasingForLearning;

/// Identity, profile class and full element list of everything connected now.
- (void)logInventories;

// --- Fixture seams ------------------------------------------------------------------
//
// The state machine is the thing under test, so a fixture replaces discovery and the
// virtual pad's replies rather than needing hardware. Production uses these unchanged;
// they are also the exact entry points the GameController handlers call, which is why a
// test that drives them is testing the real pipeline and not a copy of it.

/// Where the manager looks for hardware. nil means GCController.controllers.
@property (nonatomic, copy, nullable) NSArray<GCController *> * _Nullable (^controllersProvider)(void);

/// Deliver one physical button event, as a pressedChangedHandler would.
- (void)reportElement:(NSString *)element value:(double)value pressed:(BOOL)pressed
               device:(NSString *)device deviceName:(NSString *)deviceName source:(NSString *)source;
/// Deliver one physical axis position under its stable id
/// ("controller.axis.left.thumbstick", "dpad.dpad"), as a valueChangedHandler would.
- (void)reportAxis:(NSString *)element position:(CGPoint)position
            device:(NSString *)device deviceName:(NSString *)deviceName;

- (NSArray<GCController *> *)connectedControllers;
/// Pretend the guest façade announced itself. A fixture uses this because the adapter is a
/// separate binary; production hears the real notification when it loads.
- (void)noteGuestFacadePresent;
- (void)noteVirtualPadConnected:(nullable GCController *)controller;
- (void)noteVirtualPadFailed:(NSString *)error;
- (void)noteVirtualPadDisconnected;

@end

NS_ASSUME_NONNULL_END
