#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN
// Radial analog mapping with a small dead zone and clamped magnitude.
CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size);
// Owns only our virtual device. Physical controllers and their handlers stay
// with GameController/the guest. No game events or memory are inspected.
// iPad touch's walk area in a view of `viewSize`: the outer third away from TouchPlay's hand (hand R, the
// left third; hand L, the right third), from 460 layout units down (the lower 55 %, one unit = height / 1024)
// and out of the 20 pt edge zone - never the middle of the screen (a device check, the pinch). TouchPlay's buttons inside it are carved out per point
// (-[AKTouchAreas claimsPoint:]). CGRectNull for a view with no size.
FOUNDATION_EXPORT CGRect AKTouchWalkArea(CGSize viewSize, BOOL leftHanded);
// Where the walk stick's faint rest ring is drawn: a square in `viewSize` coordinates, in the walk area, off
// every rectangle in `areaRects` (TouchPlay's buttons at this size) by 8 pt; 175 pt where that fits near the add-on's
// stick box (the lower part of the hand-away third), smaller where it does not. CGRectNull when no ring fits.
FOUNDATION_EXPORT CGRect AKTouchWalkRestRing(CGSize viewSize, BOOL leftHanded, NSArray<NSValue *> *areaRects);
// The host's camera pinch and the walk stick (a player, a device check: "pinch zoom in the middle grabs the walk stick"): two
// fingers are a pinch when the second comes within 0.15 s of the stick's thumb, or while the thumb has not walked past
// the dead zone; a walking thumb and a later finger are a walk and a look. The host's pinch delegate (patch 0084) asks:
// for every touch the pinch is offered, AKWalkStickPinchOffer - -1 not the stick's (the host's own rules decide), 1 the
// pinch may take it, 0 it may not (it also notes when a second finger came); and before the pinch begins,
// AKWalkStickPinchMayBegin - YES with no thumb on the stick, else only for the pinch rule, and then the stick lets go
// (every walk key up, nothing sent after) and leaves those fingers alone until they lift.
FOUNDATION_EXPORT NSInteger AKWalkStickPinchOffer(UIView *host, UITouch *touch);
FOUNDATION_EXPORT BOOL AKWalkStickPinchMayBegin(UIView *host);
@interface AKTouchGamepad : NSObject
- (instancetype)initWithHostView:(UIView *)host;
// iPad touch (only the walk stick; no virtual controller): no buttons - no buttons, shoulders, right stick, corner jump or virtual
// controller (the game's gamepad mode would take over its bars, cursor and targeting). Its layer is
// placed over `host` below `sibling` (the app's toolbar). It takes a touch only in iPad touch with
// TouchPlay's buttons loaded (the host's AKTouchAreas has a contract), in the walk area, off every button:
// the ring (175 pt, knob 70 pt) appears centred where the thumb lands, and the game's movement keys W, S,
// A and D are held through the host's key path while the stick points their way (eight directions, a 12% dead zone,
// 8 degrees of hysteresis). Auto-run locks only on purpose (when the add-on's edgeRun is on): the thumb
// slides up past the ring onto the lock above it and stays 0.25 s, then lifts; it runs on straight forward, the lock
// full and "Auto-run" above it. The edge never locks; sliding off the lock cancels. A new thumb in the walk area or a
// tap on the lock stops it. A window open in the world (three pulses) keeps the stick live in the stick box only:
// the rest ring's square and the lock target above it; elsewhere touches are plain; a cancel, a size
// change, new buttons, the app put away, the keyboard and leaving the world (two pulses) let go of every key. At rest
// a faint ring shows the stick's usual place (AKTouchWalkRestRing).
- (instancetype)initWalkStickWithHostView:(UIView *)host below:(nullable UIView *)sibling;
// The movement stick: the walk stick in iPad touch, the left stick otherwise. -1...1 each axis, up positive.
@property(nonatomic, readonly) CGPoint leftStickVector;
@property(nonatomic, readonly) BOOL leftStickVisible;
@property(nonatomic, readonly) BOOL autoRunning;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, readonly) BOOL visible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, copy, nullable) void (^visibilityChanged)(BOOL visible);
// iPad touch: lets go of the walk stick - every walk key up, the vector zero, the ring hidden, auto-run off. The stick
// does this on its own for a cancel, a resize, new buttons and the keyboard; this is the one call the app's
// release-everything makes. A no-op outside iPad touch.
- (void)releaseWalking;
- (void)refresh;
- (void)toggleSettings;
// Re-read the saved layout: the launcher and the settings panel both write it, and the
// arrangement, the zones and the elements have to be what the dictionary now says.
- (void)reloadLayout;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
