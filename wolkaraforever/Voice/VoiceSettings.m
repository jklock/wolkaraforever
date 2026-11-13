// WolkaraForever: the voice settings, in full.

#import "VoiceSettings.h"
#import "../App/WolkaraForeverLog.h"
#import "../Input/ControllerCommandIngress.h"
#import "../Input/InputElement.h"

NSNotificationName const AKVoiceSettingsDidChangeNotification = @"AKVoiceSettingsDidChange";

static NSString *const AKVoiceEnabledKey = @"AKVoiceEnabled";
static NSString *const AKVoiceModeKey = @"AKVoiceMode";
static NSString *const AKVoiceAutoSubmitKey = @"AKVoiceAutoSubmit";
static NSString *const AKVoiceTrailingSpaceKey = @"AKVoiceTrailingSpace";
static NSString *const AKVoiceCustomWordsKey = @"AKVoiceCustomWords";
static NSString *const AKVoiceTakeButtonKey = @"AKVoiceTakeButtonFromGame";
// One record per controller identity, holding the single canonical button that build claimed:
// `{ "<identity>": { "element": "controller.button.share", "claimed": true } }`. The shape the
// completion specification fixes, so a file written by either build means the same thing.
static NSString *const AKControllerClaimsKey = @"AKControllerClaims";
// What a record is keyed on when the caller has no device - the same "any controller" key a
// mapping uses, so a claim and a mapping can never disagree about which pad they mean.
static NSString *const AKControllerClaimAnyDevice = @"any";

// The dictionary is biased into the recogniser, so it is bounded: a huge list is not a
// dictionary, it is a corrupt file, and it would be handed to the SDK either way.
static NSUInteger const AKVoiceWordLimit = 512;
static NSUInteger const AKVoiceWordLengthLimit = 64;
// UIKeyboardHIDUsage's last case is keyboardRightGUI, 0xE7. Nothing above it is a key a
// keyboard can report, so this is the whole space of usages the adapter can ever ask about.
static NSUInteger const AKKeyboardUsageMaximum = 0xE7;

// NO. See the header for the measurement behind it: the guest is a second reader of the same pad
// and nothing this app can do to a button removes it from that reader.
static BOOL AKControllerClaimSeam = NO;

@interface AKVoiceSettings ()
// What is held back right now. Deliberately separate from the stored records: the records are the
// player's preference and outlive a launch, this is the set the app is actually honouring, and it
// is empty in a build with no seam.
@property (nonatomic, strong) NSMutableSet<NSString *> *activeClaims;
@end

@implementation AKVoiceSettings

+ (instancetype)shared {
    static AKVoiceSettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKVoiceSettings new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        // Off, and staying off, until the user turns it on. See the header.
        _enabled = [defaults boolForKey:AKVoiceEnabledKey];
        // Hold to talk unless the user says otherwise: it is what Handy defaults to,
        // and it fails safe - a stuck toggle leaves the microphone open.
        if ([defaults objectForKey:AKVoiceModeKey])
            _mode = (AKVoiceMode)[defaults integerForKey:AKVoiceModeKey];
        else
            _mode = AKVoiceModeHold;
        _autoSubmit = [defaults boolForKey:AKVoiceAutoSubmitKey];
        _trailingSpace = [defaults boolForKey:AKVoiceTrailingSpaceKey];
        _customWords = [self sanitizedWords:[defaults arrayForKey:AKVoiceCustomWordsKey] ?: @[]];
        // Off: a mapping listens to a button, and making the game stop seeing it is a
        // change to how the game behaves that the user has to ask for.
        _takeButtonFromGame = [defaults boolForKey:AKVoiceTakeButtonKey];
        // Nothing is held back at launch unless a build that can claim says so, and this build
        // cannot. The *records* are read, never invented: `isElement:claimedForDevice:` answers
        // from them, so a preference written by another build survives a launch here.
        _activeClaims = [NSMutableSet set];
        // One pass at startup: an older build wrote element names that are not ids.
        NSUInteger migrated = [AKTrigger migrateStoredTriggersInDefaults:defaults];
        if (migrated) WKLog("voice", @"migrated %lu stored mapping(s) to canonical element ids", (unsigned long)migrated);
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    BOOL changed = (_enabled != enabled);
    _enabled = enabled;
    // Turning the feature off gives every held-back button back, immediately: the gate says so and
    // a claim that outlived its feature would be an input the player could not recover except by
    // relaunching.
    if (changed && !enabled) [self releaseClaimsWithReason:@"disable"];
    [self persist:AKVoiceEnabledKey value:@(enabled)];
}
- (void)setMode:(AKVoiceMode)mode {
    _mode = mode;
    // The mode owns the pattern; see the header. Rewriting the stored patterns here
    // is what stops a mapping made in one mode behaving like the other one.
    [self applyModeToStoredMappings];
    [self persist:AKVoiceModeKey value:@(mode)];
}
- (void)setAutoSubmit:(BOOL)autoSubmit { _autoSubmit = autoSubmit; [self persist:AKVoiceAutoSubmitKey value:@(autoSubmit)]; }
- (void)setTakeButtonFromGame:(BOOL)takeButtonFromGame {
    _takeButtonFromGame = takeButtonFromGame;
    [self persist:AKVoiceTakeButtonKey value:@(takeButtonFromGame)];
}

// The one place that decides whether the guest is kept from seeing an input. Deliberately
// asked by *element* and not by device: the adapter sees a key press, not a controller, and
// the mapping is per device, so "any device has taken this" is the only question the
// adapter's position can answer.
- (BOOL)ownsElement:(NSString *)element {
    if (!_enabled || !_takeButtonFromGame) return NO;
    if (!element.length || AKInputElementIsSystem(element)) return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in defaults.dictionaryRepresentation.allKeys) {
        if (![key hasPrefix:@"AKInputTrigger."]) continue;
        AKTrigger *stored = [AKTrigger triggerFromStored:[defaults dictionaryForKey:key]];
        // A hand-written mapping could name a system element; nothing about a screenshot
        // can be swallowed, so it is refused here too rather than only on migration.
        if (!stored || AKInputElementIsSystem(stored.element)) continue;
        // The rule the router fires on, not a second one: exact, or a family. Only the exact
        // form matched before, so a mapping stored as "keyboard.key." fired the trigger for
        // every key and still let every one of them through to the game.
        if ([AKTrigger element:stored.element covers:element]) return YES;
    }
    return NO;
}

// The same decision in the form the adapter can use: it is about to post a key and knows the
// usage, not the element. One scan, for the shell to publish to the adapter as a set.
- (NSSet<NSNumber *> *)ownedKeyUsages {
    if (!_enabled || !_takeButtonFromGame) return [NSSet set];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableArray<AKTrigger *> *stored = [NSMutableArray array];
    for (NSString *key in defaults.dictionaryRepresentation.allKeys) {
        if (![key hasPrefix:@"AKInputTrigger."]) continue;
        AKTrigger *trigger = [AKTrigger triggerFromStored:[defaults dictionaryForKey:key]];
        if (trigger) [stored addObject:trigger];
    }
    // Asked one usage at a time, over every usage a keyboard can report, through the same
    // matching the router fires on. Building the answer by enumerating usages is what makes
    // a family mapping mean what it says: the old form only read a usage out of an element
    // that was already `keyboard.key.<n>`, so a family - which the trigger model accepts and
    // the router fires on - was accepted and inert. A mapping that is not a usage still
    // cannot become one, because every id considered here was built from a number.
    NSMutableSet<NSNumber *> *usages = [NSMutableSet set];
    for (NSUInteger usage = 0; usage <= AKKeyboardUsageMaximum; usage++) {
        NSString *element = AKInputElementForKeyboardKey((NSInteger)usage);
        for (AKTrigger *trigger in stored) {
            if ([AKTrigger element:trigger.element covers:element]) { [usages addObject:@(usage)]; break; }
        }
    }
    return usages;
}
- (void)setTrailingSpace:(BOOL)trailingSpace { _trailingSpace = trailingSpace; [self persist:AKVoiceTrailingSpaceKey value:@(trailingSpace)]; }
- (void)setCustomWords:(NSArray<NSString *> *)customWords {
    _customWords = [self sanitizedWords:customWords];
    [self persist:AKVoiceCustomWordsKey value:_customWords];
}

// Anything the recogniser is handed is bounded and stripped: empty entries dropped,
// nothing longer than the limit kept, and the whole list capped.
- (NSArray<NSString *> *)sanitizedWords:(NSArray *)words {
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id entry in words) {
        if (![entry isKindOfClass:NSString.class]) continue;
        NSString *word = [(NSString *)entry stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!word.length || word.length > AKVoiceWordLengthLimit) continue;
        if ([clean containsObject:word]) continue;
        [clean addObject:word];
        if (clean.count >= AKVoiceWordLimit) break;
    }
    return clean;
}

- (void)persist:(NSString *)key value:(id)value {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    WKLog("voice", @"%@ set", key);
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
}

#pragma mark - The button

- (nullable AKTrigger *)triggerForDevice:(nullable NSString *)device {
    // Off means nothing fires, whatever is stored. One gate, here, rather than a check
    // at every call site - and no fallback when nothing is stored, on purpose: the
    // audit's first release blocker was a feature that started listening because an
    // unrelated screenshot was taken.
    if (!_enabled) return nil;
    return [self storedTriggerForDevice:device];
}

// What is mapped, whether or not the feature is switched on: the settings screen has
// to be able to show the user what they chose while it is off.
- (nullable AKTrigger *)storedTriggerForDevice:(nullable NSString *)device {
    AKTrigger *trigger = [AKTrigger savedTriggerForDevice:device defaults:NSUserDefaults.standardUserDefaults];
    if (trigger) trigger.pattern = self.mode == AKVoiceModeHold ? AKTriggerPatternPushToTalk : AKTriggerPatternPress;
    return trigger;
}

- (void)setLearnedElement:(NSString *)element forDevice:(nullable NSString *)device {
    AKTrigger *trigger = [AKTrigger new];
    trigger.element = element;
    trigger.pattern = self.mode == AKVoiceModeHold ? AKTriggerPatternPushToTalk : AKTriggerPatternPress;
    [self setTrigger:trigger forDevice:device];
}

- (void)setTrigger:(AKTrigger *)trigger forDevice:(nullable NSString *)device {
    [trigger saveForDevice:device defaults:NSUserDefaults.standardUserDefaults];
    WKLog("voice", @"mapped %@ on %@", [trigger summary], device ?: @"any");
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
}

- (void)clearMappingForDevice:(nullable NSString *)device {
    [AKTrigger forgetTriggerForDevice:device defaults:NSUserDefaults.standardUserDefaults];
    WKLog("voice", @"mapping cleared for %@", device ?: @"any");
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
}

- (BOOL)adoptLegacyMappingForDevice:(NSString *)device vendor:(nullable NSString *)vendor {
    if (!device.length || !vendor.length) return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults dictionaryForKey:[AKTrigger defaultsKeyForDevice:device]] ) return NO;
    NSDictionary *legacy = [defaults dictionaryForKey:[NSString stringWithFormat:@"AKInputTrigger.%@", vendor]];
    if (![legacy isKindOfClass:NSDictionary.class]) return NO;
    AKTrigger *trigger = [AKTrigger triggerFromStored:legacy];
    if (!trigger) {
        [defaults removeObjectForKey:[NSString stringWithFormat:@"AKInputTrigger.%@", vendor]];
        return NO;
    }
    [trigger saveForDevice:device defaults:defaults];
    [defaults removeObjectForKey:[NSString stringWithFormat:@"AKInputTrigger.%@", vendor]];
    WKLog("voice", @"adopted the mapping made before this change (%@) for %@", [trigger summary], device);
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
    return YES;
}

// A mapping made in one mode must not keep the other mode's pattern.
- (void)applyModeToStoredMappings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    AKTriggerPattern wanted = self.mode == AKVoiceModeHold ? AKTriggerPatternPushToTalk : AKTriggerPatternPress;
    for (NSString *key in defaults.dictionaryRepresentation.allKeys) {
        if (![key hasPrefix:@"AKInputTrigger."]) continue;
        NSDictionary *stored = [defaults dictionaryForKey:key];
        AKTrigger *trigger = [AKTrigger triggerFromStored:stored];
        if (!trigger) continue;
        // Every supported mapping follows the selected mode.
        if (trigger.pattern == wanted) continue;
        trigger.pattern = wanted;
        [trigger saveForDevice:[key substringFromIndex:@"AKInputTrigger.".length] defaults:defaults];
    }
}

- (NSString *)mappingSummaryForDevice:(nullable NSString *)device {
    AKTrigger *saved = [self storedTriggerForDevice:device];
    if (!saved) return @"Not set";
    return [saved summary];
}

#pragma mark - Keeping one controller button out of the game

+ (BOOL)controllerClaimIsAvailable { return AKControllerClaimSeam; }
+ (void)setControllerClaimSeamAvailableForTesting:(BOOL)available { AKControllerClaimSeam = available; }

// The stored records, or none. Anything that is not a dictionary is treated as none rather than
// repaired: this is a preference, and inventing one is worse than starting from nothing.
- (NSDictionary *)claimRecords {
    id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:AKControllerClaimsKey];
    return [stored isKindOfClass:NSDictionary.class] ? stored : @{};
}

- (BOOL)isElement:(NSString *)element claimedForDevice:(nullable NSString *)device {
    if (!element.length) return NO;
    id record = self.claimRecords[device.length ? device : AKControllerClaimAnyDevice];
    if (![record isKindOfClass:NSDictionary.class]) return NO;
    id stored = ((NSDictionary *)record)[@"element"];
    if (![stored isKindOfClass:NSString.class] || ![stored isEqual:element]) return NO;
    return [((NSDictionary *)record)[@"claimed"] boolValue];
}

- (BOOL)claimElement:(NSString *)element device:(nullable NSString *)device {
    if (!element.length || ![element hasPrefix:@"controller.button."]) {
        [AKControllerCommandIngress trace:@"claim refused reason=not-a-button element=%@", element ?: @"?"];
        return NO;
    }
    if (!AKControllerClaimSeam) {
        // The answer this build ships with. Nothing is written: a record nothing applies would
        // leave the page describing a state the app is not in.
        [AKControllerCommandIngress trace:@"claim refused reason=no-route element=%@", element];
        return NO;
    }
    NSMutableDictionary *records = [NSMutableDictionary dictionaryWithDictionary:self.claimRecords];
    records[device.length ? device : AKControllerClaimAnyDevice] =
        @{ @"element": element, @"claimed": @YES };
    [NSUserDefaults.standardUserDefaults setObject:records forKey:AKControllerClaimsKey];
    [self.activeClaims addObject:element];
    [AKControllerCommandIngress trace:@"claim take element=%@", element];
    WKLog("voice", @"holding %@ back from the game", element);
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
    return YES;
}

- (void)releaseClaimForElement:(NSString *)element device:(nullable NSString *)device {
    if (!element.length) return;
    NSMutableDictionary *records = [NSMutableDictionary dictionaryWithDictionary:self.claimRecords];
    NSString *key = device.length ? device : AKControllerClaimAnyDevice;
    if ([records[key] isKindOfClass:NSDictionary.class]) {
        [records removeObjectForKey:key];
        [NSUserDefaults.standardUserDefaults setObject:records forKey:AKControllerClaimsKey];
    }
    if ([self.activeClaims containsObject:element]) {
        [self.activeClaims removeObject:element];
        [AKControllerCommandIngress trace:@"claim restore element=%@ reason=release", element];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
}

- (NSSet<NSString *> *)claimedElements { return self.activeClaims.copy ?: [NSSet set]; }

- (void)releaseClaimsWithReason:(NSString *)reason {
    if (!self.activeClaims.count) return;
    NSArray<NSString *> *held = self.activeClaims.allObjects;
    [self.activeClaims removeAllObjects];
    for (NSString *element in held) {
        // Written even with diagnostics off: giving a button back is the safe direction, and a log
        // that cannot say it happened is exactly how a stuck claim hides.
        [AKControllerCommandIngress trace:@"claim restore element=%@ reason=%@", element, reason ?: @"?"];
        WKLog("voice", @"%@ is the game's again (%@)", element, reason ?: @"?");
    }
    [NSNotificationCenter.defaultCenter postNotificationName:AKVoiceSettingsDidChangeNotification
                                                      object:self];
}

@end
