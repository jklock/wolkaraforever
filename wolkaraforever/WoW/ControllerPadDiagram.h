// WolkaraForever: the controller, drawn, so a mapping is something you point at.
//
// A list of forty rows is not a mapping. This draws the pad the person is holding - sticks, D-pad,
// face buttons, shoulders, triggers, menu, view, home - and puts each control's target on the
// control itself. Touching a control chooses what it drives. Anything the drawing does not have is
// added from the box beneath it, and appears as a chip.
//
// The drawing is a picture of the *standard* pad, not of a particular model: what a person can
// reach is the same on an Xbox pad and a DualSense, and the two controls that differ are in the box
// rather than in a picture that would be wrong for someone else's controller.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AKControllerBinding;

@interface TKWoWControllerPadDiagram : UIView

/// The rows to draw, keyed by source element ("controller.button.a"). A source the drawing has no
/// place for is simply not drawn; the page lists it beneath.
@property (nonatomic, copy) NSDictionary<NSString *, AKControllerBinding *> *bindings;
/// Sources a Tolkara feature is using. Drawn in the app's gold, because it is not the game's.
@property (nonatomic, copy) NSSet<NSString *> *withheld;
/// YES while waiting for the user to press a control: the drawing says so and stops accepting taps.
@property (nonatomic) BOOL waiting;

/// Called with the source element when a control in the drawing is tapped.
@property (nonatomic, copy, nullable) void (^onSourceTapped)(NSString *source);

/// Every source this drawing can show, so the page knows which rows go in the box instead.
+ (NSArray<NSString *> *)drawnSources;

@end

NS_ASSUME_NONNULL_END
