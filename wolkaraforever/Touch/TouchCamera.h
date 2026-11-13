#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TouchTrackpad.h"

// The direct touch camera, as one gesture that has a beginning, an end, and a rule for being
// taken away.
//
// The platform's trackpad state machine (`TouchTrackpad.c`, upstream's, unchanged) turns finger
// centroids into a pointer, a drag or a scroll. What it cannot know is anything about this
// app's lifecycle, and that is what used to go wrong: a drag whose touch vanished - the panel
// opening over it, the app going away, a rotation, a physical controller arriving - stayed
// half-open, and the camera answered nothing until a whole new finger sequence had been lifted.
//
// This wraps that state machine and adds exactly three things, none of which change what a
// finger on the screen means:
//
//   1. A centroid jump larger than a quarter of the short side (never less than 96 pt) is not
//      motion: it is a new gesture. The old one is closed - its button released, once - and the
//      camera continues from the new point instead of being dragged across the screen by a
//      number that no thumb produced. A recentered pointer therefore cannot end a drag.
//   2. Crossing the tap threshold is said out loud, once per gesture, so a device log shows
//      whether a touch became motion (that is the line a double tap is refused by).
//   3. Every lifecycle exit has one way out: `AKTouchCameraReset` releases what the gesture was
//      holding and clears it completely, so the next touch is a camera drag immediately.
//
// It logs nothing else: no coordinates, no trail, no pointer position, and nothing about the
// game.

NS_ASSUME_NONNULL_BEGIN

typedef struct AKTouchCameraGesture {
    AKTrackpad pad;
    // The surface the centroid was measured on, in points. Only used for the jump limit.
    double width, height;
    // The tap threshold has been reported for this gesture.
    BOOL handedOff;
    // How many times the gesture has been started, so a late timer can be told apart from the
    // gesture it was started for.
    unsigned generation;
} AKTouchCameraGesture;

/// Close the gesture: what it held is released exactly once, and nothing of it is left behind.
/// `reason` is a bounded word for the log - "background", "resign", "resize", "teardown",
/// "settings", "controller", "keyboard", "cancelled". `emit` may be NULL when there is nothing
/// left to tell (teardown), and then nothing is emitted or logged.
void AKTouchCameraReset(AKTouchCameraGesture *camera, NSString *reason,
                        AKTrackpadEmit _Nullable emit, void *_Nullable context);

/// One frame of direct touch: the finger count and centroid UIKit reported. `surface` is the
/// size the centroid was measured in. Calls the platform state machine, and emits through
/// `emit` exactly as it does.
void AKTouchCameraUpdate(AKTouchCameraGesture *camera, unsigned fingers, double x, double y,
                         double time, CGSize surface, AKTrackpadEmit emit, void *context);

/// The overlay's hold timer. Answers YES when this call is what started a drag (a press went
/// out), so the caller can log or react to it.
BOOL AKTouchCameraHold(AKTouchCameraGesture *camera, double time, AKTrackpadEmit emit, void *context);

/// Whether a gesture is in progress (any finger down, held or not).
BOOL AKTouchCameraIsActive(const AKTouchCameraGesture *camera);

NS_ASSUME_NONNULL_END
