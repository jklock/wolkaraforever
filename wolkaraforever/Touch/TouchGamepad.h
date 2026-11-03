#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN
// Radial analog mapping with a small dead zone and clamped magnitude.
CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size);
// Owns only our virtual device. Physical controllers and their handlers stay
// with GameController/the guest. No game events or memory are inspected.
@interface AKTouchGamepad : NSObject
- (instancetype)initWithHostView:(UIView *)host;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, readonly) BOOL visible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, copy, nullable) void (^visibilityChanged)(BOOL visible);
- (void)refresh;
- (void)toggleSettings;
- (void)invalidate;

// --- Physical routing: the second producer of the same virtual device ---------------
//
// The Controller Manager in the launcher routes a physical pad through this controller,
// which is the only hidden GCVirtualController the app has. Two producers therefore drive
// one device, and they must not fight over it: while routing is on the physical producer
// owns every element and the overlay's touches are ignored (the overlay is reset as
// routing starts and stops), so neither can leave a button or a stick held. The manager
// decides *when* routing runs; this side obeys and reports, because the manager lives in
// the launcher and this file in the AppKit adapter dylib.
//
// `target` is a WolkaraForever virtual id ("virtual.button.a", "virtual.stick.left",
// "virtual.dpad"), not a GCInput* constant: a stored profile must not depend on the
// framework's spelling. -elementForTarget: is the one place the two are translated.
- (void)setPhysicalRoutingEnabled:(BOOL)enabled;
- (void)setPhysicalValue:(double)value forTarget:(NSString *)target;
- (void)setPhysicalPosition:(CGPoint)position forTarget:(NSString *)target;
- (void)releasePhysicalInputs;
/// The connected virtual controller, nil until -refresh has connected one. This is what
/// the guest façade may show the game while routing is on.
@property(nonatomic, readonly, nullable) GCController *virtualController;
@end
NS_ASSUME_NONNULL_END
