#import <Foundation/Foundation.h>
#import "TouchTrackpad.h"

// A controller's touchpad as the pointer: the in-game half of "Controller touchpad as mouse".
//
// The app relays the touchpad (see launcher/Input/ControllerTouchpad.h) and this turns it into
// the same pointer calls a finger on the screen makes. Motion goes through the platform's own
// trackpad state machine (`TouchTrackpad.c`, unchanged), so one finger moves and two fingers
// scroll exactly as they do on the glass. Two things differ, both because this surface is a
// controller's and not the screen's:
//
//   * A tap or a hold does not click. A thumb brushes a controller's touchpad constantly, and the
//     pad has a real click under it. Every press and release the state machine would have made
//     is dropped here.
//   * The physical click is the button: left with one finger down, right with two. It is held for
//     as long as the pad is pressed, so pressing and sliding drags.
//
// It logs nothing and reads nothing about the game.

NS_ASSUME_NONNULL_BEGIN

typedef struct AKControllerPointer {
    AKTrackpad pad;
    // The click is down, and which button it pressed.
    bool clicked;
    unsigned button;
} AKControllerPointer;

/// One delivery from the relay: how many fingers are down and where their centre is, in points.
void AKControllerPointerUpdate(AKControllerPointer *pointer, unsigned fingers, double x, double y,
                               double time, AKTrackpadEmit emit, void *_Nullable context);

/// The touchpad itself was pressed or released. A repeated edge is ignored, so a press is
/// released exactly once.
void AKControllerPointerClick(AKControllerPointer *pointer, bool pressed, AKTrackpadEmit emit,
                              void *_Nullable context);

/// Release whatever is held and forget the gesture: the controller went away, the switch was
/// turned off, or the app is leaving the foreground. `emit` may be NULL to forget silently.
void AKControllerPointerReset(AKControllerPointer *pointer, AKTrackpadEmit _Nullable emit,
                              void *_Nullable context);

NS_ASSUME_NONNULL_END
