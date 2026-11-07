// WolkaraForever: the app's own language, resolved once and read everywhere.
//
// See WKLocalization.h for why this is Foundation-only and why the game's language is a
// different setting entirely.

#import "WKLocalization.h"

// Where these few lines go, installed by the app's own shell. A hook rather than a call into the
// log, because this file is also linked by the Mac-side unit tests of the modules that read
// strings (ForeverUI's Config.wtf rules, the add-on store, this file's own suite), and none of
// them has a log to write to. With no hook installed the lines are simply not written.
static void (*WKLocalizationLogger)(NSString *tag, NSString *message) = NULL;

void WKLocalizationSetLogger(void (*logger)(NSString *tag, NSString *message)) {
    WKLocalizationLogger = logger;
}

static void WKLanguageLog(NSString *tag, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static void WKLanguageLog(NSString *tag, NSString *format, ...) {
    if (!WKLocalizationLogger) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    WKLocalizationLogger(tag, message);
}

NSNotificationName const WKLocalizationDidChangeNotification = @"WKLocalizationDidChange";
NSString *const WKLocalizationOldLanguageKey = @"old";
NSString *const WKLocalizationNewLanguageKey = @"new";
NSString *const WKAppLanguageDefaultsKey = @"WolkaraForeverAppLanguage";

// The languages this app has strings for. Order matters for resolution: it is the order
// a preferred-language list is matched against nothing at all - the list's own order is
// what decides - so this is only the set of codes that can match.
static NSString *const WKLanguageEnglish = @"en";
static NSString *const WKLanguageGerman = @"de";

static NSArray<NSString *> *WKSupportedLanguageCodes(void) {
    static NSArray<NSString *> *codes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ codes = @[WKLanguageEnglish, WKLanguageGerman]; });
    return codes;
}

// A table cached by the language it belongs to. Two tables in a launch at most: the one
// asked for and English to fall back on.
@interface WKLanguageTable : NSObject
@property(nonatomic, copy) NSString *code;
@property(nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *strings;
@end
@implementation WKLanguageTable
@end

@implementation WKLocalization {
    WKLanguageTable *_resolved;
    WKLanguageTable *_english;
    // What the setting said the last time a change was announced, so a change that came
    // from outside this class (the config file's import at launch, a test) is announced
    // exactly once and this class's own write is not announced twice.
    NSString *_lastAnnouncedValue;
}

+ (instancetype)shared {
    static WKLocalization *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [WKLocalization new];
        [shared observeDefaults];
    });
    return shared;
}

- (void)observeDefaults {
    _lastAnnouncedValue = [WKLocalization storedValueForLanguage:self.language];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(defaultsChanged:)
                                               name:NSUserDefaultsDidChangeNotification object:nil];
}

#pragma mark - Tests

static NSArray<NSString *> *WKPreferredLanguagesOverride;
static NSBundle *WKResourceBundleOverride;

+ (void)setPreferredLanguagesForTesting:(nullable NSArray<NSString *> *)languages {
    WKPreferredLanguagesOverride = [languages copy];
    [self reloadForTesting];
}
+ (void)setResourceBundleForTesting:(nullable NSBundle *)bundle {
    WKResourceBundleOverride = bundle;
    [self reloadForTesting];
}
+ (void)reloadForTesting {
    WKLocalization *shared = WKLocalization.shared;
    @synchronized (shared) {
        shared->_resolved = nil;
        shared->_english = nil;
    }
}

#pragma mark - The setting

- (WKAppLanguage)language {
    return [WKLocalization languageForStoredValue:
        [NSUserDefaults.standardUserDefaults objectForKey:WKAppLanguageDefaultsKey]];
}

- (void)setLanguage:(WKAppLanguage)language {
    NSString *stored = [WKLocalization storedValueForLanguage:language];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![[defaults stringForKey:WKAppLanguageDefaultsKey] isEqual:stored])
        [defaults setObject:stored forKey:WKAppLanguageDefaultsKey];
    // The write above reaches this class again through NSUserDefaultsDidChange, and that
    // is what announces it: one path, so an outside change and this one behave alike.
    [self announceIfChanged];
}

- (void)defaultsChanged:(NSNotification *)note {
    (void)note;
    [self announceIfChanged];
}

- (void)announceIfChanged {
    NSString *value = [WKLocalization storedValueForLanguage:self.language];
    NSString *previous;
    @synchronized (self) {
        if ([_lastAnnouncedValue isEqual:value]) return;
        previous = _lastAnnouncedValue ?: value;
        _lastAnnouncedValue = value;
        // The tables belong to the language that was in use; the change is about to
        // invalidate them, and a screen that redraws during the announcement must read
        // the new one rather than the old cache.
        _resolved = nil;
    }
    WKAppLanguage old = [WKLocalization languageForStoredValue:previous];
    WKAppLanguage now = [WKLocalization languageForStoredValue:value];
    WKLanguageLog(@"language", @"the app language is now %@ (was %@), resolved to %@",
          [WKLocalization storedValueForLanguage:now], [WKLocalization storedValueForLanguage:old],
          [self languageCode]);
    [NSNotificationCenter.defaultCenter postNotificationName:WKLocalizationDidChangeNotification
                                                     object:self
                                                   userInfo:@{WKLocalizationOldLanguageKey: @(old),
                                                              WKLocalizationNewLanguageKey: @(now)}];
}

#pragma mark - Resolution

+ (NSArray<NSString *> *)preferredLanguages {
    if (WKPreferredLanguagesOverride) return WKPreferredLanguagesOverride;
    NSArray<NSString *> *languages = NSLocale.preferredLanguages;
    return languages.count ? languages : @[@"en"];
}

+ (nullable NSString *)matchedCodeForLanguageIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
    // "de", "de-DE", "de_AT" and "de-Latn-DE" are all German. The separator is normalised
    // because NSLocale's own list uses '-' while a bundle identifier uses '_', and both
    // reach this method.
    NSString *normalised = [identifier stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSString *primary = [normalised componentsSeparatedByString:@"-"].firstObject.lowercaseString;
    return [WKSupportedLanguageCodes() containsObject:primary] ? primary : nil;
}

+ (WKAppLanguage)resolveLanguage:(WKAppLanguage)language
           fromPreferredLanguages:(nullable NSArray<NSString *> *)languages {
    if (language != WKAppLanguageSystem) return language;
    for (NSString *identifier in languages ?: @[]) {
        NSString *code = [self matchedCodeForLanguageIdentifier:identifier];
        if ([code isEqual:WKLanguageGerman]) return WKAppLanguageGerman;
        if ([code isEqual:WKLanguageEnglish]) return WKAppLanguageEnglish;
    }
    // No supported language anywhere in the list: English, the language every build is
    // complete in, rather than the first language we happen not to ship.
    return WKAppLanguageEnglish;
}

+ (NSString *)codeForLanguage:(WKAppLanguage)language {
    return language == WKAppLanguageGerman ? WKLanguageGerman : WKLanguageEnglish;
}

+ (NSString *)storedValueForLanguage:(WKAppLanguage)language {
    switch (language) {
    case WKAppLanguageGerman: return WKLanguageGerman;
    case WKAppLanguageEnglish: return WKLanguageEnglish;
    case WKAppLanguageSystem: default: return @"system";
    }
}

+ (WKAppLanguage)languageForStoredValue:(nullable id)value {
    if (![value isKindOfClass:NSString.class]) return WKAppLanguageSystem;
    NSString *text = [value lowercaseString];
    if ([text isEqual:WKLanguageEnglish]) return WKAppLanguageEnglish;
    if ([text isEqual:WKLanguageGerman]) return WKAppLanguageGerman;
    // Includes "system", and anything a hand-edited config file invented.
    return WKAppLanguageSystem;
}

+ (NSArray<NSNumber *> *)choices {
    return @[@(WKAppLanguageEnglish), @(WKAppLanguageGerman), @(WKAppLanguageSystem)];
}

- (WKAppLanguage)resolvedLanguage {
    return [WKLocalization resolveLanguage:self.language
                    fromPreferredLanguages:[WKLocalization preferredLanguages]];
}

- (NSString *)languageCode { return [WKLocalization codeForLanguage:self.resolvedLanguage]; }

- (NSLocale *)locale {
    return [NSLocale localeWithLocaleIdentifier:
        self.resolvedLanguage == WKAppLanguageGerman ? @"de_DE" : @"en_GB"];
}

- (NSString *)resolvedLanguageName {
    return self.resolvedLanguage == WKAppLanguageGerman ? @"Deutsch" : @"English";
}

- (NSString *)settingDisplayName {
    if (self.language == WKAppLanguageSystem)
        return [self.resolvedLanguageName stringByAppendingFormat:@" — %@", WKLocalized(@"lang.system")];
    return self.resolvedLanguageName;
}

#pragma mark - Tables

// One table, read from the named .lproj inside the app bundle. Xcode compiles
// Localizable.strings to a binary plist and the fixture ships the same file as text;
// -dictionaryWithContentsOfFile: reads both.
static NSDictionary<NSString *, NSString *> *WKLoadTable(NSString *code) {
    NSBundle *bundle = WKResourceBundleOverride ?: NSBundle.mainBundle;
    NSString *folder = [bundle pathForResource:code ofType:@"lproj"];
    if (!folder) return nil;
    NSString *path = [folder stringByAppendingPathComponent:@"Localizable.strings"];
    id table = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![table isKindOfClass:NSDictionary.class] || ![table count]) return nil;
    return table;
}

- (NSDictionary<NSString *, NSString *> *)tableForCode:(NSString *)code {
    BOOL english = [code isEqual:WKLanguageEnglish];
    WKLanguageTable *slot = english ? _english : _resolved;
    @synchronized (self) {
        if (!slot || ![slot.code isEqual:code]) {
            slot = [WKLanguageTable new];
            slot.code = code;
            slot.strings = WKLoadTable(code);
            if (english) _english = slot; else _resolved = slot;
            if (!slot.strings)
                WKLanguageLog(@"language", @"no %@ table in this build; English is the fallback", code);
        }
    }
    return slot.strings;
}

- (nullable NSString *)lookup:(NSString *)key code:(NSString *)code {
    NSString *value = [self tableForCode:code][key];
    if ([value isKindOfClass:NSString.class] && value.length) return value;
    return nil;
}

// The last resort, and never a raw key: the last component of the key, without its
// namespace and with its underscores read as spaces. "home.play" reads as "Play". This
// only happens in a build whose resources are wrong, which the table check in
// wolkaraforever/tools/check_localization.py is what stops.
static NSString *WKReadableKey(NSString *key) {
    NSString *leaf = [key componentsSeparatedByString:@"."].lastObject ?: key;
    NSString *words = [leaf stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    if (!words.length) return @"";
    return [words stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                         withString:[words substringToIndex:1].uppercaseString];
}

- (NSString *)stringForKey:(NSString *)key {
    if (![key isKindOfClass:NSString.class] || !key.length) return @"";
    NSString *code = self.languageCode;
    NSString *value = [self lookup:key code:code];
    if (value) return value;
    if (![code isEqual:WKLanguageEnglish]) {
        value = [self lookup:key code:WKLanguageEnglish];
        if (value) {
            WKLanguageLog(@"language", @"%@ has no %@ string; English is shown", key, code);
            return value;
        }
    }
    WKLanguageLog(@"language", @"%@ is in neither table; its own name is shown", key);
    return WKReadableKey(key);
}

+ (NSString *)localizedString:(NSString *)key {
    return [WKLocalization.shared stringForKey:key];
}

+ (NSString *)localizedFormat:(NSString *)key, ... {
    NSString *format = [WKLocalization.shared stringForKey:key];
    va_list arguments;
    va_start(arguments, key);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    return text;
}

+ (NSString *)localizedString:(NSString *)key count:(NSInteger)count {
    // Zero, one, other - in that order of preference, in the table's own spelling. A
    // language that does not distinguish zero or one simply leaves that key out and the
    // "other" form is used, so a table never has to carry a form it does not need.
    NSArray<NSString *> *forms = count == 0 ? @[@".zero", @".other", @".one"]
                                 : (count == 1 || count == -1) ? @[@".one", @".other", @".zero"]
                                 : @[@".other", @".one", @".zero"];
    for (NSString *form in forms) {
        NSString *value = [[WKLocalization shared] lookup:[key stringByAppendingString:form]
                                                     code:[WKLocalization currentLanguageCode]];
        if (value) return value;
    }
    // No plural-aware form at all: the plain string is better than a guess.
    return [[WKLocalization shared] stringForKey:key];
}

+ (NSString *)localizedFormat:(NSString *)key count:(NSInteger)count, ... {
    NSString *format = [self localizedString:key count:count];
    va_list arguments;
    va_start(arguments, count);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    return text;
}

+ (BOOL)hasLocalizedString:(NSString *)key {
    WKLocalization *localization = WKLocalization.shared;
    return [localization lookup:key code:localization.languageCode] != nil;
}

+ (NSString *)currentLanguageCode { return WKLocalization.shared.languageCode; }

@end
