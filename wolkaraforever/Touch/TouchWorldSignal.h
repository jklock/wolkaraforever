#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// iPad touch, ruling A24: TouchPlay's buttons are drawn only in the world, but the game gives no "in the world"
/// signal. The add-on sends one through secure event input (patch 0058 announces each change):
///   - entering the world (login, /reload, TouchPlay switched On): one short pulse, on then off;
///   - leaving the world (logout, leaving, TouchPlay switched Off): two pulses, a short gap between;
///   - a window or panel open while still in the world (ruling A32): three pulses;
///   - the login screen's password box: secure input on for as long as the box has focus (seconds).
/// This reads them. An on that is followed by an off within AKTouchPulseMaxSeconds is a pulse; pulses that follow
/// one another within AKTouchPulseGroupSeconds are one group; a group of one is "entered the world", two is "left it",
/// three is "a window is open" (still in the world, ruling A32), four or more is read as two (the safe reading). Secure input on for longer than AKTouchPasswordSeconds is a real password box, so not the world (in the world,
/// more than AKTouchPasswordInWorldSeconds, ruling A27; a window open counts as in the world).
/// A game start is "not in the world" until the add-on says otherwise.
///
/// Time is the clock's; `tick` settles whatever the clock has run out (a timer calls it; tests move their clock
/// and call it). Nothing here touches a view: whoever owns it hears `changed`.
typedef NS_ENUM(NSInteger, AKTouchWorldState) {
    AKTouchWorldOut = 0,    // not in the world: a game start, the login and character screens, two pulses, a password box
    AKTouchWorldIn,         // in the world with nothing open: TouchPlay's buttons are live (one pulse)
    AKTouchWorldWindow,     // in the world with a window or panel open (three pulses, ruling A32): plain touches, but the
                            // walk stick stays live, auto-run included (ruling A34)
};
@interface AKTouchWorldSignal : NSObject
/// Where the player is now (default AKTouchWorldOut).
@property (nonatomic, readonly) AKTouchWorldState state;
/// Whether the player is in the world with nothing open now, so TouchPlay's buttons are live (state In).
@property (nonatomic, readonly) BOOL inWorld;
/// Called, on the thread that fed the signal, each time `state` changes.
@property (nonatomic, copy, nullable) void (^changed)(AKTouchWorldState state);
/// The clock (seconds). The default is the system uptime; tests give their own.
@property (nonatomic, copy, null_resettable) NSTimeInterval (^clock)(void);

/// The game turned secure event input on or off (AKSecureEventInputDidChangeNotification, on the main thread).
- (void)secureInputChanged:(BOOL)enabled;
/// Settles what the clock has run out: a long "on" (a password box) and a group of pulses with no more to come.
- (void)tick;
@end

/// An on that goes off within this many seconds is a pulse. The password field's debounce
/// (AKTouchPasswordDebounceSeconds) is the same number, so a pulse never reaches the password keyboard.
FOUNDATION_EXPORT const NSTimeInterval AKTouchPulseMaxSeconds;      // 0.35
/// Pulses this close (the next one's start after the last one's end) are one group.
FOUNDATION_EXPORT const NSTimeInterval AKTouchPulseGroupSeconds;    // 0.6
/// Secure input on for longer than this is a password box, not the add-on.
FOUNDATION_EXPORT const NSTimeInterval AKTouchPasswordSeconds;      // 0.5
/// ...but one that starts while the player is in the world (ruling A27) has to last longer than this: a loading screen
/// can stretch the add-on's entering pulse past 0.5 s, and that is neither a box nor the player leaving. Shorter than
/// a pulse is still a pulse; between the two it is ignored. The keyboard's wait (AKTouchPasswordInWorldDebounceSeconds)
/// is the same number.
FOUNDATION_EXPORT const NSTimeInterval AKTouchPasswordInWorldSeconds;   // 1.5

NS_ASSUME_NONNULL_END
