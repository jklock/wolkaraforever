// WolkaraForever: the app's own language, in one place.
//
// Two languages are independent here, and mixing them up is the bug this file exists to
// prevent. `WoWLocale` is the *game's* download language: it selects what WoW downloads
// and what its textLocale/audioLocale say. `WolkaraForeverAppLanguage` is the *app's*
// language: it decides the language of every label WolkaraForever draws. A player can
// read the launcher in German while playing the English client, and the other way round.
//
// The choice has three settings: English, German, and System Default. System Default is
// resolved here, once, from the iPad's own preferred-language list, and only German is
// ever a match: anything else falls back to English, because English is the one language
// every build has complete. Nothing in the app resolves the language for itself.
//
// This class is deliberately tiny and Foundation-only:
//
//   - it is safe before any UI exists, because it is read from the app delegate's launch
//     path (the log's first line, an error page, a closing countdown) as well as from
//     views, and "which language" must not depend on a view having been built;
//   - it is usable from Swift product code through the same class methods;
//   - it posts WKLocalizationDidChangeNotification so a screen that is already up can
//     redraw in the new language instead of waiting for a relaunch.
//
// The strings themselves are the app's own resources: en.lproj/Localizable.strings and
// de.lproj/Localizable.strings beside this file. Keys are namespaced by the screen or
// subsystem that owns them ("home.play", "addons.install", "overlay.thermal.serious"),
// and a key that is missing falls back to English, then to a readable form of its own
// last component. A raw key is never shown: that is asserted by the launcher fixture and
// by the table check in wolkaraforever/tools/check_localization.py.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WKAppLanguage) {
    WKAppLanguageSystem = 0,
    WKAppLanguageEnglish,
    WKAppLanguageGerman,
};

/// Posted when the app-language setting changes, on the thread that changed it. The
/// userInfo carries WKLocalizationOldLanguageKey and WKLocalizationNewLanguageKey.
extern NSNotificationName const WKLocalizationDidChangeNotification;
extern NSString *const WKLocalizationOldLanguageKey;
extern NSString *const WKLocalizationNewLanguageKey;

/// The defaults key the setting lives under. It is also one of the config-file keys, so
/// the choice survives an export and a reinstall like every other choice the user makes.
extern NSString *const WKAppLanguageDefaultsKey;

@interface WKLocalization : NSObject

+ (instancetype)shared;

/// The user's choice, including WKAppLanguageSystem. Setting it persists the value and
/// posts WKLocalizationDidChangeNotification; it does not rebuild any UI by itself.
@property (nonatomic) WKAppLanguage language;

/// The language actually in use: never WKAppLanguageSystem. This is what every label,
/// every accessibility string and every date in the app is drawn in.
@property (nonatomic, readonly) WKAppLanguage resolvedLanguage;
/// @"en" or @"de", the resolved language's resource folder and BCP-47-ish tag.
@property (nonatomic, readonly, copy) NSString *languageCode;
/// A locale for the resolved language, so a date, a byte count or a version number is
/// formatted the way that language writes it rather than the way the iPad is set to.
@property (nonatomic, readonly, copy) NSLocale *locale;

/// The resolved language's name, written in that language: "English", "Deutsch".
@property (nonatomic, readonly, copy) NSString *resolvedLanguageName;
/// The setting as the row shows it: the resolved language's own name for English and
/// German, and the translated "System Default" when the setting follows the iPad.
@property (nonatomic, readonly, copy) NSString *settingDisplayName;

#pragma mark - Resolution

/// What a setting resolves to for a given preferred-language list. The first entry that
/// is a language this app has strings for wins; anything else is skipped, so a list of
/// French then German is German, and a list of English then German is English. A setting
/// of English or German ignores the list.
+ (WKAppLanguage)resolveLanguage:(WKAppLanguage)language
           fromPreferredLanguages:(nullable NSArray<NSString *> *)languages;
/// The BCP-47 code of a language this app ships. Only en and de are matching.
+ (nullable NSString *)matchedCodeForLanguageIdentifier:(NSString *)identifier;
+ (NSString *)codeForLanguage:(WKAppLanguage)language;
/// The stored spelling of a setting, and the setting a stored spelling means. Anything
/// unrecognised, including a missing value, is WKAppLanguageSystem - which is what an
/// installation that predates this setting should do.
+ (NSString *)storedValueForLanguage:(WKAppLanguage)language;
+ (WKAppLanguage)languageForStoredValue:(nullable id)value;
/// The languages the choice list offers, in order.
+ (NSArray<NSNumber *> *)choices;

#pragma mark - Strings

/// The translated string for `key`, falling back to English and then to a readable form
/// of the key's last component. Never nil, never a raw key.
+ (NSString *)localizedString:(NSString *)key;
/// The translated string for `key`, used as a format. The format itself is translated,
/// so word order and every `%` conversion come from the table.
///
/// Deliberately not annotated NS_FORMAT_FUNCTION: the first argument is a key, not a
/// format, so the compiler would check the key and report every argument as unused. The
/// conversions are checked instead by wolkaraforever/tools/check_localization.py, which
/// compares them across both tables and knows what the runtime does with them.
+ (NSString *)localizedFormat:(NSString *)key, ...;
/// The plural form that fits `count`: `key.zero`, `key.one` and `key.other` are looked up
/// in that order (zero only for 0, so English's "no add-ons" and German's "keine Add-ons"
/// can be said properly).
+ (NSString *)localizedString:(NSString *)key count:(NSInteger)count;
+ (NSString *)localizedFormat:(NSString *)key count:(NSInteger)count, ...;

/// Whether a key exists in the resolved language's table. For tests and for diagnostics;
/// nothing in the UI branches on it.
+ (BOOL)hasLocalizedString:(NSString *)key;

/// The resolved language code without an instance: for code that cannot hold one, such as a
/// compatibility library asking this class by name at runtime.
+ (NSString *)currentLanguageCode;

/// Where the service's own few log lines go. The app's shell installs the log here; a test binary
/// does not, and then nothing is written. A hook rather than a direct call because the Mac-side
/// suites of the modules that read strings link this file without the log's implementation.
void WKLocalizationSetLogger(void (*_Nullable logger)(NSString *tag, NSString *message));

#pragma mark - Tests

/// The language list System Default resolves against. Production reads the iPad's own
/// list; a test substitutes one so the resolution rules can be exercised on either.
+ (void)setPreferredLanguagesForTesting:(nullable NSArray<NSString *> *)languages;
/// The resource bundle the tables are read from. Nil (the default) means the app bundle.
+ (void)setResourceBundleForTesting:(nullable NSBundle *)bundle;
/// Forget the cached tables and re-read them, as a relaunch would.
+ (void)reloadForTesting;

@end

/// The app's language, resolved and translated. WKLocalized(key) is the whole API most
/// call sites need; it never returns nil and never returns the key itself.
///
/// The plural macros' second parameter is `n`, not `count`: a macro parameter is replaced
/// wherever its token appears, including in the `count:` selector label, which silently
/// turned the call into a syntax error the first time it was called `count`.
#define WKLocalized(key) [WKLocalization localizedString:(key)]
#define WKLocalizedFormat(key, ...) [WKLocalization localizedFormat:(key), ##__VA_ARGS__]
#define WKLocalizedCount(key, n) [WKLocalization localizedString:(key) count:(n)]
#define WKLocalizedCountFormat(key, n, ...) [WKLocalization localizedFormat:(key) count:(n), ##__VA_ARGS__]

NS_ASSUME_NONNULL_END
