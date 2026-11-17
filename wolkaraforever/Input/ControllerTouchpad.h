// WolkaraForever: a controller's touchpad as the game's pointer, when the user asks for it.
//
// A DualSense (or DualShock 4) reports its touchpad as two touch points and one click. Until this
// existed the touches only ever reached the diagnostics panel - the interest gate admits touchpad
// movement in diagnostic mode and nowhere else - and the click was one more learnable button.
//
// With "Controller touchpad as mouse" switched on (it is off unless the user turns it on), the
// inspector hands every touchpad touch and the touchpad click to this relay *before* the interest
// gate, and the relay hands them to the in-game touch layer, which runs them through the
// platform's own trackpad state machine: one finger moves the pointer, two fingers scroll, and the
// physical click is the left button (the right button with two fingers down). A tap does not
// click: a controller's touchpad is brushed by a thumb far too often for that.
//
// The two halves live in different libraries - this one in the app, the pointer in the AppKit
// adapter - and talk the way the rest of the app does across that line: one notification, named
// by a string both sides spell out. Moves are coalesced to at most one delivery per main-queue
// turn, keeping only the latest position, so a 120 Hz touchpad is bounded work.
//
// Nothing here reads, writes or automates the game: it is the user's own finger on the user's own
// controller, delivered the same way a finger on the screen already is.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// The stored switch, off unless the user turned it on.
FOUNDATION_EXPORT NSString *const AKControllerTouchpadPointerDefaultsKey;   // "WolkaraForeverControllerTouchpadPointer"
// The stored speed, an AKControllerTouchpadSpeed.
FOUNDATION_EXPORT NSString *const AKControllerTouchpadSpeedDefaultsKey;     // "WolkaraForeverControllerTouchpadSpeed"

// App -> adapter. Posted on the main queue only. userInfo carries exactly one of:
//   "fingers" (unsigned), "x", "y" (points, y down, relative to an arbitrary origin), "time"
//   "click"   (BOOL: the touchpad was pressed or released)
//   "reset"   (YES: the controller went away or the switch was turned off; release everything)
FOUNDATION_EXPORT NSNotificationName const AKControllerTouchpadPointerNotification; // "AKControllerTouchpadPointer"
// App -> AppKit host. Posted only when a controller touch contact or click starts or ends. The
// host ignores the controller's duplicate GCMouse stream while this is YES, but continues to
// accept a separate physical mouse or trackpad as soon as the controller contact ends.
FOUNDATION_EXPORT NSNotificationName const AKControllerTouchpadActivityNotification;
FOUNDATION_EXPORT NSString *const AKControllerTouchpadActiveKey; // "active"
FOUNDATION_EXPORT NSString *const AKControllerTouchpadFingersKey;  // "fingers"
FOUNDATION_EXPORT NSString *const AKControllerTouchpadXKey;        // "x"
FOUNDATION_EXPORT NSString *const AKControllerTouchpadYKey;        // "y"
FOUNDATION_EXPORT NSString *const AKControllerTouchpadTimeKey;     // "time"
FOUNDATION_EXPORT NSString *const AKControllerTouchpadClickKey;    // "click"
FOUNDATION_EXPORT NSString *const AKControllerTouchpadResetKey;    // "reset"

typedef NS_ENUM(NSInteger, AKControllerTouchpadSpeed) {
    AKControllerTouchpadSpeedSlow = 0,
    AKControllerTouchpadSpeedNormal = 1,
    AKControllerTouchpadSpeedFast = 2,
};

// Game Controller reports a touch as -1...1 on each axis with y up. The pointer wants points with
// y down. A DualSense touchpad is a little over twice as wide as it is tall, and both of its axes
// are normalised to the same range, so the vertical axis is halved: the same finger movement is
// the same pointer movement in either direction.
FOUNDATION_EXPORT CGPoint AKControllerTouchpadPoint(double x, double y, AKControllerTouchpadSpeed speed);

@interface AKControllerTouchpadRelay : NSObject

+ (instancetype)shared;

// Stored. Turning it off releases anything the pointer is holding.
@property (atomic) BOOL enabled;
@property (atomic) AKControllerTouchpadSpeed speed;

// Any thread: what the touchpad reported. `index` is which touch point (0 or 1); anything else is
// ignored. Cheap enough to call from a GameController handler: a lock, four stores and, at most
// once per main-queue turn, one dispatch.
- (void)touch:(NSUInteger)index down:(BOOL)down x:(double)x y:(double)y;
// Any thread: the touchpad itself was pressed or released. Never coalesced, and delivered after
// any movement that came before it.
- (void)click:(BOOL)pressed;
// Any thread: a controller went away. Lifts every finger and releases the click.
- (void)reset;

// For the fixture: deliveries posted, and touch reports folded into a delivery already pending.
@property (atomic, readonly) NSUInteger deliveredCount;
@property (atomic, readonly) NSUInteger coalescedCount;
- (void)resetCounters;

@end

NS_ASSUME_NONNULL_END
