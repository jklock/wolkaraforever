#import <UIKit/UIKit.h>

// Posted after saving; the object is the defaults store that changed.
FOUNDATION_EXPORT NSNotificationName const AKGamepadLayoutDidChangeNotification;

// Preferences contain only UI appearance/feedback; never controller or game state.
@interface AKGamepadLayout : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic) CGFloat opacity;
@property(nonatomic) CGFloat rearScale;
@property(nonatomic) CGFloat frontScale;
@property(nonatomic) BOOL hapticsEnabled;
// Swap the visual shoulder slots only; controller element identities are unchanged.
@property(nonatomic) BOOL swapShoulders;
// Whether the optional performance HUD is shown. Off by default; the in-game
// settings page and the launcher's Performance & UI row both write it, so the
// preference has one home and one meaning.
@property(nonatomic) BOOL performanceOverlayEnabled;
// Only the two sticks are shown (movement and camera); the buttons stay hidden. On by
// default: on a phone the buttons cover the game, and the game's own UI does the rest.
@property(nonatomic) BOOL sticksOnly;
// The sticks are not drawn where they sit: they fade almost away and come back under the
// thumb that presses their half of the screen, and the corner beyond the camera stick jumps.
// Off by default and a mobile-interface arrangement only, so Standard and every existing
// mobile layout keep the fixed rings they have.
@property(nonatomic) BOOL floatingSticks;
// Areas the app leaves alone while the floating arrangement is on: normalised rectangles in
// the overlay's own space, where a touch goes to the game - or to an add-on's own buttons -
// instead of to a stick. Empty by default, and saved with the rest of the layout: nothing is
// reserved for anything unless the person using it asks, which is what keeps an add-on from
// defining this interface. Each is @{@"x",@"y",@"w",@"h"} in 0...1.
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSNumber *> *> *keepFree;
// Which gamepad element each on-screen control sends, as data: slot (its element name, e.g.
// "A" or "LB") -> element. Empty means every control sends its own name, which is what every
// release has done. Two controls may not send the same element.
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *elements;
- (NSString *)elementForSlot:(NSString *)slot;
- (BOOL)setElement:(NSString *)element forSlot:(NSString *)slot;
- (void)clearElementMapping;
- (void)addKeepFreeAreaWithX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w height:(CGFloat)h;
- (void)clearKeepFreeAreas;
// A whole arrangement as data: every value above, saved under a name the user chooses, and
// the built-in starting points. This is what makes a setup keepable and shareable without the
// app knowing which add-on (if any) it is for.
- (NSDictionary<NSString *, id> *)arrangement;
- (void)applyArrangement:(NSDictionary<NSString *, id> *)arrangement;
+ (NSArray<NSString *> *)templateNames;
- (void)applyTemplateNamed:(NSString *)name;
- (NSArray<NSString *> *)savedProfileNames;
- (BOOL)saveAsProfileNamed:(NSString *)name;
- (BOOL)applyProfileNamed:(NSString *)name;
- (BOOL)deleteProfileNamed:(NSString *)name;
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)save;
- (void)reset;
@end
