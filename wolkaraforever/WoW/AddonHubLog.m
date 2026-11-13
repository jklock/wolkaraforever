#import "AddonHubLog.h"
#import "AddonStore.h"
#import "../App/WolkaraForeverLog.h"

TKAddonHubEvent const TKAddonHubEventRecordMigration = @"record-migration";
TKAddonHubEvent const TKAddonHubEventSource = @"source";
TKAddonHubEvent const TKAddonHubEventHandoff = @"handoff";
TKAddonHubEvent const TKAddonHubEventArchive = @"archive";
TKAddonHubEvent const TKAddonHubEventUpdate = @"update";
TKAddonHubEvent const TKAddonHubEventRow = @"row";
TKAddonHubEvent const TKAddonHubEventCancel = @"cancel";
TKAddonHubEvent const TKAddonHubEventRollback = @"rollback";
TKAddonHubEvent const TKAddonHubEventRecovery = @"recovery";

NSString *const TKAddonHubKeyOutcome    = @"outcome";
NSString *const TKAddonHubKeyProvider   = @"provider";
NSString *const TKAddonHubKeyDigest     = @"digest";
NSString *const TKAddonHubKeyIdentifier = @"identifier";
NSString *const TKAddonHubKeyState      = @"state";
NSString *const TKAddonHubKeyAction     = @"action";
NSString *const TKAddonHubKeyReason     = @"reason";
NSString *const TKAddonHubKeyCount      = @"count";

// The order the keys are printed in, so two lines about the same event read the same way.
static NSArray<NSString *> *TKAddonHubKeyOrder(void) {
    return @[TKAddonHubKeyOutcome, TKAddonHubKeyAction, TKAddonHubKeyState, TKAddonHubKeyProvider,
             TKAddonHubKeyIdentifier, TKAddonHubKeyDigest, TKAddonHubKeyReason, TKAddonHubKeyCount];
}

// A short, bounded token: letters, digits and the three separators the app's own identifiers use.
// Anything else - a slash, a colon, an `@`, a space, a percent escape - makes the whole value `-`
// rather than being partially printed, because a partially printed URL is still a URL.
static NSString *TKAddonHubToken(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class]) return @"-";
    NSString *text = value;
    if (!text.length || text.length > limit) return @"-";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    if ([text rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return @"-";
    return text;
}

// The provider field is a closed vocabulary, never free text: the four acquisition routes and
// the one provider kind this build knows. A manifest value this build does not recognise is `-`.
static NSString *TKAddonHubProvider(id value) {
    if (![value isKindOfClass:NSString.class]) return @"-";
    if (TKAddonProvenanceIsValid(value)) return value;
    if ([value isEqual:@"curseforge"]) return @"curseforge";
    return @"-";
}

NSString *TKAddonHubDigest(NSString *digest) {
    if (![digest isKindOfClass:NSString.class] || digest.length < 16) return @"-";
    NSString *prefix = [digest substringToIndex:16];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    if ([prefix rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound) return @"-";
    return prefix;
}

NSString *TKAddonHubLogLine(TKAddonHubEvent event, NSDictionary<NSString *, id> *fields) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"event=%@", TKAddonHubToken(event, 32)];
    for (NSString *key in TKAddonHubKeyOrder()) {
        id value = fields[key];
        if (!value) continue;
        if ([key isEqual:TKAddonHubKeyCount]) {
            NSInteger count = [value isKindOfClass:NSNumber.class] ? [value integerValue] : -1;
            if (count < 0) continue;
            [line appendFormat:@" %@=%ld", key, (long)MIN(count, (NSInteger)100000)];
        } else if ([key isEqual:TKAddonHubKeyProvider]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubProvider(value)];
        } else if ([key isEqual:TKAddonHubKeyDigest]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubDigest(value)];
        } else if ([key isEqual:TKAddonHubKeyIdentifier]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubToken(value, 64)];
        } else {
            [line appendFormat:@" %@=%@", key, TKAddonHubToken(value, 48)];
        }
    }
    return line;
}

void TKAddonHubLog(TKAddonHubEvent event, NSDictionary<NSString *, id> *fields) {
    NSString *line = TKAddonHubLogLine(event, fields);
    WKLog("addon-hub", @"%@", line);
}
