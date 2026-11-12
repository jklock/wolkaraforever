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
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)save;
- (void)reset;
@end
