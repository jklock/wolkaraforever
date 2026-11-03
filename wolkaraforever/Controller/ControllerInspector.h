// WolkaraForever layer: what a controller reports to us, and every change to it.
//
// Reading only. It reports every change the pads, keyboards and pointing devices make,
// names everything it finds, and logs it. It never consumes an input, and it never changes
// a pad's behaviour on its own: a reserved system gesture is released only when the user
// has mapped that exact element for dictation, through -releaseSystemGestureForElement:
// device:, which the input router calls. Before 2026-10-16 it disabled Share's gesture at
// startup for every pad that declared one, which changed how the controller behaved before
// the user had chosen anything - see development/STABILITY_AUDIT_2026-10-16.md.
//
// As of the Controller Manager it no longer installs handlers. AKControllerManager owns
// discovery and every GameController handler, because routing a physical pad through a
// virtual one needs exactly one owner of "which control is down". This file subscribes to
// that stream and keeps doing what it always did with it: name, log, and hand the event to
// the voice router through -onInput. The gesture methods below are forwarded to the same
// owner, tagged by reason, so a voice mapping and a routing profile cannot undo each
// other's release.
//
// Output goes to the platform's own log channel and to Documents/wolkaraforever.log.

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

// The model identity a mapping is remembered against. Declared and implemented once, so
// the inspector and the manager cannot disagree about what a pad is called.
#import "ControllerIdentity.h"

NS_ASSUME_NONNULL_BEGIN

@interface AKControllerInspector : NSObject

+ (instancetype)shared;

// Start watching: the pads connected now, and any that connect later. Also the
// keyboards and mice the system reports. Safe to call more than once.
- (void)begin;

// The identical stream the log carries, for a caller that wants to act on it.
// `element` is a canonical id from InputElement.h ("controller.button.share",
// "system.screenshot"); `pressed` distinguishes an edge from a value change.
@property (nonatomic, copy, nullable) void (^onInput)(NSString *element, double value, BOOL pressed);

// Log the identity and full element list of everything connected right now.
// This is the call that answers "what does this pad actually have?".
- (void)logInventories;

// Show the same events in a small panel over the game. Off unless asked for.
- (void)showPanel:(BOOL)visible;

// Which device reported the event currently being delivered, and what kind of source
// it was. Read from inside the `onInput` block: it is set for the duration of the
// call, so a trigger can be remembered per controller. `currentDevice` is the
// identity; `currentDeviceName` is what to show a person.
@property (nonatomic, copy, readonly, nullable) NSString *currentDevice;
@property (nonatomic, copy, readonly, nullable) NSString *currentDeviceName;
@property (nonatomic, copy, readonly, nullable) NSString *currentSourceName;

// Whether a connected controller declares the Share element that iPadOS reserves.
@property (nonatomic, readonly) BOOL currentControllerDeclaresShare;

// Release the system's claim on one element of one controller, so its press reaches
// the app. Only ever called because the user mapped that element; the identity is
// remembered so the exact gesture can be given back.
- (BOOL)releaseSystemGestureForElement:(NSString *)element device:(nullable NSString *)device;
// Give it back, and forget that it was released.
- (void)restoreSystemGestureForElement:(NSString *)element device:(nullable NSString *)device;
// Give everything back: voice switched off, a mapping removed, or a pad gone.
- (void)restoreAllSystemGestures;

// While the user is choosing a button, the gestures the system would otherwise keep are
// released too - every mappable button on every connected pad.
//
// Without this, a button the system reserves (Menu, Options, Home) can never be learned: its
// press goes to iPadOS and the page that asks the user to press something shows nothing at
// all, which is exactly what a user reported on the device (2026-10-22) - "the other button I
// could use does not show up in the UI when pressed". The rule that a gesture is only released
// for an element the user has already mapped cannot be satisfied by the very press that is
// supposed to create that mapping.
//
// Everything released here is remembered separately and given back by
// -endReleasingForLearning, so a button the user did not choose is never left changed.
- (void)beginReleasingForLearning;
- (void)endReleasingForLearning;

@end

NS_ASSUME_NONNULL_END
