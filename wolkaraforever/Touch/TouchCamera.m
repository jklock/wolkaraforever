#import "TouchCamera.h"
#import "TouchControllerLog.h"
#include <math.h>
#include <string.h>

// The platform's own tap/hold threshold: a gesture that has travelled further than this is
// motion, and every tap-like decision in TouchTrackpad.c is taken against it. The log reports
// the crossing so a device run can read the same line the pad drew.
static const double AKTouchCameraTapTravel = 8;
// A jump is not motion. A quarter of the short side is far beyond any thumb: at 60 frames a
// second it is thousands of points per second on the shortest axis of every device this runs
// on, and never less than 96 points in one frame.
static const double AKTouchCameraJumpLimitFloor = 96;
static const double AKTouchCameraJumpLimitFraction = 0.25;

typedef struct {
    AKTrackpadEmit _Nullable emit;
    void *_Nullable context;
} AKTouchCameraSink;

static NSString *AKTouchCameraButtonName(unsigned button) {
    switch (button) {
        case 0: return @"left";
        case 1: return @"right";
        case 2: return @"middle";
    }
    return @"pointer";
}

// Every event a gesture produces goes through here, which is the one place a press and its
// release are counted. The action itself is unchanged and reached the host exactly as before.
static void AKTouchCameraSinkEmit(void *context, AKTrackpadAction action, double x, double y,
                                  unsigned button) {
    AKTouchCameraSink *sink = context;
    if (sink->emit) sink->emit(sink->context, action, x, y, button);
    if (action == AKTrackpadDown)
        AKTouchControllerLog(AKTouchControllerEventPress, @"sent",
                             @{@"control": @"pointer", @"element": AKTouchCameraButtonName(button)});
    else if (action == AKTrackpadUp)
        AKTouchControllerLog(AKTouchControllerEventRelease, @"sent",
                             @{@"control": @"pointer", @"element": AKTouchCameraButtonName(button)});
}

static void AKTouchCameraDeliver(AKTrackpadEmit _Nullable emit, void *_Nullable context,
                                 AKTrackpadAction action, unsigned button) {
    if (!emit) return;
    AKTouchCameraSink sink = { emit, context };
    AKTouchCameraSinkEmit(&sink, action, 0, 0, button);
}

// Forget the gesture completely. The caller has already released whatever it held.
static void AKTouchCameraForget(AKTouchCameraGesture *camera) {
    memset(&camera->pad, 0, sizeof camera->pad);
    camera->handedOff = NO;
    camera->generation++;
}

void AKTouchCameraReset(AKTouchCameraGesture *camera, NSString *reason,
                        AKTrackpadEmit emit, void *context) {
    if (!camera) return;
    BOOL playerCancel = [reason isEqualToString:@"cancelled"];
    BOOL wasActive = camera->pad.fingers || camera->pad.dragging || camera->pad.blocked ||
        camera->pad.lifting;
    camera->generation++;
    camera->handedOff = NO;
    if (playerCancel) {
        // The platform's own rule, kept exactly: `AKTrackpadCancel` releases a held button
        // once and then *suppresses the rest of this gesture until every finger is lifted*, so
        // a cancelled touch cannot turn into a drag. Clearing the pad outright here would hand
        // those leftover fingers to the camera as motion - the jump `blocked` exists to
        // prevent - which is a change to behaviour this build has no reason to make.
        AKTouchCameraSink sink = { emit, context };
        AKTrackpadCancel(&camera->pad, emit ? AKTouchCameraSinkEmit : NULL, emit ? &sink : NULL);
        if (!camera->pad.fingers) memset(&camera->pad, 0, sizeof camera->pad);
    } else {
        // Every other exit is the app taking the gesture away - the background, a panel, a
        // rotation, a controller arriving, teardown. Nothing is touching the screen for it, so
        // it is released once and cleared completely, which is what makes the next touch a
        // camera drag immediately.
        if (camera->pad.dragging) AKTouchCameraDeliver(emit, context, AKTrackpadUp, camera->pad.button);
        AKTouchCameraForget(camera);
    }
    if (!emit || !wasActive) return;
    // A cancellation the player or the system caused ("cancelled") and one the app caused are
    // different events on purpose: the first is the gesture's own exit, the second is the app
    // taking the gesture away.
    AKTouchControllerLog(playerCancel ? AKTouchControllerEventCancel : AKTouchControllerEventLifecycle,
                         playerCancel ? @"cancelled" : @"cleanup", @{@"reason": reason ?: @"unknown"});
}

BOOL AKTouchCameraIsActive(const AKTouchCameraGesture *camera) {
    return camera && (camera->pad.fingers || camera->pad.dragging || camera->pad.lifting ||
                      camera->pad.blocked);
}

void AKTouchCameraUpdate(AKTouchCameraGesture *camera, unsigned fingers, double x, double y,
                         double time, CGSize surface, AKTrackpadEmit emit, void *context) {
    if (!camera) return;
    camera->width = surface.width;
    camera->height = surface.height;
    // A centroid that jumped is a new gesture. Closing the old one before the update means the
    // delta the pad is about to see is zero, so nothing is dragged by the jump itself.
    if (fingers && camera->pad.fingers && isfinite(x) && isfinite(y)) {
        double jump = hypot(x - camera->pad.x, y - camera->pad.y);
        double shortSide = fmin(surface.width, surface.height);
        double limit = fmax(AKTouchCameraJumpLimitFloor, AKTouchCameraJumpLimitFraction * shortSide);
        if (isfinite(jump) && jump > limit) {
            // The button, if one was held, is released exactly once by the close before the
            // log line: a rebase is never a stuck press.
            if (camera->pad.dragging) AKTouchCameraDeliver(emit, context, AKTrackpadUp, camera->pad.button);
            AKTouchCameraForget(camera);
            AKTouchControllerLog(AKTouchControllerEventThreshold, @"rebased",
                                 @{@"control": @"camera", @"reason": @"centroid"});
        }
    }
    AKTouchCameraSink sink = { emit, context };
    AKTrackpadUpdate(&camera->pad, fingers, x, y, time, AKTouchCameraSinkEmit, &sink);
    if (!camera->handedOff && camera->pad.fingers > 0 && camera->pad.travelled > AKTouchCameraTapTravel) {
        camera->handedOff = YES;
        AKTouchControllerLog(AKTouchControllerEventThreshold, @"handoff", @{@"control": @"camera"});
    }
}

BOOL AKTouchCameraHold(AKTouchCameraGesture *camera, double time, AKTrackpadEmit emit, void *context) {
    if (!camera || camera->pad.dragging) return NO;
    AKTouchCameraSink sink = { emit, context };
    AKTrackpadHold(&camera->pad, time, AKTouchCameraSinkEmit, &sink);
    // The press itself was logged by the sink, once, with the button it holds.
    return camera->pad.dragging;
}
