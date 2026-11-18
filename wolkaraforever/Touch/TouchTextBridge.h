#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What the keyboard is for (iPad touch, rule 9).
typedef NS_ENUM(NSInteger, AKTextKind) {
    AKTextKindNone = 0,
    /// The game's chat: the controls' own composer (the draft editor), sent as F12 + the line + Return.
    AKTextKindChat,
    /// An account name box: a plain field that iPadOS knows is a user name.
    AKTextKindUsername,
    /// The game's password box: a secure field the player types the password into by hand. Ruling A41 (18 Nov 2026):
    /// iPadOS offers no saved password for it (no Passwords app suggestion, no Face ID).
    AKTextKindPassword,
};

/// Where the bridge's text goes: the host's own text path (the same two calls the controls' delegate
/// has), which turns each character into the game's key down and up.
@protocol AKTouchTextSink <NSObject>
- (void)touchInsertText:(NSString *)text;
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters;
@end

/// Whether the bridge belongs in this interface: iPad touch only. Every other mode keeps 1.0.10's keyboard.
FOUNDATION_EXPORT BOOL AKTouchTextBridgeWanted(void);

/// Where the game's login password box sits, as fractions of the game view (mockup 28: centre x 1105/2212,
/// y 1030/1658): the field is put over it, so iPadOS sees a real field where the player sees the box.
FOUNDATION_EXPORT const CGPoint AKTouchPasswordBoxCentre;      // {0.5, 0.621}
/// The field's size, in points (ruling A23).
FOUNDATION_EXPORT const CGSize AKTouchPasswordFieldSize;       // {320, 44}
/// How far the game slides up while the password keyboard is up, as a fraction of the view's height (mockups
/// 26, 29, 83: 230 of 1658), so the box stays above the keyboard.
FOUNDATION_EXPORT const CGFloat AKTouchPasswordSlideFraction;  // 0.139
/// After a whole password arrives, the game's "secure input on" is ignored this long (or until it goes off
/// while the app is active): coming back from Face ID's sheet turns it on again, and the box is already filled.
FOUNDATION_EXPORT const NSTimeInterval AKTouchFillQuietSeconds;  // 2
/// The game's "secure input on" opens the password field only if it is still on this long afterwards (ruling A24):
/// the add-on's short pulses, which tell the app the player is in the world, are never the password box, so they
/// never flash the password keyboard. The same number as the pulse limit (AKTouchPulseMaxSeconds).
FOUNDATION_EXPORT const NSTimeInterval AKTouchPasswordDebounceSeconds;  // 0.35
/// ...but while the player is in the world (`inWorld`) it has to stay on this long (ruling A27): a loading screen can
/// stretch the add-on's pulse past the debounce. The same number as the world signal's AKTouchPasswordInWorldSeconds.
FOUNDATION_EXPORT const NSTimeInterval AKTouchPasswordInWorldDebounceSeconds;  // 1.5

/// The keyboard for a game box that iPadOS cannot see (iPad touch only).
///
/// The game draws its own edit boxes; iPadOS only sees the app's views. For the password box the bridge
/// holds an invisible, untouchable `UITextField` over the game's box (`secureTextEntry`, `textContentType` one-time code, alpha 0) that
/// takes the keyboard; iPadOS offers nothing from the Passwords app for it (ruling A41). Whatever lands in that field -
/// a typed key, or several characters at once by any other path - goes to the game straight away as key
/// events, one character at a time through the sink, and the field is emptied at once. Several characters at
/// once also close the keyboard: the game shows the dots and the player taps Log In (mockup 28). Return is sent only
/// when the player presses Return. Control characters are never typed.
///
/// The field's text is never logged, stored, copied or kept: it is not read except to send it, and the
/// field never holds it beyond the call that put it there. Logs name what happened ("password field up"),
/// never what was typed or how long it was.
///
/// The chat kind is not this field: it asks `openChat`, which is the controls' existing composer.
@interface AKTouchTextBridge : NSObject
/// The text's destination (held weakly): the controls, which pass it to the host.
@property (nonatomic, weak, nullable) id<AKTouchTextSink> sink;
/// What `beginForKind:AKTextKindChat` does: open the controls' chat composer.
@property (nonatomic, copy, nullable) void (^openChat)(void);
/// Called when the field takes or gives up the keyboard. Given up with `kind` still set: it lost the keyboard on its own
/// (another view took it); with `kind` None: `end` closed it.
@property (nonatomic, copy, nullable) void (^activeChanged)(BOOL active);
/// The clock (seconds) for the debounce and the quiet time after a fill. The default is the system uptime; tests give
/// their own.
@property (nonatomic, copy, null_resettable) NSTimeInterval (^clock)(void);
/// Called when the game's secure input has stayed on past the debounce: the password box really has focus. `opening`
/// is whether the field is about to open (NO in the quiet time after a fill); call `open` to let it - the caller may
/// do its own work around it (the controls hand the keyboard over from the chat composer). With no block set the field
/// just opens.
@property (nonatomic, copy, nullable) void (^secureFocusConfirmed)(BOOL opening, void (^open)(void));

/// Whether the app is active now (the controls read the scene: during UIApplicationWillResignActiveNotification
/// UIApplication still says active). While it is not, `tick` leaves a waiting "on" waiting; call `tick` when the app is
/// active again. No block: always active.
@property (nonatomic, copy, nullable) BOOL (^appIsActive)(void);

/// Whether the player is in the world now (the controls set it from the world signal before each secure-input change;
/// default NO). A secure input that starts in the world waits AKTouchPasswordInWorldDebounceSeconds, not the debounce.
@property (nonatomic) BOOL inWorld;

/// The field. Put in the game's view by `attachToView:`; it never takes a touch.
@property (nonatomic, readonly) UITextField *field;
/// The kind the field is set up for; None when the bridge is closed. The chat kind is never the field's. It stays set when
/// the field loses the keyboard on its own (the Passwords sheet, Face ID): only `end` (and the game's box losing focus
/// while the app is active) clears it, so the field can still take an AutoFill that UIKit hands it afterwards.
@property (nonatomic, readonly) AKTextKind kind;
/// Whether the field has the keyboard now.
@property (nonatomic, readonly) BOOL active;

/// Adds the field to `view` (the game's view): AKTouchPasswordFieldSize, centred on the login password box
/// (AKTouchPasswordBoxCentre of the view's bounds, placed again whenever it opens), drawn clear, faint but not
/// hidden, never taking a touch.
- (void)attachToView:(UIView *)view;
/// Chat: closes the field and calls `openChat`. Username, Password: sets the field up for that kind and
/// gives it the keyboard. None: the same as `end`. Chat goes to `openChat` without closing the field first, so the
/// keyboard passes straight from one to the other (the field gives it up when the composer takes it).
- (void)beginForKind:(AKTextKind)kind;
/// Closes the field: the keyboard goes, nothing is sent, the field is emptied.
- (void)end;
/// The game turned secure event input on or off (patch 0058: its password box has the keyboard). On: the
/// password kind, unless it is already up - but only if it is still on after AKTouchPasswordDebounceSeconds
/// (`tick` settles that, and only while the app is active), so a pulse never opens it. Off: a waiting "on" is forgotten;
/// the field is closed - but only while the app is active, because the game also turns it off when the app resigns
/// active, which Face ID's sheet does in the middle of an autofill (`appActive` must say inactive then: the controls read
/// the scene's state, not UIApplication's, which still reads active during UIApplicationWillResignActiveNotification).
/// Within
/// AKTouchFillQuietSeconds of a whole password arriving, "on" is ignored (the box is filled; Face ID's sheet going away
/// turns it on again), unless an "off" while active came first.
- (void)secureInputChanged:(BOOL)enabled appActive:(BOOL)appActive;
/// Settles the debounce: opens the password field if secure input has stayed on long enough. A timer calls it; tests
/// move their clock and call it.
- (void)tick;
@end

NS_ASSUME_NONNULL_END
