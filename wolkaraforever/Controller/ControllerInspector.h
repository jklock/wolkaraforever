// WolkaraForever layer: what a controller reports to us, and every change to it.
//
// Reading only. It attaches observers to the pads, keyboards and pointing devices the
// system reports, names everything it finds, and logs every change as it happens. It
// never consumes an input, and it never changes a pad's behaviour on its own: a
// reserved system gesture is released only when the user has mapped that exact
// element, through -releaseSystemGestureForElement:device:, which the input router
// calls. Before 2026-10-16 it disabled Share's gesture at startup for every pad that
// declared one, which changed how the controller behaved before the user had chosen
// anything - see development/STABILITY_AUDIT_2026-10-16.md.
//
// Output goes to the platform's own log channel and to Documents/wolkaraforever.log.

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import "../Input/InputInterest.h"

NS_ASSUME_NONNULL_BEGIN

// Posted when the stored diagnostics preference changes. The router listens, because the
// interest snapshot is what actually turns the stream on and off, and the two classes must not
// have to import each other to say so.
FOUNDATION_EXPORT NSNotificationName const AKInputDiagnosticsDidChangeNotification;

/// A controller's *model* identity: vendor and product category. This is what a mapping is
/// remembered against, and it is deliberately not claimed to be per-device. GameController
/// exposes no serial number, so two identical pads are indistinguishable to this app and
/// share one mapping; the log says so when that happens, and `development/technical/INPUT_TRIGGERS.md` says
/// so to the reader. It is never the display name (a mapping key should not be), and never
/// the player index, which moves as pads come and go.
FOUNDATION_EXPORT NSString *AKControllerIdentity(GCController *pad);

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

#pragma mark - What is worth reporting at all

// The router owns this and replaces it whenever the user's choices change. Reading it allocates
// nothing, so a GameController callback can ask it before it has done any work: no event
// object, no main-queue block, no log write for an element nobody is interested in.
//
// Default: AKInputInterestModeNone. Until something asks for input, everything is ignored.
@property (atomic, copy, nullable) AKInputInterest *interest;

// Diagnostics, and the only thing that may turn an event into a log line.
//
// Off in ordinary play, and stored, so a relaunch does not silently switch it back on. The
// 2026-11-04 device log held 25,316 log lines for one five-minute run with voice off, because
// every inspected event was written - twice - whether or not anyone wanted it. With this off, a
// mapped trigger still works; nothing else is recorded.
@property (atomic) BOOL diagnosticsEnabled;

// Whether the panel is on screen. The panel's history is only maintained while it is: without
// this the inspector scheduled a main-queue block for a panel that was not there, once per
// event.
@property (atomic) BOOL panelVisible;

// Aggregation-only measurements. These are not logs and they are not cleared by reading them.
//   callbackTiming - time spent inside the GameController callback, before it dispatches.
//   handoffTiming  - from the callback starting to the main-queue block beginning.
@property (nonatomic, readonly) AKTimingSamples *callbackTiming;
@property (nonatomic, readonly) AKTimingSamples *handoffTiming;
@property (nonatomic, readonly) NSUInteger admittedEvents;
@property (nonatomic, readonly) NSUInteger ignoredEvents;
@property (nonatomic, readonly) NSUInteger coalescedEvents;
- (void)resetDiagnostics;

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
