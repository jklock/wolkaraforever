#import "TouchContract.h"
#import "InterfaceMode.h"
#include <math.h>
#include <fcntl.h>
#include <unistd.h>

NSString *const AKTouchContractMissingNoticeKey = @"touch.contract.missing";
NSNotificationName const AKTouchContractDidChangeNotification = @"AKTouchContractDidChangeNotification";

/// The modifiers every TouchPlay key carries: control, option and shift (the NSEventModifierFlags
/// bit values, which this file cannot import: the app has no AppKit).
static const NSUInteger kModifierShift = 1 << 17, kModifierControl = 1 << 18, kModifierOption = 1 << 19;

@implementation AKTouchArea
@end

@implementation AKTouchContract
- (AKTouchArea *)areaNamed:(NSString *)name {
    for (AKTouchArea *area in self.areas) if ([area.name isEqualToString:name]) return area;
    return nil;
}
- (BOOL)outlinesArea:(NSString *)name {
    NSSet<NSString *> *listed = self.outlineAreas;
    return listed ? (name.length > 0 && [listed containsObject:name]) : YES;
}
@end

#pragma mark Parsing

/// An integer written with digits only (and an optional leading minus): "5x", "", " 5" are not.
static BOOL AKStrictInteger(NSString *text, NSInteger *value) {
    if (text.length == 0 || text.length > 9) return NO;
    NSUInteger start = [text hasPrefix:@"-"] ? 1 : 0;
    if (start == text.length) return NO;
    for (NSUInteger i = start; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    *value = text.integerValue;
    return YES;
}

static BOOL AKStrictDecimal(NSString *text, double *value) {
    if (text.length == 0 || text.length > 12) return NO;
    BOOL dot = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '.' && !dot && i > 0 && i + 1 < text.length) dot = YES;
        else if (c < '0' || c > '9') return NO;
    }
    *value = text.doubleValue;
    return isfinite(*value);
}

static AKTouchArea *AKParseArea(NSString *text) {
    NSArray<NSString *> *fields = [text componentsSeparatedByString:@","];
    if (fields.count != 9) return nil;
    if (fields[0].length == 0) return nil;
    if (![@[@"TL", @"TR", @"BL", @"BR"] containsObject:fields[1]]) return nil;
    NSInteger numbers[4];
    for (int i = 0; i < 4; i++) if (!AKStrictInteger(fields[2 + i], &numbers[i])) return nil;
    if (numbers[2] <= 0 || numbers[3] <= 0) return nil;
    AKTouchArea *area = [AKTouchArea new];
    area.name = fields[0];
    area.anchor = fields[1];
    area.dx = numbers[0]; area.dy = numbers[1]; area.w = numbers[2]; area.h = numbers[3];
    area.tapKey = fields[6]; area.holdKey = fields[7]; area.pressKey = fields[8];
    return area;
}

/// The text of the Lua table that starts at the `{` at `open` (braces inside strings do not count).
static NSString *AKLuaTableBody(NSString *text, NSUInteger open) {
    NSInteger depth = 0;
    BOOL inString = NO;
    for (NSUInteger i = open; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (inString) {
            if (c == '\\') i++;
            else if (c == '"') inString = NO;
        } else if (c == '"') inString = YES;
        else if (c == '{') depth++;
        else if (c == '}' && --depth == 0) return [text substringWithRange:NSMakeRange(open, i - open + 1)];
    }
    return nil;
}

/// ["feel"]["edgeRun"] (the input path's run-to-the-edge switch): the first `["feel"] = {` table that sets
/// it, and YES when the file does not say.
static BOOL AKParseEdgeRun(NSString *fileText) {
    NSRegularExpression *feel = [NSRegularExpression regularExpressionWithPattern:@"\\[\"feel\"\\]\\s*=\\s*\\{" options:0 error:NULL];
    NSRegularExpression *edge = [NSRegularExpression regularExpressionWithPattern:@"\\[\"edgeRun\"\\]\\s*=\\s*(true|false)\\b" options:0 error:NULL];
    for (NSTextCheckingResult *match in [feel matchesInString:fileText options:0 range:NSMakeRange(0, fileText.length)]) {
        NSString *body = AKLuaTableBody(fileText, match.range.location + match.range.length - 1);
        if (!body) continue;
        // Only a setting of the feel table itself, not of a table nested inside it. Braces inside a
        // string are text; the text itself is kept at the table's own depth, where the key is.
        NSMutableString *flat = [NSMutableString string];
        NSInteger depth = 0;
        BOOL inString = NO;
        for (NSUInteger i = 0; i < body.length; i++) {
            unichar c = [body characterAtIndex:i];
            if (inString) {
                if (depth == 1) [flat appendFormat:@"%C", c];
                if (c == '\\' && i + 1 < body.length) {
                    i++;
                    if (depth == 1) [flat appendFormat:@"%C", [body characterAtIndex:i]];
                } else if (c == '"') inString = NO;
                continue;
            }
            if (c == '"') inString = YES;
            else if (c == '{') { depth++; continue; }
            else if (c == '}') { depth--; continue; }
            if (depth == 1) [flat appendFormat:@"%C", c];
        }
        NSTextCheckingResult *found = [edge firstMatchInString:flat options:0 range:NSMakeRange(0, flat.length)];
        if (found) return [[flat substringWithRange:[found rangeAtIndex:1]] isEqualToString:@"true"];
    }
    return YES;
}

AKTouchContract *AKTouchContractParse(NSString *fileText) {
    if (![fileText isKindOfClass:NSString.class] || fileText.length == 0) return nil;
    static NSRegularExpression *line;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        line = [NSRegularExpression regularExpressionWithPattern:@"\\[\"contract\"\\]\\s*=\\s*\"([^\"]*)\"" options:0 error:NULL];
    });
    NSTextCheckingResult *match = [line firstMatchInString:fileText options:0 range:NSMakeRange(0, fileText.length)];
    if (!match) return nil;
    NSString *value = [fileText substringWithRange:[match rangeAtIndex:1]];

    NSArray<NSString *> *parts = [value componentsSeparatedByString:@";"];
    if (![parts.firstObject isEqualToString:@"TPC1"]) return nil;   // only version 1, exactly
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < parts.count; i++) {
        NSRange equals = [parts[i] rangeOfString:@"="];
        if (equals.location == NSNotFound || equals.location == 0) return nil;
        fields[[parts[i] substringToIndex:equals.location]] = [parts[i] substringFromIndex:equals.location + 1];
    }
    double hold = 0;
    if (!AKStrictDecimal(fields[@"hold"], &hold) || hold <= 0 || hold > 10) return nil;
    NSString *hand = fields[@"hand"];
    if (![hand isEqualToString:@"L"] && ![hand isEqualToString:@"R"]) return nil;
    NSString *turn = fields[@"turn"];
    if (![turn isEqualToString:@"0"] && ![turn isEqualToString:@"1"]) return nil;
    NSString *world = fields[@"world"];
    NSString *areasText = fields[@"areas"];
    if (world.length == 0 || areasText.length == 0) return nil;

    NSMutableArray<AKTouchArea *> *areas = [NSMutableArray array];
    for (NSString *text in [areasText componentsSeparatedByString:@"|"]) {
        AKTouchArea *area = AKParseArea(text);
        if (!area) return nil;   // one bad area and the whole line is not trusted
        [areas addObject:area];
    }

    AKTouchContract *contract = [AKTouchContract new];
    contract.version = 1;
    contract.holdSeconds = hold;
    contract.leftHanded = [hand isEqualToString:@"L"];
    contract.turnWithView = [turn isEqualToString:@"1"];
    contract.sheetPulses = [fields[@"sheet"] isEqualToString:@"2"];
    contract.worldKey = world;
    contract.areas = areas;
    // Optional (a device check): the areas whose press the app outlines. Absent: every area (an add-on from before it).
    NSString *outline = fields[@"outline"];
    if (outline) {
        NSMutableSet<NSString *> *names = [NSMutableSet set];
        for (NSString *name in [outline componentsSeparatedByString:@","]) if (name.length) [names addObject:name];
        contract.outlineAreas = names;
    }
    contract.edgeRun = AKParseEdgeRun(fileText);
    contract.signature = [NSString stringWithFormat:@"%@|edgeRun=%d", value, contract.edgeRun];
    return contract;
}

#pragma mark Finding and loading the file

NSString *AKTouchContractFilePath(NSURL *gameFolder) {
    if (![gameFolder isKindOfClass:NSURL.class] || !gameFolder.isFileURL) return nil;
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *accounts = [gameFolder.path stringByAppendingPathComponent:@"WTF/Account"];
    NSArray<NSString *> *names = [[files contentsOfDirectoryAtPath:accounts error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    NSString *best = nil;
    NSDate *bestDate = nil;
    for (NSString *account in names) {
        // Exactly one level under the account: <ACCOUNT>/SavedVariables/TouchPlay.lua. A
        // character's own file is deeper and is not the contract.
        NSString *path = [[[accounts stringByAppendingPathComponent:account] stringByAppendingPathComponent:@"SavedVariables"] stringByAppendingPathComponent:@"TouchPlay.lua"];
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:NULL];
        if (![attributes.fileType isEqualToString:NSFileTypeRegular]) continue;
        NSDate *modified = attributes.fileModificationDate ?: NSDate.distantPast;
        if (!best || [modified compare:bestDate] == NSOrderedDescending) { best = path; bestDate = modified; }
    }
    return best;
}

static NSLock *AKContractLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    return lock;
}
static AKTouchContract *gContract;
static BOOL gLoaded;

/// The contract in the newest account's file of `gameFolder`, or nil.
static AKTouchContract *AKReadContract(NSURL *gameFolder) {
    NSString *path = AKTouchContractFilePath(gameFolder);
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    return AKTouchContractParse(text);
}

AKTouchContract *AKTouchContractLoadForGame(NSURL *gameFolder, void (^notice)(NSString *key)) {
    AKTouchContract *contract = AKReadContract(gameFolder);
    [AKContractLock() lock];
    gContract = contract;
    gLoaded = YES;
    [AKContractLock() unlock];
    if (!contract && notice) notice(AKTouchContractMissingNoticeKey);
    return contract;
}

#pragma mark Watching the file (the player's reload gives the app new buttons)

// The watch: vnode sources on the TouchPlay.lua files, their SavedVariables folders and WTF/Account.
// The game saves by replacing the file, which ends the old file's source (rename, delete), and a
// file that did not exist at game start appears as a change of its folder. So after every change
// all sources are made again from what is on disk, once the writes have settled.
static dispatch_queue_t gWatchQueue;       // serial; everything below is touched only on it
static NSMutableArray<dispatch_source_t> *gSources;
static NSURL *gWatchedFolder;
static NSUInteger gWatchToken;             // a debounce or a re-arm from before a newer watch is stale
static BOOL gChangePending;                // one re-read per burst of events

static void AKWatchStop(void) {
    for (dispatch_source_t source in gSources) dispatch_source_cancel(source);   // the cancel handler closes the descriptor
    gSources = nil;
}

static void AKWatchArm(void);

static void AKWatchChanged(NSUInteger token) {
    // The game writes a file in several steps, and the file and its folders each report it; read once,
    // when the burst is over.
    if (gChangePending) return;
    gChangePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), gWatchQueue, ^{
        gChangePending = NO;
        if (token != gWatchToken || !gWatchedFolder) return;
        AKWatchArm();
        if (!AKInterfaceModeIsTouchPlay()) return;
        AKTouchContract *contract = AKReadContract(gWatchedFolder);
        if (!contract) {
            NSLog(@"TouchContract: the changed TouchPlay.lua has no usable contract; keeping the last one");
            return;
        }
        [AKContractLock() lock];
        BOOL changed = !(gLoaded && gContract && [gContract.signature isEqualToString:contract.signature]);
        if (changed) { gContract = contract; gLoaded = YES; }
        [AKContractLock() unlock];
        if (!changed) return;
        NSLog(@"TouchContract: a new contract was saved (%lu areas, hold %.2f s)", (unsigned long)contract.areas.count, contract.holdSeconds);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:AKTouchContractDidChangeNotification object:contract];
        });
    });
}

static void AKWatchArm(void) {
    AKWatchStop();
    if (!gWatchedFolder) return;
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *accounts = [gWatchedFolder.path stringByAppendingPathComponent:@"WTF/Account"];
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:accounts];
    for (NSString *account in [files contentsOfDirectoryAtPath:accounts error:NULL]) {
        NSString *saved = [[accounts stringByAppendingPathComponent:account] stringByAppendingPathComponent:@"SavedVariables"];
        [paths addObject:saved];
        [paths addObject:[saved stringByAppendingPathComponent:@"TouchPlay.lua"]];
    }
    gSources = [NSMutableArray array];
    NSUInteger token = gWatchToken;
    for (NSString *path in paths) {
        int descriptor = open(path.fileSystemRepresentation, O_EVTONLY);
        if (descriptor < 0) continue;
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)descriptor,
            DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK, gWatchQueue);
        dispatch_source_set_event_handler(source, ^{ AKWatchChanged(token); });
        dispatch_source_set_cancel_handler(source, ^{ close(descriptor); });
        dispatch_resume(source);
        [gSources addObject:source];
    }
}

void AKTouchContractWatch(NSURL *gameFolder) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gWatchQueue = dispatch_queue_create("WolkaraForever.TouchContract.watch", DISPATCH_QUEUE_SERIAL); });
    if (!AKInterfaceModeIsTouchPlay() || ![gameFolder isKindOfClass:NSURL.class] || !gameFolder.isFileURL) return;
    NSURL *folder = [gameFolder copy];
    dispatch_sync(gWatchQueue, ^{
        gWatchToken++;
        gChangePending = NO;
        gWatchedFolder = folder;
        AKWatchArm();
    });
}

AKTouchContract *AKTouchCurrentContract(void) {
    if (!AKInterfaceModeIsTouchPlay()) return nil;
    [AKContractLock() lock];
    BOOL loaded = gLoaded;
    AKTouchContract *contract = gContract;
    [AKContractLock() unlock];
    if (loaded) return contract;
    // Nothing loaded it in this process (the adapter library is a different binary from the app):
    // the guest's working directory is the game folder. Asked before the guest has changed into
    // it, there is no WTF to read, and that is not an answer to remember: try again next time.
    char buffer[PATH_MAX];
    if (!getcwd(buffer, sizeof buffer)) return nil;
    NSURL *folder = [NSURL fileURLWithPath:[NSString stringWithUTF8String:buffer] isDirectory:YES];
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:[folder.path stringByAppendingPathComponent:@"WTF/Account"] isDirectory:&isDirectory] || !isDirectory) return nil;
    AKTouchContract *read = AKTouchContractLoadForGame(folder, nil);
    AKTouchContractWatch(folder);
    return read;
}

BOOL AKTouchContractEdgeRun(void) {
    AKTouchContract *contract = AKTouchCurrentContract();
    return contract ? contract.edgeRun : YES;
}

void AKTouchContractReset(void) {
    if (gWatchQueue) dispatch_sync(gWatchQueue, ^{
        gWatchToken++;
        gChangePending = NO;
        gWatchedFolder = nil;
        AKWatchStop();
    });
    [AKContractLock() lock];
    gContract = nil;
    gLoaded = NO;
    [AKContractLock() unlock];
}

#pragma mark Rectangles and keys

CGRect AKTouchAreaRect(AKTouchArea *area, CGSize viewSize) {
    if (!area || viewSize.width <= 0 || viewSize.height <= 0) return CGRectZero;
    CGFloat u = viewSize.height / 1024.0;
    CGFloat w = area.w * u, h = area.h * u;
    CGFloat x = [area.anchor hasSuffix:@"R"] ? viewSize.width - (area.dx + area.w) * u : area.dx * u;
    CGFloat y = [area.anchor hasPrefix:@"B"] ? viewSize.height - (area.dy + area.h) * u : area.dy * u;
    return CGRectMake(x, y, w, h);
}

/// macOS virtual key codes (Carbon kVK_*, HIToolbox/Events.h).
static NSDictionary<NSString *, NSNumber *> *AKTouchKeyTable(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"F1": @122, @"F2": @120, @"F3": @99, @"F4": @118, @"F5": @96, @"F6": @97, @"F7": @98, @"F8": @100,
            @"F9": @101, @"F10": @109, @"F11": @103, @"F12": @111,
            @"1": @18, @"2": @19, @"3": @20, @"4": @21, @"5": @23, @"6": @22, @"7": @26, @"8": @28, @"9": @25, @"0": @29,
            @"A": @0, @"B": @11, @"C": @8, @"D": @2, @"E": @14, @"F": @3, @"G": @5, @"H": @4, @"I": @34, @"J": @38,
            @"K": @40, @"L": @37, @"M": @46, @"N": @45, @"O": @31, @"P": @35, @"Q": @12, @"R": @15, @"S": @1, @"T": @17,
            @"U": @32, @"V": @9, @"W": @13, @"X": @7, @"Y": @16, @"Z": @6,
            // The keypad (kVK_ANSI_Keypad*) and F13..F19: the 22 more keys TouchPlay's pet, stance and Leave areas use.
            @"NUMPAD0": @82, @"NUMPAD1": @83, @"NUMPAD2": @84, @"NUMPAD3": @85, @"NUMPAD4": @86, @"NUMPAD5": @87,
            @"NUMPAD6": @88, @"NUMPAD7": @89, @"NUMPAD8": @91, @"NUMPAD9": @92, @"NUMPADDECIMAL": @65,
            @"NUMPADMULTIPLY": @67, @"NUMPADPLUS": @69, @"NUMPADDIVIDE": @75, @"NUMPADMINUS": @78,
            @"F13": @105, @"F14": @107, @"F15": @113, @"F16": @106, @"F17": @64, @"F18": @79, @"F19": @80,
        };
    });
    return table;
}

// A key name is dash-separated: ALT, CTRL and SHIFT, each exactly once and in any order, then the key. The game
// builds a chord as ALT-CTRL-SHIFT-<key> (Blizzard_SharedXML KeyCommand.lua: "MUST BE IN THIS ORDER (ALT, CTRL,
// SHIFT, META)") and looks its binding up by that string, so a binding made as CTRL-ALT-SHIFT-<key> is never found
// and the game falls back to the bare key's (the an iPad test symptom). TouchPlay now binds in the game's order;
// files written by older versions (CTRL-ALT-SHIFT-) still name the same chord. META (Command) is refused: the
// host's chord path holds only control, option and shift.
BOOL AKTouchKeyCodeForName(NSString *wowKey, uint16_t *code, NSUInteger *mods) {
    if (![wowKey isKindOfClass:NSString.class]) return NO;
    NSArray<NSString *> *tokens = [wowKey componentsSeparatedByString:@"-"];
    if (tokens.count != 4) return NO;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *token = tokens[i];
        if (![token isEqualToString:@"ALT"] && ![token isEqualToString:@"CTRL"] && ![token isEqualToString:@"SHIFT"]) return NO;
        if ([seen containsObject:token]) return NO;
        [seen addObject:token];
    }
    NSNumber *value = AKTouchKeyTable()[tokens[3]];
    if (!value) return NO;
    if (code) *code = value.unsignedShortValue;
    if (mods) *mods = kModifierControl | kModifierOption | kModifierShift;
    return YES;
}
