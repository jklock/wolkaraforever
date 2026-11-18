#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The interface the user asked for. One key, read wherever a decision depends on
/// it, so the launcher's selector and the guest's own controls cannot disagree about
/// which one is on.
///
/// Five spellings are understood: "ipados" (Standard), "ios" (an ordinary phone), "iosduo" (the
/// Duo), "ipadtouch" (an iPad run with the TouchPlay add-on's touch interface), and "auto" -
/// whatever this device is, from its own hardware class. "auto" never resolves to "ipadtouch":
/// that one is chosen on purpose.
///
/// A missing value, "ipados", or a value this build does not recognise means Standard:
/// the interface every installation had, so adding "auto" changes nothing for an
/// existing one.
extern NSString *const AKInterfaceModeDefaultsKey;   // "WolkaraForeverInterfaceModeV1"
extern NSString *const AKInterfaceModeIPadOS;        // "ipados"
extern NSString *const AKInterfaceModeIOS;           // "ios"
extern NSString *const AKInterfaceModeIOSDuo;        // "iosduo"
extern NSString *const AKInterfaceModeIPadTouch;     // "ipadtouch"
extern NSString *const AKInterfaceModeAuto;          // "auto"

/// Whether the mobile interface is on: "ios", "iosduo" and "ipadtouch", and "auto" on a phone.
/// The hardware is read here and nowhere else in the app.
FOUNDATION_EXPORT BOOL AKInterfaceModeIsMobile(void);

/// Whether the TouchPlay interface is on: YES only for the stored value "ipadtouch". In it the
/// game's touch comes from the TouchPlay add-on's own buttons, so the controller overlay and its
/// virtual gamepad are not made. Later TouchPlay behaviour gates on this, not on the mode string.
FOUNDATION_EXPORT BOOL AKInterfaceModeIsTouchPlay(void);

/// Whether the stored choice is "auto", so the launcher can mark it as such.
FOUNDATION_EXPORT BOOL AKInterfaceModeIsAutomatic(void);

/// What "auto" resolves to on this device, whatever is chosen now, so the selector can say
/// "Automatic (iOS on Duo)" on a Duo while iPadOS is what is in force.
FOUNDATION_EXPORT NSString *AKInterfaceModeAutomaticName(void);

/// What the stored choice resolves to: "ipados", "ios", "iosduo" or "ipadtouch".
FOUNDATION_EXPORT NSString *AKInterfaceModeName(void);

/// The stored choice itself: "auto", "ipados", "ios", "iosduo" or "ipadtouch", never the resolution.
FOUNDATION_EXPORT NSString *AKInterfaceModeStoredName(void);

#pragma mark Crash fallback (iPad touch only)

/// Games that started in iPad touch and never exited cleanly, in a row. Only while "ipadtouch" is
/// the stored mode is this ever read, written or cleared; every other value leaves it alone.
extern NSString *const AKTouchCrashGuardDefaultsKey;   // "WolkaraForeverTouchUncleanStarts"

/// The three primitives. The launcher's start and exit paths do not call these; they go through the
/// session functions below, so one place decides what counts.

/// Counts a game start as unclean until it exits cleanly.
FOUNDATION_EXPORT void AKTouchCrashGuardWillStart(void);

/// A clean way out of a game: the run of unclean starts is over.
FOUNDATION_EXPORT void AKTouchCrashGuardDidExitCleanly(void);

/// The session, driven by Shell/main.m. Only a real crash may leave the count up.
///
/// Begin: a game is about to start. In any other mode than iPad touch it does nothing at all. In iPad
/// touch it counts the start, installs once (per process) an atexit handler
/// - every orderly exit() is a clean exit, including the one the game's own Quit reaches through the
/// host - and a watch on the app's background/foreground: put away, the session is taken out of the
/// count (iPadOS may kill a backgrounded app, and that is not a crash); back in front, while the game
/// is still running, it is counted again.
FOUNDATION_EXPORT void AKTouchCrashGuardBeginSession(void);

/// Any clean way out: the guest returned, the user chose Leave game, the guest called exit(0).
FOUNDATION_EXPORT void AKTouchCrashGuardEndSession(void);

/// The game never got going (it did not start): this session is taken out of the count, and an
/// earlier unclean start is left as it was.
FOUNDATION_EXPORT void AKTouchCrashGuardAbandonSession(void);

/// What atexit() runs, and whether Begin has installed it - exposed so a test can run the very
/// function the process would, and fail if the wiring is gone.
FOUNDATION_EXPORT void AKTouchCrashGuardExitHandler(void);
FOUNDATION_EXPORT BOOL AKTouchCrashGuardExitHandlerInstalled(void);

/// Whether two unclean starts in a row are on record while iPad touch is the stored mode.
FOUNDATION_EXPORT BOOL AKTouchCrashGuardShouldFallBack(void);

/// If it should fall back: stores "ipados", clears the count and answers YES, once. The launcher
/// calls this where the user can see the page and says so when it answers YES.
FOUNDATION_EXPORT BOOL AKTouchCrashGuardApplyFallback(void);

NS_ASSUME_NONNULL_END
