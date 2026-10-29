#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const TKForeverUIErrorDomain;
// The Forever edition these rows are about. They never touch another edition's
// files: every path is resolved from that installation's working directory and
// checked to stay inside it.
FOUNDATION_EXPORT NSString *const TKForeverUIEdition;

// WoW Forever file operations for the home page's Performance & UI Manager.
//
// The configuration half is here, in Objective-C, because it is small, byte
// exact and testable without a simulator. The archive half is a Swift class
// (ForeverUIArchive.swift) that uses the project's pinned ZIPFoundation; it is
// reached by name so this module does not depend on Swift at link time.
@interface TKForeverUI : NSObject

// WTF/Config.wtf, with every GamePadEnable assignment normalised to exactly one
// `SET GamePadEnable "1"`. Other lines keep their bytes. Reads the file back and
// fails unless exactly one assignment with value 1 is present.
+ (BOOL)enableGamepadInWorkingDirectory:(NSString *)directory error:(NSError **)error;
// The same write with either value, for the switch: exactly one assignment,
// `"1"` or `"0"`, everything else byte-identical.
+ (BOOL)setGamepad:(BOOL)enabled inWorkingDirectory:(NSString *)directory error:(NSError **)error;

// Writes exactly one `SET <name> "<value>"` for each entry, removes every other
// assignment of those names, and leaves every other line byte-identical. Reads
// the file back and fails unless exactly one assignment per name is present with
// the value asked for. Names are matched case-insensitively, as WoW does. A name
// that is empty, contains whitespace or a quote is refused rather than guessed
// at, because a broken line would silently do nothing.
+ (BOOL)setCVars:(NSDictionary<NSString *, NSString *> *)values
inWorkingDirectory:(NSString *)directory
           error:(NSError **)error;

// Keeps the installed Forever client's text and audio language aligned with
// the launcher selection. Only these two CVar assignments are replaced; every
// other Config.wtf line keeps its bytes. Supported Blizzard locale tags are
// required so the launcher can never write an unusable setting.
+ (BOOL)setLocale:(NSString *)locale
inWorkingDirectory:(NSString *)directory
           error:(NSError **)error;

// The client settings this app applies so a frame fits the display's budget.
//
// Measured on Dadpad (M1 iPad Pro 12.9, iPadOS 27, 2026-10-23): the client
// renders at native 2732x2048 with no render scale of its own and no frame cap,
// spends 8-9 ms of GPU time per in-world frame and then misses the 16.7 ms
// display budget, settling near 45 fps; twenty minutes later it is thermally
// throttling ("Serious") at 32.6 fps with both CPU and GPU clocks down. These
// are the client's own CVars, so the client keeps its own quality settings and
// nothing here is a binary patch.
+ (NSDictionary<NSString *, NSString *> *)performancePreset;
+ (BOOL)applyPerformancePresetInWorkingDirectory:(NSString *)directory error:(NSError **)error;

// YES when Config.wtf exists and carries exactly one GamePadEnable assignment,
// with value 1. A missing or unreadable config reads as NO.
+ (BOOL)gamepadEnabledInWorkingDirectory:(NSString *)directory;

// Removes only the graphics/display CVars in the measured Forever allowlist and
// rewrites the file atomically. Account, locale, audio, UI, input, gamepad,
// cache and unknown settings are preserved byte for byte.
+ (BOOL)resetGraphicsInWorkingDirectory:(NSString *)directory error:(NSError **)error;

// The allowlist itself, for tests and for anyone who needs to say what a reset
// removes without reading a Config.wtf. Names are compared case-insensitively.
FOUNDATION_EXPORT NSSet<NSString *> *TKForeverUIGraphicsCVars(void);

// The Forever installation's WTF directory. Creates it only when asked, and
// only inside the working directory. Nil when the path cannot be resolved.
+ (nullable NSString *)wtfDirectoryInWorkingDirectory:(NSString *)directory
                                               create:(BOOL)create
                                                error:(NSError **)error;

// Archive bridge. Each returns nil/NO with an error when the archive class is
// not in the build, so a caller can explain that rather than claim success.
+ (nullable NSString *)createUIBackupInWorkingDirectory:(NSString *)directory
                                               edition:(NSString *)edition
                                                 error:(NSError **)error;
+ (nullable NSString *)newestUIBackupInWorkingDirectory:(NSString *)directory
                                                  error:(NSError **)error;
+ (BOOL)restoreUIBackupNamed:(NSString *)name
          inWorkingDirectory:(NSString *)directory
                     edition:(NSString *)edition
                       error:(NSError **)error;
+ (BOOL)recoverInterruptedRestoreInWorkingDirectory:(NSString *)directory
                                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
