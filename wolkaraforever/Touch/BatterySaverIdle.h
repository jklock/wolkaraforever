// WolkaraForever: the idle coordinator behind Battery Saver's AFK option.
//
// One object, owned by the AppKit host, owns one black layer above the game surface and
// below the pointer. After the timeout the layer fades in and the session is held at a low
// fixed presentation rate; the next input wakes it and is deliberately consumed, so a
// thumb that brushed the screen does not also move the camera.
//
// What it deliberately is not:
//   - It does not hook -[UIApplication sendEvent:]. The host view already receives direct
//     touches, presses, pointer moves and clicks, and that is where these events are read.
//   - It does not change screen brightness, idleTimerDisabled, session connectivity, game
//     memory or game settings. The dim is a view; nothing outside this process is touched.
//   - It never dims while an input is held, while the touch controls' own configuration UI
//     is open, or while the app is not frontmost.
//
// The clock is injectable. A fixture drives -tickAt: with made-up times instead of waiting
// ten real minutes, which is the only way a timeout can be tested rather than described.

#import <UIKit/UIKit.h>
#import "BatterySaverPolicy.h"

NS_ASSUME_NONNULL_BEGIN

/// The black layer itself. It never takes input: a touch that lands on it belongs to the
/// game surface underneath, and the host decides whether it is delivered.
@interface AKBatterySaverDimView : UIView
@end

@interface AKBatterySaverIdle : NSObject

/// `hostView` is the game surface. The dim layer becomes its topmost subview below the
/// pointer; the coordinator keeps a weak reference to it.
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithHostView:(UIView *)hostView NS_DESIGNATED_INITIALIZER;

/// The timeout this guest was started with, in minutes: 0 (off), 2, 5 or 10. The launcher's
/// snapshot decides the value; changing it here changes this session.
@property (nonatomic) NSInteger timeoutMinutes;

/// YES while the layer is dimming the session.
@property (nonatomic, readonly, getter=isDimmed) BOOL dimmed;

/// Monotonic seconds. CACurrentMediaTime by default; a fixture sets its own.
@property (nonatomic, copy) NSTimeInterval (^clock)(void);

/// Whether the touch controls' configuration UI is open. Polled, because it is a state the
/// touch controls own: opening it can neither dim nor be interrupted by a timeout.
@property (nonatomic, copy, nullable) BOOL (^configurationActive)(void);

/// An input arrived. Resets the countdown, and returns YES when the session was dimmed -
/// in which case that input only woke it, and the caller must not deliver it to the game.
/// Main thread.
- (BOOL)input:(NSString *)source;

/// Something is being held: a touch, a key, a mouse button, a controller contact. While
/// anything is held the session cannot dim, and the countdown restarts when it is released.
/// Main thread.
- (void)setHeld:(BOOL)held reason:(NSString *)reason;

/// The app is no longer frontmost. Wake, and stop counting: a game in the background is not
/// a game somebody dimmed.
- (void)suspend;
/// The app is frontmost again. Start counting from now.
- (void)resume;

/// What this session is capped at right now: the idle state is one of the policy's inputs.
- (AKBatterySaverFramePolicy)framePolicy;

/// Rename the dim layer to the surface's current bounds. Called from the host's layout.
- (void)layoutDimView;

/// The timer's one step, with the time named so a fixture can supply it.
- (void)tickAt:(NSTimeInterval)now;

@end

NS_ASSUME_NONNULL_END
