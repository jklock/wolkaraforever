// WolkaraForever: the app's language, on its own.
//
// Foundation only, so it runs on the Mac beside the other unit tests instead of in a simulator:
// resolving a language, reading the tables, choosing a plural and formatting a string have no UI
// in them, and a test that needed a booted iPad would be run less often.
//
// What is *not* here is the part that is not Foundation: the persisted choice lives in the config
// file, whose schema is UIKit-bearing, so its migration is checked by the launcher fixture
// (WoW/tests/test_wow_launcher_app.m) together with the German screen flow.
//
//   wolkaraforever/tools/test_localization.sh

#import <Foundation/Foundation.h>
#import "../launcher/App/WKLocalization.h"
#include <stdio.h>

static int failures = 0, checks = 0;

#define CHECK(condition, description) do { \
    checks++; \
    if (!(condition)) { failures++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, [(description) UTF8String]); } \
} while (0)

// A bundle of our own making, so the fallback chain can be tested with a table that is genuinely
// incomplete: the shipped tables are kept complete by check_localization.py, which is the point of
// the fallback being unreachable in a real build.
static NSBundle *MakeBundle(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *tables) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    for (NSString *code in tables) {
        NSString *folder = [[root stringByAppendingPathComponent:code] stringByAppendingPathExtension:@"lproj"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
        NSMutableString *text = [NSMutableString string];
        for (NSString *key in tables[code]) [text appendFormat:@"\"%@\" = \"%@\";\n", key, tables[code][key]];
        [text writeToFile:[folder stringByAppendingPathComponent:@"Localizable.strings"]
               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    return [NSBundle bundleWithPath:root];
}

static void TestResolution(void) {
    // The setting wins over the device.
    CHECK([WKLocalization resolveLanguage:WKAppLanguageEnglish fromPreferredLanguages:@[@"de-DE"]] == WKAppLanguageEnglish,
          @"English is English on a German iPad");
    CHECK([WKLocalization resolveLanguage:WKAppLanguageGerman fromPreferredLanguages:@[@"en-US"]] == WKAppLanguageGerman,
          @"German is German on an English iPad");
    // System follows the list, in its order, and only for a language we ship.
    CHECK(([WKLocalization resolveLanguage:WKAppLanguageSystem fromPreferredLanguages:@[@"de-DE", @"en-US"]] == WKAppLanguageGerman),
          @"a German first choice resolves to German");
    CHECK(([WKLocalization resolveLanguage:WKAppLanguageSystem fromPreferredLanguages:@[@"en-US", @"de-DE"]] == WKAppLanguageEnglish),
          @"an English first choice resolves to English");
    CHECK(([WKLocalization resolveLanguage:WKAppLanguageSystem fromPreferredLanguages:@[@"ja-JP", @"de-DE"]] == WKAppLanguageGerman),
          @"a language we do not ship is skipped, not treated as English");
    CHECK(([WKLocalization resolveLanguage:WKAppLanguageSystem fromPreferredLanguages:@[@"ja-JP", @"it-IT"]] == WKAppLanguageEnglish),
          @"nothing we ship falls back to English");
    CHECK([WKLocalization resolveLanguage:WKAppLanguageSystem fromPreferredLanguages:@[]] == WKAppLanguageEnglish,
          @"an empty list falls back to English");
    CHECK([WKLocalization resolveLanguage:WKAppLanguageSystem fromPreferredLanguages:nil] == WKAppLanguageEnglish,
          @"a missing list falls back to English");
    // Identifiers as the system writes them.
    CHECK([[WKLocalization matchedCodeForLanguageIdentifier:@"de"] isEqual:@"de"], @"de matches");
    CHECK([[WKLocalization matchedCodeForLanguageIdentifier:@"de-DE"] isEqual:@"de"], @"de-DE matches");
    CHECK([[WKLocalization matchedCodeForLanguageIdentifier:@"de_AT"] isEqual:@"de"], @"de_AT matches");
    CHECK([[WKLocalization matchedCodeForLanguageIdentifier:@"de-Latn-DE"] isEqual:@"de"], @"a script subtag still matches");
    CHECK([[WKLocalization matchedCodeForLanguageIdentifier:@"fr-CA"] isEqual:@"fr"], @"fr-CA matches French");
    CHECK([[WKLocalization matchedCodeForLanguageIdentifier:@"en-GB"] isEqual:@"en"], @"en-GB matches");
    CHECK([WKLocalization matchedCodeForLanguageIdentifier:@"eng"] == nil, @"eng is not en");
    CHECK([WKLocalization matchedCodeForLanguageIdentifier:@"dee"] == nil, @"dee is not de");
    CHECK([WKLocalization matchedCodeForLanguageIdentifier:@""] == nil, @"an empty identifier matches nothing");
    // Through a variable: -Wnonnull refuses a literal nil for a non-null parameter, and what
    // this checks is that a nil arriving at run time - a malformed call - is still handled.
    NSString *nothing = nil;
    CHECK([WKLocalization matchedCodeForLanguageIdentifier:nothing] == nil, @"a nil identifier matches nothing");
}

static void TestStoredValues(void) {
    CHECK([[WKLocalization storedValueForLanguage:WKAppLanguageSystem] isEqual:@"system"], @"system is stored as system");
    CHECK([[WKLocalization storedValueForLanguage:WKAppLanguageEnglish] isEqual:@"en"], @"English is stored as en");
    CHECK([[WKLocalization storedValueForLanguage:WKAppLanguageGerman] isEqual:@"de"], @"German is stored as de");
    CHECK([[WKLocalization storedValueForLanguage:WKAppLanguageFrench] isEqual:@"fr"], @"French is stored as fr");
    CHECK([WKLocalization languageForStoredValue:@"de"] == WKAppLanguageGerman, @"de reads back as German");
    CHECK([WKLocalization languageForStoredValue:@"DE"] == WKAppLanguageGerman, @"a hand-edited DE still reads as German");
    CHECK([WKLocalization languageForStoredValue:@"en"] == WKAppLanguageEnglish, @"en reads back as English");
    CHECK([WKLocalization languageForStoredValue:@"system"] == WKAppLanguageSystem, @"system reads back as system");
    // An installation that predates the setting, and a value nobody wrote.
    CHECK([WKLocalization languageForStoredValue:nil] == WKAppLanguageSystem, @"a missing value follows the iPad");
    CHECK([WKLocalization languageForStoredValue:@7] == WKAppLanguageSystem, @"a number follows the iPad");
    CHECK([WKLocalization languageForStoredValue:@"fr"] == WKAppLanguageFrench, @"fr reads back as French");
    CHECK([WKLocalization languageForStoredValue:@"it"] == WKAppLanguageSystem, @"an invented language follows the iPad");
    CHECK([[WKLocalization choices] count] == 4, @"four choices: English, French, German, System Default");
}

static void TestTables(void) {
    // The shipped tables: all three complete, and a key answered in each.
    [WKLocalization setPreferredLanguagesForTesting:@[@"en-US"]];
    [WKLocalization setResourceBundleForTesting:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:WKAppLanguageDefaultsKey];
    WKLocalization.shared.language = WKAppLanguageEnglish;
    CHECK([WKLocalized(@"home.action.play") isEqual:@"Play"], @"English says Play");
    CHECK([WKLocalization.shared.languageCode isEqual:@"en"], @"the resolved code is en");
    CHECK([WKLocalized(@"home.action.changed") isEqual:@"Changed"], @"a key in no table reads as its own name, never as the key");
    CHECK(![WKLocalized(@"home.action.changed") containsString:@"."], @"a fallback is never a dotted key");
    CHECK([WKLocalized(@"") isEqual:@""], @"an empty key is an empty string");

    WKLocalization.shared.language = WKAppLanguageGerman;
    CHECK([WKLocalized(@"home.action.play") isEqual:@"Spielen"], @"German says Spielen");
    CHECK([WKLocalization.shared.languageCode isEqual:@"de"], @"the resolved code is de");
    CHECK([WKLocalized(@"home.status.ready") isEqual:@"Bereit zum Spielen"], @"a status line is German");
    CHECK([WKLocalized(@"voice.mapping.notSet") isEqual:@"Nicht belegt"], @"an accessibility string is German");

    WKLocalization.shared.language = WKAppLanguageFrench;
    CHECK([WKLocalized(@"home.action.play") isEqual:@"Jouer"], @"French says Jouer");
    CHECK([WKLocalization.shared.languageCode isEqual:@"fr"], @"the resolved code is fr");
    CHECK([WKLocalized(@"home.status.ready") isEqual:@"Prêt à jouer"], @"a status line is French");
    CHECK([WKLocalized(@"voice.mapping.notSet") isEqual:@"Non défini"], @"an accessibility string is French");

    // A table that is genuinely incomplete: the German one is missing a key, so English answers.
    NSBundle *partial = MakeBundle(@{@"en": @{@"test.only": @"English only", @"test.both": @"Both"},
                                     @"de": @{@"test.both": @"Beide"}});
    [WKLocalization setResourceBundleForTesting:partial];
    WKLocalization.shared.language = WKAppLanguageGerman;
    CHECK([WKLocalized(@"test.both") isEqual:@"Beide"], @"a complete key is German");
    CHECK([WKLocalized(@"test.only") isEqual:@"English only"], @"a key missing from German falls back to English");
    [WKLocalization setResourceBundleForTesting:nil];
}

static void TestFormatting(void) {
    WKLocalization.shared.language = WKAppLanguageGerman;
    // Conversions come from the table, so a language can reorder them.
    NSString *gpu = WKLocalizedFormat(@"overlay.gpu", 12.5, 62.0, 3.25);
    CHECK([gpu containsString:@"12,5"] || [gpu containsString:@"12.5"], @"a format is applied, not printed");
    // A literal per-cent in a translated string is a per-cent, so what must not survive is a
    // conversion - not the character itself.
    CHECK(![gpu containsString:@"%@"] && ![gpu containsString:@"%."], @"no conversion is left over");
    CHECK([gpu containsString:@"62"], @"the second argument lands");
    // A literal per-cent survives a translation that spaces it.
    NSString *battery = WKLocalizedFormat(@"overlay.battery", 85, WKLocalized(@"overlay.battery.charging"));
    CHECK([battery containsString:@"85"], @"the battery percentage lands");
    CHECK([battery containsString:@"Lädt"], @"the charging word is German");
    // Plurals: zero, one and other, and a language that needs only two forms.
    CHECK([WKLocalizedCountFormat(@"addons.count", 0, 0) isEqual:@"0 Add-ons installiert"],
          @"zero takes the other form in German");
    CHECK([WKLocalizedCountFormat(@"addons.count", 3, 3) isEqual:@"3 Add-ons installiert"],
          @"three takes the other form");
    CHECK(([WKLocalizedCountFormat(@"addons.count", 1, 1) isEqual:@"1 Add-on installiert"]),
          @"a German count of one says Add-on, not Add-ons");
    CHECK(([WKLocalizedCountFormat(@"addons.count", 2, 2) isEqual:@"2 Add-ons installiert"]),
          @"a German count of two says Add-ons");
    WKLocalization.shared.language = WKAppLanguageEnglish;
    CHECK(([WKLocalizedCountFormat(@"addons.count", 1, 1) isEqual:@"1 add-on installed"]), @"English singular");
    CHECK(([WKLocalizedCountFormat(@"addons.count", 2, 2) isEqual:@"2 add-ons installed"]), @"English plural");
    // Dates and numbers are formatted in the app's language, not the iPad's.
    NSDateFormatter *clock = [NSDateFormatter new];
    clock.locale = WKLocalization.shared.locale;
    clock.dateStyle = NSDateFormatterNoStyle; clock.timeStyle = NSDateFormatterShortStyle;
    CHECK(clock.locale.localeIdentifier.length > 0, @"a locale exists for formatting");
    WKLocalization.shared.language = WKAppLanguageGerman;
    CHECK([WKLocalization.shared.locale.localeIdentifier hasPrefix:@"de"], @"the German locale is German");
    WKLocalization.shared.language = WKAppLanguageEnglish;
    CHECK([WKLocalization.shared.locale.localeIdentifier hasPrefix:@"en"], @"the English locale is English");
}

// The render-profile confirmation: device-neutral words for what a choice above the default costs,
// plus a sentence for what was measured, only where a record measured it. No language may carry the
// old line that claimed a measured miss on every device.
static void TestRenderConfirmation(void) {
    [WKLocalization setResourceBundleForTesting:nil];
    NSArray *keys = @[@"home.render.confirm.quality", @"home.render.confirm.balanced",
                      @"home.render.confirm.finding.missedBudget", @"home.render.confirm.finding.graphicsWork"];
    NSMutableDictionary<NSString *, NSString *> *english = [NSMutableDictionary dictionary];
    for (NSNumber *language in @[@(WKAppLanguageEnglish), @(WKAppLanguageGerman), @(WKAppLanguageFrench)]) {
        WKLocalization.shared.language = language.integerValue;
        NSString *code = WKLocalization.shared.languageCode;
        for (NSString *key in keys) {
            NSString *text = WKLocalized(key);
            CHECK(text.length > 20 && ![text containsString:@"home.render"],
                  ([NSString stringWithFormat:@"%@ answers %@", code, key]));
            if (language.integerValue == WKAppLanguageEnglish) english[key] = text;
            else CHECK(![text isEqual:english[key]], ([NSString stringWithFormat:@"%@ translates %@", code, key]));
        }
        NSString *quality = WKLocalizedFormat(@"home.render.confirm.quality", @"2420 × 1668", @"iPad Pro 11-inch (M5)");
        CHECK([quality containsString:@"2420 × 1668"] && [quality containsString:@"iPad Pro 11-inch (M5)"],
              ([NSString stringWithFormat:@"%@: the Quality line carries the size and the device", code]));
        CHECK(![quality containsString:@"%"], ([NSString stringWithFormat:@"%@: no conversion is left over", code]));
        NSString *balanced = WKLocalizedFormat(@"home.render.confirm.balanced", @"1210 × 834", @"iPad Pro 11-inch (M5)");
        CHECK([balanced containsString:@"1210 × 834"] && [balanced containsString:@"iPad Pro 11-inch (M5)"],
              ([NSString stringWithFormat:@"%@: the Balanced line carries the size and the device", code]));
    }
    WKLocalization.shared.language = WKAppLanguageEnglish;
    CHECK([WKLocalizedFormat(@"home.render.confirm.quality", @"2420 × 1668", @"iPad Pro 11-inch (M5)") isEqual:
           @"Quality draws the 3D world at the screen's full resolution, 2420 × 1668 on iPad Pro 11-inch (M5), and takes much more graphics work than this profile's default. Lowering the game's own Render Scale brings that back down."],
          @"the English Quality line, word for word");
    CHECK(![WKLocalized(@"home.render.confirm.quality") containsString:@"frame budget"],
          @"the device-neutral line claims no measurement");
    CHECK([WKLocalized(@"home.render.confirm.finding.missedBudget") containsString:@"frame budget"],
          @"the 12.9-inch M1's measured miss is kept, as its own sentence");
    CHECK([WKLocalized(@"home.render.confirm.finding.graphicsWork") containsString:@"2.5 times"],
          @"the 11-inch M5's measurement is its own sentence");
    // The old one-size line is gone from every table rather than left behind unused.
    CHECK([WKLocalized(@"home.render.confirm.message") isEqual:@"Message"], @"the old line is no longer in the table");
}

static unsigned changes = 0;
static WKAppLanguage lastNew = WKAppLanguageSystem, lastOld = WKAppLanguageSystem;
static void OnChange(NSNotification *note) {
    changes++;
    lastNew = [note.userInfo[WKLocalizationNewLanguageKey] integerValue];
    lastOld = [note.userInfo[WKLocalizationOldLanguageKey] integerValue];
}

static void TestChangeNotification(void) {
    WKLocalization.shared.language = WKAppLanguageEnglish;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:WKLocalizationDidChangeNotification
                                                             object:nil queue:nil
                                                         usingBlock:^(NSNotification *note) { OnChange(note); }];
    changes = 0;
    WKLocalization.shared.language = WKAppLanguageGerman;
    CHECK(changes == 1, @"a change is announced once");
    CHECK(lastOld == WKAppLanguageEnglish && lastNew == WKAppLanguageGerman, @"the announcement names both languages");
    WKLocalization.shared.language = WKAppLanguageGerman;
    CHECK(changes == 1, @"setting the same language again announces nothing");
    // A change made behind the class's back - the config file's import at launch - is announced too.
    [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:WKAppLanguageDefaultsKey];
    CHECK(changes == 2, @"a value written to the defaults is announced");
    CHECK(lastNew == WKAppLanguageEnglish, @"and it says which language arrived");
    [NSNotificationCenter.defaultCenter removeObserver:token];
}

int main(void) {
    @autoreleasepool {
        // A clean slate: the defaults database of whatever ran last is a real one.
        [NSUserDefaults.standardUserDefaults removeObjectForKey:WKAppLanguageDefaultsKey];
        TestResolution();
        TestStoredValues();
        TestTables();
        TestFormatting();
        TestRenderConfirmation();
        TestChangeNotification();
    }
    if (failures) {
        printf("localization FAIL: %d of %d checks\n", failures, checks);
        return 1;
    }
    printf("localization PASS: %d checks (resolution, stored values, tables, fallback, formatting, plurals, render confirmation, change notice)\n", checks);
    return 0;
}
