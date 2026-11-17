#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The AFK saver: after the launcher row's minutes with no touch, key, pointer or controller input during a game
/// (Off, 2, 5 or 10; 5 by default, BatterySettings.h), the screen is dimmed - a 70% black layer over the game in a
/// window of its own, so the iPad's brightness is never changed - and the game's frames drop to 10 a second (the
/// Metal adapter's frame limit). The next touch wakes it at once, and only wakes it: that touch (every finger of it,
/// to its lift) and a waking key or pointer move never reach the game or the app's controls. The session stays alive
/// throughout: the screen still never locks during a game (idleTimerDisabled is left exactly as the app sets it), the
/// game keeps its connection, only slower.
///
/// It never dims while a finger or a key is down (a held key released while dimmed would be lost), nor while the app
/// is away; coming back to the app wakes it. A controller cannot be held back from the game, so a controller wakes it
/// and its input goes through.
@interface AKIdleSaver : NSObject
/// The game's saver: made and armed when the AppKit adapter loads (the guest's start), reading the launcher's row.
+ (nullable instancetype)shared;
/// Minutes with no input before it dims; 0 is off. Read from the launcher's row at init.
@property (nonatomic) NSInteger minutes;
/// Whether the app is active. Away, nothing dims; coming back is input (and wakes a dimmed screen).
@property (nonatomic) BOOL appActive;
@property (nonatomic, readonly) BOOL dimmed;
/// The dimming layer (in its own window when the app has a scene). Never takes a touch: the event hook does.
@property (nonatomic, readonly) UIView *dimView;
/// The clock (seconds). The default is the system uptime; tests give their own.
@property (nonatomic, copy, null_resettable) NSTimeInterval (^clock)(void);
/// A number that changes when any controller, hardware keyboard or mouse reports input (GameController's
/// lastEventTimestamp). The default reads GameController; tests give their own.
@property (nonatomic, copy, null_resettable) double (^controllerStamp)(void);
/// Where the 10 frames a second goes: YES dimmed, NO awake. The default calls the Metal adapter by name.
@property (nonatomic, copy, null_resettable) void (^capSender)(BOOL idle);

/// Starts the count from now.
- (void)begin;
/// One event the application is about to dispatch. YES: it is the waking input (or part of it) and must not be
/// dispatched; NO: dispatch it as usual (and it counts as input).
- (BOOL)handleEvent:(UIEvent *)event;
/// Settles the clock's now: dims when the minutes have passed, wakes on a controller. A timer calls it; tests call it
/// after moving their clock.
- (void)tick;
@end

NS_ASSUME_NONNULL_END
