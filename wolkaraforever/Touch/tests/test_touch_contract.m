// Reads TouchPlay's button list (contract v1): parsing, the file's place in the game folder,
// the rectangles and the key codes. Foundation and CoreGraphics only: no UI, no guest.
//
//   test_touch_contract <fixtures folder>
//
// The fixtures are the contract as the iPad wrote it (TouchPlay-v1.lua, saved on the device on
// a device check), the same file from a newer TouchPlay (TouchPlay-v2.lua, "TPC2"), and the v1 file
// cut in the middle (TouchPlay-broken.lua). The game folder on the iPad is
// Documents/World of Warcraft/_forever_ (profile "wow-forever", workingDirectory), and the
// account-wide file is WTF/Account/<ACCOUNT>/SavedVariables/TouchPlay.lua in it; the tests build
// that layout in a temporary folder.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "InterfaceMode.h"
#import "TouchContract.h"
#include <unistd.h>

static int checks = 0, failures = 0;
// The message is a printf-style format with Objective-C object conversions (%@) allowed.
#define CHECK(condition, ...) do { checks++; if (!(condition)) { failures++; \
    fprintf(stderr, "FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString alloc] initWithFormat:@__VA_ARGS__].UTF8String); } } while (0)

static NSString *gFixtures;
static NSString *Fixture(NSString *name) {
    return [NSString stringWithContentsOfFile:[gFixtures stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
}

static NSString *NewGameFolder(void) {
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"touch-contract-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    return folder;
}

/// Writes `text` to <game>/<relative>, with the given modification time.
static void WriteFile(NSString *game, NSString *relative, NSString *text, NSDate *modified) {
    NSString *path = [game stringByAppendingPathComponent:relative];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    if (modified) [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: modified} ofItemAtPath:path error:NULL];
}

static NSString *ContractLine(NSString *body) {
    return [NSString stringWithFormat:@"\nTouchPlayDB = {\n[\"enabled\"] = true,\n[\"contract\"] = \"%@\",\n}\n", body];
}

static const NSUInteger kControl = 1 << 18, kOption = 1 << 19, kShift = 1 << 17;

static void parse_v1(void) {
    AKTouchContract *c = AKTouchContractParse(Fixture(@"TouchPlay-v1.lua"));
    CHECK(c != nil, "the iPad's own file parses");
    if (!c) return;
    CHECK(c.version == 1, "version %ld", (long)c.version);
    CHECK(c.holdSeconds == 0.45, "hold %f", c.holdSeconds);
    CHECK(!c.leftHanded, "hand R");
    CHECK(c.turnWithView, "turn=1");
    CHECK([c.worldKey isEqualToString:@"CTRL-ALT-SHIFT-F1"], "world %@", c.worldKey);
    CHECK(c.areas.count == 26, "areas %lu", (unsigned long)c.areas.count);
    AKTouchArea *spell1 = [c areaNamed:@"spell1"];
    CHECK(spell1 != nil, "spell1");
    if (spell1) {
        CHECK([spell1.name isEqualToString:@"spell1"] && [spell1.anchor isEqualToString:@"BR"], "name/anchor");
        CHECK(spell1.dx == 54 && spell1.dy == 68 && spell1.w == 88 && spell1.h == 88, "geometry %ld,%ld,%ld,%ld", (long)spell1.dx, (long)spell1.dy, (long)spell1.w, (long)spell1.h);
        CHECK([spell1.tapKey isEqualToString:@"CTRL-ALT-SHIFT-F2"], "tap %@", spell1.tapKey);
        CHECK([spell1.holdKey isEqualToString:@"CTRL-ALT-SHIFT-D"], "hold %@", spell1.holdKey);
        CHECK(spell1.pressKey.length == 0, "press empty, got '%@'", spell1.pressKey);
    }
    AKTouchArea *jump = [c areaNamed:@"jump"];
    CHECK([jump.pressKey isEqualToString:@"CTRL-ALT-SHIFT-R"], "jump press %@", jump.pressKey);
    CHECK(jump.tapKey.length == 0 && jump.holdKey.length == 0, "jump has press only");
    CHECK([[c areaNamed:@"dive"].pressKey isEqualToString:@"CTRL-ALT-SHIFT-S"], "dive is the last area and keeps its key");
    CHECK([[c areaNamed:@"chat"].anchor isEqualToString:@"BL"] && [[c areaNamed:@"minimap"].anchor isEqualToString:@"TR"] && [[c areaNamed:@"player"].anchor isEqualToString:@"TL"], "anchors");
    // Every name the add-on plan lists is present, once.
    NSMutableSet *names = [NSMutableSet set];
    for (AKTouchArea *a in c.areas) [names addObject:a.name];
    CHECK(names.count == 26, "26 distinct names, got %lu", (unsigned long)names.count);
    CHECK(c.edgeRun, "edgeRun defaults to YES when the file has no feel table");
    // The file carries keys this reader does not care about (enabled, softInteractOld, guideDone, layout).
    CHECK([Fixture(@"TouchPlay-v1.lua") containsString:@"guideDone"] && [Fixture(@"TouchPlay-v1.lua") containsString:@"softInteractOld"], "fixture is the real file");
}

static void parse_fields(void) {
    NSString *areas = @"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,CTRL-ALT-SHIFT-D,";
    AKTouchContract *c = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.6;hand=L;turn=0;world=CTRL-ALT-SHIFT-F5;areas=%@", areas]));
    CHECK(c != nil && c.holdSeconds == 0.6 && c.leftHanded && !c.turnWithView && [c.worldKey isEqualToString:@"CTRL-ALT-SHIFT-F5"] && c.areas.count == 1, "hand L, turn 0, hold 0.6");
    // A newer field this build does not know is ignored, not an error.
    c = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;future=7;world=CTRL-ALT-SHIFT-F1;areas=%@", areas]));
    CHECK(c != nil && c.areas.count == 1, "unknown field ignored");
    CHECK(!c.sheetPulses, "S13 absent sheet field defaults off");
    for (NSString *value in @[@"2", @"3", @""]) {
        AKTouchContract *sheet = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=%@;sheet=%@", areas, value]));
        CHECK(sheet != nil && sheet.areas.count == 1 && [sheet.worldKey isEqualToString:@"CTRL-ALT-SHIFT-F1"], "S13 sheet field preserves contract: %@", value);
        CHECK(sheet.sheetPulses == [value isEqualToString:@"2"], "S13 sheet=%@ opt-in only for 2", value);
    }
}

// The press outline (a device check, a player: the gold outline round the quest list's area when the list is empty and the
// add-on ignores the tap): the optional `outline=` field names the areas whose press the app outlines - the ones the
// add-on always draws something in. An older add-on does not write it: every area is outlined, as before. An older
// app ignores the field (any unknown field is), so the add-on may write it whatever app reads it.
static void outline_list(void) {
    NSString *areas = @"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,|quest,TR,10,300,200,300,CTRL-ALT-SHIFT-F7,,|jump,BR,200,40,80,80,,,CTRL-ALT-SHIFT-R";
    AKTouchContract *old = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=%@", areas]));
    CHECK(old != nil && old.outlineAreas == nil, "no outline field: nil (every area)");
    CHECK([old outlinesArea:@"spell1"] && [old outlinesArea:@"quest"] && [old outlinesArea:@"jump"], "no outline field: every area is outlined");
    AKTouchContract *listed = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;outline=spell1,jump;areas=%@", areas]));
    CHECK(listed != nil && listed.areas.count == 3, "the field does not change the areas");
    CHECK([listed outlinesArea:@"spell1"] && [listed outlinesArea:@"jump"], "listed areas are outlined");
    CHECK(![listed outlinesArea:@"quest"], "an area left out is never outlined");
    CHECK(![listed.signature isEqualToString:old.signature], "a changed list is a changed contract");
    // At the end of the line too, and with a name this build has no area for (ignored, not an error).
    AKTouchContract *last = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=%@;outline=quest,pet7", areas]));
    CHECK(last != nil && [last outlinesArea:@"quest"] && ![last outlinesArea:@"spell1"] && ![last outlinesArea:@"jump"], "outline after the areas; unknown name ignored");
    // Empty: the add-on draws its own feedback everywhere; the app outlines nothing.
    AKTouchContract *none = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;outline=;areas=%@", areas]));
    CHECK(none != nil && none.outlineAreas.count == 0 && ![none outlinesArea:@"spell1"] && ![none outlinesArea:@"quest"], "outline= with nothing: no outline at all");
    // Spaces or an empty name between commas are not names.
    AKTouchContract *spaced = AKTouchContractParse(ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;outline=spell1,,jump,;areas=%@", areas]));
    CHECK(spaced != nil && spaced.outlineAreas.count == 2 && [spaced outlinesArea:@"jump"] && ![spaced outlinesArea:@""], "empty names dropped");
}

static void unknown_version_plain_taps(void) {
    CHECK(AKTouchContractParse(Fixture(@"TouchPlay-v2.lua")) == nil, "TPC2 is not read");
    CHECK(AKTouchContractParse(ContractLine(@"TPC10;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "TPC10 is not version 1");
    CHECK(AKTouchContractParse(ContractLine(@"TPC0;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "TPC0");
    CHECK(AKTouchContractParse(ContractLine(@"XYZ1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "not a contract");
}

static void broken_file_plain_taps(void) {
    NSString *cut = Fixture(@"TouchPlay-broken.lua");
    CHECK(cut.length > 200 && [cut containsString:@"TPC1;"], "the broken fixture is the v1 file cut short");
    CHECK(AKTouchContractParse(cut) == nil, "a file cut in the middle is not read");
    CHECK(AKTouchContractParse(nil) == nil && AKTouchContractParse(@"") == nil, "nothing");
    CHECK(AKTouchContractParse(@"TouchPlayDB = {\n[\"enabled\"] = true,\n}\n") == nil, "a file with no contract line");
    NSString *ok = @"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=";
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,CTRL-ALT-SHIFT-D"])) == nil, "an area with 8 fields");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,,"])) == nil, "an area with 10 fields");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@"spell1,XX,54,68,88,88,CTRL-ALT-SHIFT-F2,,"])) == nil, "an unknown anchor");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@"spell1,BR,5x,68,88,88,CTRL-ALT-SHIFT-F2,,"])) == nil, "a number that is not one");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@"spell1,BR,54,68,0,88,CTRL-ALT-SHIFT-F2,,"])) == nil, "an area with no width");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@",BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,"])) == nil, "an area with no name");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@""])) == nil, "no areas at all");
    CHECK(AKTouchContractParse(ContractLine([ok stringByAppendingString:@"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,|"])) == nil, "an empty area");
    CHECK(AKTouchContractParse(ContractLine(@"TPC1;hold=0.45;hand=R;turn=1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "no world key");
    CHECK(AKTouchContractParse(ContractLine(@"TPC1;hold=abc;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "hold that is not a number");
    CHECK(AKTouchContractParse(ContractLine(@"TPC1;hold=0.45;hand=X;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "hand that is neither L nor R");
    CHECK(AKTouchContractParse(ContractLine(@"TPC1;hold=0.45;hand=R;turn=2;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,")) == nil, "turn that is neither 0 nor 1");
    // Whatever bytes arrive, nothing crashes.
    NSMutableString *junk = [NSMutableString string];
    for (int i = 0; i < 20000; i++) [junk appendString:@"[\"contract\"] = \"TPC1;;;|||,,,"];
    CHECK(AKTouchContractParse(junk) == nil, "junk");
}

static void missing_file_plain_taps(void) {
    NSString *game = NewGameFolder();
    NSURL *url = [NSURL fileURLWithPath:game];
    CHECK(AKTouchContractFilePath(url) == nil, "an empty game folder has no file");
    CHECK(AKTouchContractFilePath(nil) == nil, "no folder");
    CHECK(AKTouchContractFilePath([NSURL fileURLWithPath:@"/nonexistent/touch"]) == nil, "a folder that is not there");
    __block int notices = 0; __block NSString *shown = nil;
    AKTouchContractReset();
    AKTouchContract *c = AKTouchContractLoadForGame(url, ^(NSString *key) { notices++; shown = key; });
    CHECK(c == nil && notices == 1, "missing file: plain taps and one notice (%d)", notices);
    CHECK([shown isEqualToString:@"touch.contract.missing"], "notice key %@", shown);
    CHECK(AKTouchContractEdgeRun(), "no contract: edgeRun YES");
    // A WTF folder with an account but no file, and a character's file only.
    WriteFile(game, @"WTF/Account/FixtureAccount/93/Fixture-Character/SavedVariables/TouchPlay.lua", ContractLine(@"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,"), nil);
    CHECK(AKTouchContractFilePath(url) == nil, "a character's own file is never the contract source");
    notices = 0;
    CHECK(AKTouchContractLoadForGame(url, ^(NSString *key) { notices++; }) == nil && notices == 1, "per-character file only: still plain taps, one notice");
    [NSFileManager.defaultManager removeItemAtPath:game error:NULL];
}

static void unusable_files_show_the_notice_once(void) {
    NSDictionary<NSString *, NSString *> *cases = @{@"v2": @"TouchPlay-v2.lua", @"broken": @"TouchPlay-broken.lua"};
    for (NSString *label in cases) {
        NSString *game = NewGameFolder();
        WriteFile(game, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", Fixture(cases[label]), nil);
        __block int notices = 0;
        AKTouchContract *c = AKTouchContractLoadForGame([NSURL fileURLWithPath:game], ^(NSString *key) { notices++; });
        CHECK(c == nil && notices == 1, "%@: plain taps and one notice (%d)", label, notices);
        [NSFileManager.defaultManager removeItemAtPath:game error:NULL];
    }
    // A good file: no notice, and it is the current contract.
    NSString *game = NewGameFolder();
    WriteFile(game, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", Fixture(@"TouchPlay-v1.lua"), nil);
    __block int notices = 0;
    AKTouchContract *c = AKTouchContractLoadForGame([NSURL fileURLWithPath:game], ^(NSString *key) { notices++; });
    CHECK(c != nil && notices == 0, "a good file shows no notice");
    CHECK(c.areas.count == 26, "good file loaded through the folder");
    [NSFileManager.defaultManager removeItemAtPath:game error:NULL];
    // A game start with no notice block is fine.
    CHECK(AKTouchContractLoadForGame([NSURL fileURLWithPath:@"/nonexistent/touch"], nil) == nil, "no block");
}

static void rect_br_at_1366(void) {
    AKTouchContract *c = AKTouchContractParse(Fixture(@"TouchPlay-v1.lua"));
    CGRect r = AKTouchAreaRect([c areaNamed:@"spell1"], CGSizeMake(1366, 1024));
    CHECK(r.origin.x == 1224 && r.origin.y == 868 && r.size.width == 88 && r.size.height == 88, "spell1 at 1366x1024 = (%.2f, %.2f, %.2f, %.2f)", r.origin.x, r.origin.y, r.size.width, r.size.height);
}

static void rects_follow_size(void) {
    AKTouchContract *c = AKTouchContractParse(Fixture(@"TouchPlay-v1.lua"));
    CGSize size = CGSizeMake(1194, 834);
    CGFloat u = size.height / 1024.0;
    CHECK(fabs(u - 0.8145) < 0.0001, "u = %f", u);
    CGRect r = AKTouchAreaRect([c areaNamed:@"spell1"], size);
    CHECK(fabs(r.origin.x - (1194 - 142 * u)) < 0.5 && fabs(r.origin.y - (834 - 156 * u)) < 0.5 && fabs(r.size.width - 88 * u) < 0.5 && fabs(r.size.height - 88 * u) < 0.5,
          "spell1 at 1194x834 = (%.2f, %.2f, %.2f, %.2f)", r.origin.x, r.origin.y, r.size.width, r.size.height);
    // The other three anchors, at the iPad's size and at a smaller one.
    for (NSValue *v in @[[NSValue valueWithCGSize:CGSizeMake(1366, 1024)], [NSValue valueWithCGSize:size]]) {
        CGSize s = v.CGSizeValue; CGFloat k = s.height / 1024.0;
        CGRect tl = AKTouchAreaRect([c areaNamed:@"player"], s);   // TL,10,8,348,150
        CHECK(fabs(tl.origin.x - 10 * k) < 0.01 && fabs(tl.origin.y - 8 * k) < 0.01 && fabs(tl.size.width - 348 * k) < 0.01 && fabs(tl.size.height - 150 * k) < 0.01, "TL at %.0fx%.0f", s.width, s.height);
        CGRect tr = AKTouchAreaRect([c areaNamed:@"item1"], s);    // TR,18,300,48,48
        CHECK(fabs(tr.origin.x - (s.width - (18 + 48) * k)) < 0.01 && fabs(tr.origin.y - 300 * k) < 0.01 && fabs(tr.size.width - 48 * k) < 0.01, "TR at %.0fx%.0f", s.width, s.height);
        CGRect bl = AKTouchAreaRect([c areaNamed:@"chat"], s);     // BL,296,24,568,52
        CHECK(fabs(bl.origin.x - 296 * k) < 0.01 && fabs(bl.origin.y - (s.height - (24 + 52) * k)) < 0.01 && fabs(bl.size.width - 568 * k) < 0.01 && fabs(bl.size.height - 52 * k) < 0.01, "BL at %.0fx%.0f", s.width, s.height);
    }
    CHECK(CGRectIsEmpty(AKTouchAreaRect(nil, size)), "no area, no rectangle");
    CHECK(CGRectIsEmpty(AKTouchAreaRect([c areaNamed:@"spell1"], CGSizeZero)), "no size, no rectangle");
}

static void key_codes(void) {
    uint16_t code = 999; NSUInteger mods = 0;
    CHECK(AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-F2", &code, &mods) && code == 120 && mods == (kControl | kOption | kShift), "F2 -> %u mods %lx", code, (unsigned long)mods);
    CHECK(AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-0", &code, &mods) && code == 29 && mods == (kControl | kOption | kShift), "0 -> %u", code);
    code = 999;
    CHECK(!AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-F20", &code, &mods) && code == 999, "F20 is not a TouchPlay key and leaves the output alone");
    // The whole table, from the plan's constraint (Carbon kVK_*, checked against HIToolbox/Events.h).
    NSDictionary<NSString *, NSNumber *> *table = @{
        @"F1": @122, @"F2": @120, @"F3": @99, @"F4": @118, @"F5": @96, @"F6": @97, @"F7": @98, @"F8": @100, @"F9": @101, @"F10": @109, @"F11": @103, @"F12": @111,
        @"1": @18, @"2": @19, @"3": @20, @"4": @21, @"5": @23, @"6": @22, @"7": @26, @"8": @28, @"9": @25, @"0": @29,
        @"A": @0, @"B": @11, @"C": @8, @"D": @2, @"E": @14, @"F": @3, @"G": @5, @"H": @4, @"I": @34, @"J": @38, @"K": @40, @"L": @37, @"M": @46,
        @"N": @45, @"O": @31, @"P": @35, @"Q": @12, @"R": @15, @"S": @1, @"T": @17, @"U": @32, @"V": @9, @"W": @13, @"X": @7, @"Y": @16, @"Z": @6};
    CHECK(table.count == 48, "table has %lu entries", (unsigned long)table.count);
    for (NSString *name in table) {
        BOOL ok = AKTouchKeyCodeForName([@"CTRL-ALT-SHIFT-" stringByAppendingString:name], &code, &mods);
        CHECK(ok && code == table[name].unsignedShortValue && mods == (kControl | kOption | kShift), "%@ -> %u, want %@", name, code, table[name]);
    }
    // The game's own order (ALT-CTRL-SHIFT-, Blizzard_SharedXML KeyCommand.lua: "MUST BE IN THIS ORDER (ALT, CTRL,
    // SHIFT, META)") is the one the game looks a binding up by; the add-on binds that. Every order of the three is the
    // same key and the same chord.
    for (NSString *prefix in @[@"ALT-CTRL-SHIFT-", @"CTRL-ALT-SHIFT-", @"SHIFT-ALT-CTRL-", @"ALT-SHIFT-CTRL-", @"CTRL-SHIFT-ALT-", @"SHIFT-CTRL-ALT-"]) {
        for (NSString *name in table) {
            code = 999; mods = 0;
            BOOL ok = AKTouchKeyCodeForName([prefix stringByAppendingString:name], &code, &mods);
            CHECK(ok && code == table[name].unsignedShortValue && mods == (kControl | kOption | kShift), "%@%@ -> %u, want %@", prefix, name, code, table[name]);
        }
    }
    // The 22 keys the pet and stance areas need beyond F1..F12, 0..9 and A..Z (Carbon kVK_ANSI_Keypad*, kVK_F13..F19).
    NSDictionary<NSString *, NSNumber *> *extra = @{
        @"NUMPAD0": @82, @"NUMPAD1": @83, @"NUMPAD2": @84, @"NUMPAD3": @85, @"NUMPAD4": @86, @"NUMPAD5": @87, @"NUMPAD6": @88,
        @"NUMPAD7": @89, @"NUMPAD8": @91, @"NUMPAD9": @92, @"NUMPADDECIMAL": @65, @"NUMPADMULTIPLY": @67, @"NUMPADPLUS": @69,
        @"NUMPADDIVIDE": @75, @"NUMPADMINUS": @78,
        @"F13": @105, @"F14": @107, @"F15": @113, @"F16": @106, @"F17": @64, @"F18": @79, @"F19": @80};
    CHECK(extra.count == 22, "extra table has %lu entries", (unsigned long)extra.count);
    NSMutableSet<NSNumber *> *codes = [NSMutableSet setWithArray:table.allValues];
    for (NSString *prefix in @[@"ALT-CTRL-SHIFT-", @"CTRL-ALT-SHIFT-", @"SHIFT-ALT-CTRL-", @"ALT-SHIFT-CTRL-", @"CTRL-SHIFT-ALT-", @"SHIFT-CTRL-ALT-"]) {
        for (NSString *name in extra) {
            code = 999; mods = 0;
            BOOL ok = AKTouchKeyCodeForName([prefix stringByAppendingString:name], &code, &mods);
            CHECK(ok && code == extra[name].unsignedShortValue && mods == (kControl | kOption | kShift), "%@%@ -> %u, want %@", prefix, name, code, extra[name]);
        }
    }
    for (NSString *name in extra) {
        CHECK(![codes containsObject:extra[name]], "%@ (%@) shares a code with an older key", name, extra[name]);
        [codes addObject:extra[name]];
        // All three modifiers are still required: none, one, or two of them is no key.
        for (NSString *prefix in @[@"", @"ALT-", @"CTRL-", @"SHIFT-", @"ALT-CTRL-", @"ALT-SHIFT-", @"CTRL-SHIFT-"]) {
            code = 999;
            CHECK(!AKTouchKeyCodeForName([prefix stringByAppendingString:name], &code, &mods) && code == 999, "%@%@ lacks a modifier", prefix, name);
        }
        CHECK(!AKTouchKeyCodeForName([@"ALT-CTRL-SHIFT-META-" stringByAppendingString:name], &code, &mods), "META and %@", name);
        CHECK(!AKTouchKeyCodeForName([@"ALT-CTRL-SHIFT-" stringByAppendingString:name.lowercaseString], &code, &mods), "lower-case %@", name);
    }
    CHECK(codes.count == 70, "70 distinct key codes in all: %lu", (unsigned long)codes.count);
    // Names next to the new ones stay unknown, and none of the new codes is a walk key's (W 13, A 0, S 1, D 2).
    for (NSString *name in @[@"NUMPAD", @"NUMPAD10", @"NUMPADENTER", @"NUMPADEQUALS", @"NUMPADCLEAR", @"F0", @"F20", @"F24", @"F013", @"NUMPADPLUS-1"]) {
        code = 999;
        CHECK(!AKTouchKeyCodeForName([@"ALT-CTRL-SHIFT-" stringByAppendingString:name], &code, &mods) && code == 999, "%@ is no key", name);
    }
    for (NSNumber *walk in @[@13, @0, @1, @2]) CHECK(![extra.allValues containsObject:walk], "a new key sits on walk code %@", walk);
    // The reader still parses the walk keys' names (W is in the table); TouchAreas refuses them as walk keys.
    CHECK(AKTouchKeyCodeForName(@"ALT-CTRL-SHIFT-W", &code, NULL) && code == 13, "W still parses; TouchAreas refuses it");
    // All three modifiers, each once, and nothing the chord path cannot hold.
    CHECK(!AKTouchKeyCodeForName(@"F2", &code, &mods), "no prefix");
    CHECK(!AKTouchKeyCodeForName(@"CTRL-F2", &code, &mods), "partial prefix");
    CHECK(!AKTouchKeyCodeForName(@"ALT-CTRL-F2", &code, &mods), "two of the three");
    CHECK(!AKTouchKeyCodeForName(@"ALT-ALT-CTRL-SHIFT-F2", &code, &mods), "a modifier twice");
    CHECK(!AKTouchKeyCodeForName(@"ALT-CTRL-CTRL-F2", &code, &mods), "a modifier twice instead of SHIFT");
    CHECK(!AKTouchKeyCodeForName(@"META-ALT-CTRL-SHIFT-F2", &code, &mods) && !AKTouchKeyCodeForName(@"ALT-CTRL-SHIFT-META-F2", &code, &mods), "META (Command) is not a TouchPlay modifier");
    CHECK(!AKTouchKeyCodeForName(@"alt-ctrl-shift-F2", &code, &mods), "lower-case modifiers");
    CHECK(!AKTouchKeyCodeForName(@"ALT-CTRL-SHIFT-F2-", &code, &mods) && !AKTouchKeyCodeForName(@"-ALT-CTRL-SHIFT-F2", &code, &mods), "a stray dash");
    CHECK(!AKTouchKeyCodeForName(@"ALT--CTRL-SHIFT-F2", &code, &mods), "an empty token");
    CHECK(!AKTouchKeyCodeForName(@"ALT-CTRL-SHIFT-H-J", &code, &mods), "two keys");
    CHECK(!AKTouchKeyCodeForName(@"ALT-CTRL-SHIFT", &code, &mods) && !AKTouchKeyCodeForName(@"ALT-CTRL-SHIFT-SHIFT", &code, &mods), "modifiers and no key");
    CHECK(!AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-f2", &code, &mods), "lower case");
    CHECK(!AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-", &code, &mods), "no key");
    CHECK(!AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-F2 ", &code, &mods), "trailing space");
    CHECK(!AKTouchKeyCodeForName(@"", &code, &mods) && !AKTouchKeyCodeForName(nil, &code, &mods), "empty and nil");
    CHECK(AKTouchKeyCodeForName(@"CTRL-ALT-SHIFT-F2", NULL, NULL), "outputs are optional");
    // Every key in the real contract resolves.
    AKTouchContract *c = AKTouchContractParse(Fixture(@"TouchPlay-v1.lua"));
    int keys = 0;
    for (AKTouchArea *a in c.areas) for (NSString *k in @[a.tapKey, a.holdKey, a.pressKey]) if (k.length) { keys++; CHECK(AKTouchKeyCodeForName(k, NULL, NULL), "%@ of %@", k, a.name); }
    CHECK(AKTouchKeyCodeForName(c.worldKey, NULL, NULL), "world key");
    CHECK(keys == 40, "keys in the file: %d", keys);
}

/// The add-on's key set bound in the game's order (ALT-CTRL-SHIFT-): every area, the world key too, gets the same
/// key code and chord as the same file in TouchPlay's old order (CTRL-ALT-SHIFT-), so the iPad plays it unchanged.
static void game_order_contract_matches(void) {
    AKTouchContract *game = AKTouchContractParse(Fixture(@"TouchPlay-v1-altorder.lua"));
    AKTouchContract *old = AKTouchContractParse(Fixture(@"TouchPlay-v1-a22.lua"));
    CHECK(game != nil && old != nil && game.areas.count == 26 && old.areas.count == 26, "both files parse: %lu / %lu areas", (unsigned long)game.areas.count, (unsigned long)old.areas.count);
    CHECK([game.worldKey hasPrefix:@"ALT-CTRL-SHIFT-"], "the world key is in the game's order: %@", game.worldKey);
    int keys = 0;
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"(world)"];
    NSMutableArray<NSString *> *gameKeys = [NSMutableArray arrayWithObject:game.worldKey ?: @""];
    NSMutableArray<NSString *> *oldKeys = [NSMutableArray arrayWithObject:old.worldKey ?: @""];
    for (NSUInteger i = 0; i < MIN(game.areas.count, old.areas.count); i++) {
        AKTouchArea *g = game.areas[i], *o = old.areas[i];
        CHECK([g.name isEqualToString:o.name], "area %lu: %@ / %@", (unsigned long)i, g.name, o.name);
        [names addObjectsFromArray:@[g.name, g.name, g.name]];
        [gameKeys addObjectsFromArray:@[g.tapKey, g.holdKey, g.pressKey]];
        [oldKeys addObjectsFromArray:@[o.tapKey, o.holdKey, o.pressKey]];
    }
    for (NSUInteger i = 0; i < gameKeys.count; i++) {
        if (!oldKeys[i].length) { CHECK(!gameKeys[i].length, "%@: no key in either file", names[i]); continue; }
        uint16_t gc = 999, oc = 998; NSUInteger gm = 0, om = 1;
        BOOL gok = AKTouchKeyCodeForName(gameKeys[i], &gc, &gm), ook = AKTouchKeyCodeForName(oldKeys[i], &oc, &om);
        CHECK(gok && ook && gc == oc && gm == om && gm == (kControl | kOption | kShift), "%@: %@ -> %u/%lx, %@ -> %u/%lx", names[i], gameKeys[i], gc, (unsigned long)gm, oldKeys[i], oc, (unsigned long)om);
        keys++;
    }
    CHECK(keys >= 30, "keys compared: %d", keys);
}

static void newest_account_wins(void) {
    NSString *game = NewGameFolder();
    NSDate *now = NSDate.date;
    NSString *(^contract)(NSString *) = ^(NSString *world) {
        return ContractLine([NSString stringWithFormat:@"TPC1;hold=0.45;hand=R;turn=1;world=%@;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,", world]);
    };
    // The account that sorts last by name is the older one, so only the modification time can decide.
    WriteFile(game, @"WTF/Account/ZZZ-OLD/SavedVariables/TouchPlay.lua", contract(@"CTRL-ALT-SHIFT-F1"), [now dateByAddingTimeInterval:-3600]);
    WriteFile(game, @"WTF/Account/AAA-NEW/SavedVariables/TouchPlay.lua", contract(@"CTRL-ALT-SHIFT-F5"), [now dateByAddingTimeInterval:-60]);
    // A character's file, newer still, must not win.
    WriteFile(game, @"WTF/Account/ZZZ-OLD/93/Fixture-Character/SavedVariables/TouchPlay.lua", contract(@"CTRL-ALT-SHIFT-F9"), now);
    // Something else under WTF/Account that is not an account folder.
    WriteFile(game, @"WTF/Account/readme.txt", @"x", now);
    NSString *path = AKTouchContractFilePath([NSURL fileURLWithPath:game]);
    CHECK([path hasSuffix:@"WTF/Account/AAA-NEW/SavedVariables/TouchPlay.lua"], "newest file: %@", path);
    AKTouchContractReset();
    AKTouchContract *c = AKTouchContractLoadForGame([NSURL fileURLWithPath:game], nil);
    CHECK([c.worldKey isEqualToString:@"CTRL-ALT-SHIFT-F5"], "the newer account's contract is used: %@", c.worldKey);
    // Swap the times: now the other one is newer.
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [now dateByAddingTimeInterval:10]} ofItemAtPath:[game stringByAppendingPathComponent:@"WTF/Account/ZZZ-OLD/SavedVariables/TouchPlay.lua"] error:NULL];
    c = AKTouchContractLoadForGame([NSURL fileURLWithPath:game], nil);
    CHECK([c.worldKey isEqualToString:@"CTRL-ALT-SHIFT-F1"], "after a touch of the older file: %@", c.worldKey);
    [NSFileManager.defaultManager removeItemAtPath:game error:NULL];
}

static void edge_run(void) {
    NSString *areas = @"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,";
    NSString *base = ContractLine(areas);
    CHECK(AKTouchContractParse(base).edgeRun, "absent: YES");
    NSString *off = [base stringByAppendingString:@"TouchPlayFeel = {\n}\nTouchPlayDB2 = {\n[\"feel\"] = {\n[\"scale\"] = 1,\n[\"edgeRun\"] = false,\n[\"x\"] = {\n[\"y\"] = 1,\n},\n},\n}\n"];
    CHECK(!AKTouchContractParse(off).edgeRun, "feel.edgeRun = false: NO");
    NSString *on = [base stringByAppendingString:@"X = {\n[\"feel\"] = {\n[\"edgeRun\"] = true,\n},\n}\n"];
    CHECK(AKTouchContractParse(on).edgeRun, "feel.edgeRun = true: YES");
    NSString *nested = [base stringByAppendingString:@"X = {\n[\"feel\"] = {\n[\"deep\"] = {\n[\"a\"] = 1,\n},\n[\"edgeRun\"] = false,\n},\n}\n"];
    CHECK(!AKTouchContractParse(nested).edgeRun, "edgeRun after a nested table inside feel");
    // An edgeRun outside the feel table is not the setting.
    NSString *stray = [base stringByAppendingString:@"X = {\n[\"edgeRun\"] = false,\n[\"feel\"] = {\n[\"scale\"] = 1,\n},\n[\"other\"] = {\n[\"edgeRun\"] = false,\n},\n}\n"];
    CHECK(AKTouchContractParse(stray).edgeRun, "edgeRun outside feel is ignored");
    NSString *feelFirst = [@"X = {\n[\"feel\"] = {\n[\"edgeRun\"] = false,\n},\n}\n" stringByAppendingString:base];
    CHECK(!AKTouchContractParse(feelFirst).edgeRun, "feel table before the contract line");
    // Braces inside a string are text, not table structure, and do not move the depth.
    NSString *braceString = [base stringByAppendingString:@"X = {\n[\"feel\"] = {\n[\"note\"] = \"a } b\",\n[\"edgeRun\"] = false,\n},\n}\n"];
    CHECK(!AKTouchContractParse(braceString).edgeRun, "a } inside a string before edgeRun");
    NSString *openString = [base stringByAppendingString:@"X = {\n[\"feel\"] = {\n[\"note\"] = \"{{ \\\" {\",\n[\"edgeRun\"] = false,\n},\n}\n"];
    CHECK(!AKTouchContractParse(openString).edgeRun, "{ and an escaped quote inside a string before edgeRun");
    NSString *decoy = [base stringByAppendingString:@"X = {\n[\"feel\"] = {\n[\"note\"] = \"} [\\\"edgeRun\\\"] = false\",\n},\n}\n"];
    CHECK(AKTouchContractParse(decoy).edgeRun, "an edgeRun written inside a string value is not the setting");
    // The C function reads the current contract, which exists in iPad touch mode only.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:AKInterfaceModeDefaultsKey];
    NSString *game = NewGameFolder();
    WriteFile(game, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", off, nil);
    [defaults setObject:@"ipadtouch" forKey:AKInterfaceModeDefaultsKey];
    AKTouchContractLoadForGame([NSURL fileURLWithPath:game], nil);
    CHECK(!AKTouchContractEdgeRun(), "AKTouchContractEdgeRun follows the loaded file");
    [defaults setObject:@"ipados" forKey:AKInterfaceModeDefaultsKey];
    CHECK(AKTouchContractEdgeRun(), "outside iPad touch it is the default, YES");
    [defaults setObject:@"ipadtouch" forKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    chdir("/");
    CHECK(AKTouchContractEdgeRun(), "and is YES with nothing to load");
    if (saved) [defaults setObject:saved forKey:AKInterfaceModeDefaultsKey]; else [defaults removeObjectForKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    [NSFileManager.defaultManager removeItemAtPath:game error:NULL];
}

static void current_contract_follows_the_mode(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:AKInterfaceModeDefaultsKey];
    NSString *game = NewGameFolder();
    WriteFile(game, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", Fixture(@"TouchPlay-v1.lua"), nil);
    NSString *previous = NSFileManager.defaultManager.currentDirectoryPath;
    // The guest's working directory is the game folder; the adapter reads it from there.
    CHECK(chdir(game.fileSystemRepresentation) == 0, "chdir");
    for (NSString *mode in @[@"ipados", @"ios", @"iosduo", @"auto"]) {
        [defaults setObject:mode forKey:AKInterfaceModeDefaultsKey];
        AKTouchContractReset();
        CHECK(AKTouchCurrentContract() == nil, "mode %@: no contract is loaded", mode);
    }
    [defaults setObject:@"ipadtouch" forKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    AKTouchContract *c = AKTouchCurrentContract();
    CHECK(c != nil && c.areas.count == 26, "iPad touch: read lazily from the working directory");
    CHECK(AKTouchCurrentContract() == c, "and kept: the same object the second time");
    // A load for a game start replaces it.
    NSString *other = NewGameFolder();
    WriteFile(other, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", ContractLine(@"TPC1;hold=0.45;hand=L;turn=1;world=CTRL-ALT-SHIFT-F1;areas=spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,,"), nil);
    AKTouchContractLoadForGame([NSURL fileURLWithPath:other], nil);
    CHECK(AKTouchCurrentContract().leftHanded && AKTouchCurrentContract().areas.count == 1, "the load for this game start is the current one");
    // A game start with none: nil, not the previous game's.
    AKTouchContractLoadForGame([NSURL fileURLWithPath:@"/nonexistent/touch"], nil);
    CHECK(AKTouchCurrentContract() == nil, "none this time means none, not the last one");
    // The mode going away (the stored value changes) turns it off again.
    AKTouchContractLoadForGame([NSURL fileURLWithPath:game], nil);
    CHECK(AKTouchCurrentContract() != nil, "loaded");
    [defaults setObject:@"ipados" forKey:AKInterfaceModeDefaultsKey];
    CHECK(AKTouchCurrentContract() == nil, "outside iPad touch the current contract is nil even if one was loaded");
    chdir(previous.fileSystemRepresentation);
    if (saved) [defaults setObject:saved forKey:AKInterfaceModeDefaultsKey]; else [defaults removeObjectForKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    [NSFileManager.defaultManager removeItemAtPath:game error:NULL];
    [NSFileManager.defaultManager removeItemAtPath:other error:NULL];
}

static BOOL WaitFor(BOOL (^done)(void), NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [end timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

/// The game replaces SavedVariables files rather than writing into them; so do these.
static void ReplaceFile(NSString *game, NSString *text) {
    WriteFile(game, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", text, nil);
}

static NSString *V1With(NSString *from, NSString *to) {
    return [Fixture(@"TouchPlay-v1.lua") stringByReplacingOccurrencesOfString:from withString:to];
}

static void lazy_read_before_chdir(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:AKInterfaceModeDefaultsKey];
    [defaults setObject:@"ipadtouch" forKey:AKInterfaceModeDefaultsKey];
    NSString *game = NewGameFolder(), *elsewhere = NewGameFolder();
    WriteFile(game, @"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua", Fixture(@"TouchPlay-v1.lua"), nil);
    NSString *previous = NSFileManager.defaultManager.currentDirectoryPath;
    AKTouchContractReset();
    // Asked before the guest has changed into the game folder: nothing to read, and not an answer
    // for the rest of the session.
    CHECK(chdir(elsewhere.fileSystemRepresentation) == 0, "chdir");
    CHECK(AKTouchCurrentContract() == nil, "no WTF here: no contract");
    CHECK(AKTouchCurrentContract() == nil, "and still none the second time");
    CHECK(chdir(game.fileSystemRepresentation) == 0, "chdir");
    AKTouchContract *c = AKTouchCurrentContract();
    CHECK(c != nil && c.areas.count == 26, "once in the game folder the contract is read (the earlier nil was not cached)");
    // A game folder that has WTF but no file is an answer: asked once, nil, kept.
    NSString *empty = NewGameFolder();
    [NSFileManager.defaultManager createDirectoryAtPath:[empty stringByAppendingPathComponent:@"WTF/Account"] withIntermediateDirectories:YES attributes:nil error:NULL];
    AKTouchContractReset();
    CHECK(chdir(empty.fileSystemRepresentation) == 0, "chdir");
    CHECK(AKTouchCurrentContract() == nil, "WTF/Account without a file: no contract");
    chdir(previous.fileSystemRepresentation);
    if (saved) [defaults setObject:saved forKey:AKInterfaceModeDefaultsKey]; else [defaults removeObjectForKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    for (NSString *folder in @[game, elsewhere, empty]) [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
}

static void contract_changes_are_picked_up(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:AKInterfaceModeDefaultsKey];
    [defaults setObject:@"ipadtouch" forKey:AKInterfaceModeDefaultsKey];
    NSString *game = NewGameFolder();
    NSURL *url = [NSURL fileURLWithPath:game];
    __block int changes = 0;
    __block AKTouchContract *announced = nil;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKTouchContractDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        changes++; announced = n.object;
    }];
    AKTouchContractReset();
    ReplaceFile(game, Fixture(@"TouchPlay-v1.lua"));
    CHECK(AKTouchContractLoadForGame(url, nil).holdSeconds == 0.45, "v1 loaded");
    AKTouchContractWatch(url);

    // Saved with a different hold time: the contract changes.
    ReplaceFile(game, V1With(@"hold=0.45", @"hold=0.6"));
    CHECK(WaitFor(^BOOL { return AKTouchCurrentContract().holdSeconds == 0.6; }, 5), "a replaced file with hold=0.6 gives the new contract");
    CHECK(changes == 1 && announced.holdSeconds == 0.6, "one notification, carrying the new contract (%d)", changes);

    // The same contract written again is not a change.
    ReplaceFile(game, V1With(@"hold=0.45", @"hold=0.6"));
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    CHECK(changes == 1, "the same contract again: no second notification (%d)", changes);

    // A cut file and a newer version: the last good contract stays, nothing is announced.
    ReplaceFile(game, Fixture(@"TouchPlay-broken.lua"));
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    CHECK(AKTouchCurrentContract().holdSeconds == 0.6 && changes == 1, "a broken file keeps the previous contract");
    ReplaceFile(game, Fixture(@"TouchPlay-v2.lua"));
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    CHECK(AKTouchCurrentContract().holdSeconds == 0.6 && changes == 1, "a TPC2 file keeps the previous contract");

    // The watch survived the replacements: a good file after the bad ones is picked up.
    ReplaceFile(game, V1With(@"hold=0.45", @"hold=0.7"));
    CHECK(WaitFor(^BOOL { return AKTouchCurrentContract().holdSeconds == 0.7; }, 5), "the watch was re-armed: hold=0.7 is picked up after the broken ones");
    CHECK(changes == 2, "two changes in all (%d)", changes);

    // Deleted: the last good contract stays; written again: picked up.
    [NSFileManager.defaultManager removeItemAtPath:[game stringByAppendingPathComponent:@"WTF/Account/FixtureAccount/SavedVariables/TouchPlay.lua"] error:NULL];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    CHECK(AKTouchCurrentContract().holdSeconds == 0.7 && changes == 2, "a deleted file keeps the previous contract");
    ReplaceFile(game, V1With(@"hold=0.45", @"hold=0.8"));
    CHECK(WaitFor(^BOOL { return AKTouchCurrentContract().holdSeconds == 0.8; }, 5), "written again after a delete: hold=0.8");
    // The contract is swapped before its notification reaches the main queue: let that arrive here,
    // or it lands in the count below (a 1-in-6 flake on 13 Nov).
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    // Outside iPad touch mode nothing is watched.
    [defaults setObject:@"ipados" forKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    changes = 0;
    AKTouchContractWatch(url);
    ReplaceFile(game, V1With(@"hold=0.45", @"hold=0.9"));
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    CHECK(changes == 0, "not in iPad touch mode: no watch, no notification (%d)", changes);
    [defaults setObject:@"ipadtouch" forKey:AKInterfaceModeDefaultsKey];
    CHECK(AKTouchContractLoadForGame(url, nil).holdSeconds == 0.9 && changes == 0, "a load stays quiet");

    // The file did not exist when the game started (the player has not saved yet): it appears later.
    NSString *fresh = NewGameFolder();
    NSURL *freshURL = [NSURL fileURLWithPath:fresh];
    [NSFileManager.defaultManager createDirectoryAtPath:[fresh stringByAppendingPathComponent:@"WTF/Account"] withIntermediateDirectories:YES attributes:nil error:NULL];
    AKTouchContractReset();
    changes = 0;
    CHECK(AKTouchContractLoadForGame(freshURL, nil) == nil, "no file yet");
    AKTouchContractWatch(freshURL);
    ReplaceFile(fresh, Fixture(@"TouchPlay-v1.lua"));
    CHECK(WaitFor(^BOOL { return AKTouchCurrentContract().areas.count == 26; }, 5) && changes == 1, "a file that appears later is picked up (%d)", changes);

    // Reset stops the watch.
    AKTouchContractReset();
    changes = 0;
    ReplaceFile(fresh, V1With(@"hold=0.45", @"hold=0.5"));
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    CHECK(changes == 0, "after a reset the old folder is not watched (%d)", changes);

    [NSNotificationCenter.defaultCenter removeObserver:observer];
    if (saved) [defaults setObject:saved forKey:AKInterfaceModeDefaultsKey]; else [defaults removeObjectForKey:AKInterfaceModeDefaultsKey];
    AKTouchContractReset();
    for (NSString *folder in @[game, fresh]) [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: test_touch_contract <fixtures folder>\n"); return 2; }
        gFixtures = [NSString stringWithUTF8String:argv[1]];
        CHECK(Fixture(@"TouchPlay-v1.lua") != nil && Fixture(@"TouchPlay-v2.lua") != nil && Fixture(@"TouchPlay-broken.lua") != nil, "fixtures found in %@", gFixtures);
        void (*tests[])(void) = {parse_v1, parse_fields, unknown_version_plain_taps, broken_file_plain_taps, missing_file_plain_taps,
            unusable_files_show_the_notice_once, rect_br_at_1366, rects_follow_size, key_codes, game_order_contract_matches, newest_account_wins, edge_run,
            current_contract_follows_the_mode, lazy_read_before_chdir, contract_changes_are_picked_up, outline_list};
        const char *names[] = {"parse_v1", "parse_fields", "unknown_version_plain_taps", "broken_file_plain_taps", "missing_file_plain_taps",
            "unusable_files_show_the_notice_once", "rect_br_at_1366", "rects_follow_size", "key_codes", "game_order_contract_matches", "newest_account_wins", "edge_run",
            "current_contract_follows_the_mode", "lazy_read_before_chdir", "contract_changes_are_picked_up", "outline_list"};
        for (size_t i = 0; i < sizeof tests / sizeof *tests; i++) {
            int before = failures;
            tests[i]();
            printf("%s %s\n", failures == before ? "PASS" : "FAIL", names[i]);
        }
        printf("TOUCH_CONTRACT_%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
        return failures ? 1 : 0;
    }
}
