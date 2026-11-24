#import "AddonHubLog.h"
#import "AddonStore.h"
#import "../App/WolkaraForeverLog.h"

TKAddonHubEvent const TKAddonHubEventRecordMigration = @"record-migration";
TKAddonHubEvent const TKAddonHubEventSource = @"source";
TKAddonHubEvent const TKAddonHubEventHandoff = @"handoff";
TKAddonHubEvent const TKAddonHubEventWeb = @"web";
TKAddonHubEvent const TKAddonHubEventArchive = @"archive";
TKAddonHubEvent const TKAddonHubEventUpdate = @"update";
TKAddonHubEvent const TKAddonHubEventRow = @"row";
TKAddonHubEvent const TKAddonHubEventCancel = @"cancel";
TKAddonHubEvent const TKAddonHubEventRollback = @"rollback";
TKAddonHubEvent const TKAddonHubEventRecovery = @"recovery";
TKAddonHubEvent const TKAddonHubEventAction = @"action";

NSString *const TKAddonHubKeyOutcome    = @"outcome";
NSString *const TKAddonHubKeyProvider   = @"provider";
NSString *const TKAddonHubKeyDigest     = @"digest";
NSString *const TKAddonHubKeyIdentifier = @"identifier";
NSString *const TKAddonHubKeyState      = @"state";
NSString *const TKAddonHubKeyAction     = @"action";
NSString *const TKAddonHubKeyReason     = @"reason";
NSString *const TKAddonHubKeyCount      = @"count";
NSString *const TKAddonHubKeyHost       = @"host";
NSString *const TKAddonHubKeyRoute      = @"route";
NSString *const TKAddonHubKeyMIME       = @"mime";
NSString *const TKAddonHubKeyStatus     = @"status";
NSString *const TKAddonHubKeyCode       = @"code";
NSString *const TKAddonHubKeyDuration   = @"duration";
NSString *const TKAddonHubKeyFailure    = @"failure";

NSString *const TKAddonHubDiagnosticsEnabledKey = @"WolkaraForever.AddOns.Diagnostics";

// The order the keys are printed in, so two lines about the same event read the same way.
static NSArray<NSString *> *TKAddonHubKeyOrder(void) {
    return @[TKAddonHubKeyOutcome, TKAddonHubKeyAction, TKAddonHubKeyState, TKAddonHubKeyFailure,
             TKAddonHubKeyProvider, TKAddonHubKeyIdentifier, TKAddonHubKeyDigest,
             TKAddonHubKeyReason, TKAddonHubKeyHost, TKAddonHubKeyRoute, TKAddonHubKeyMIME,
             TKAddonHubKeyStatus, TKAddonHubKeyCode, TKAddonHubKeyCount, TKAddonHubKeyDuration];
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

// The failure field is a closed vocabulary too. A class this build does not name is `-`, so an
// error message can never travel in this key.
static NSString *TKAddonHubFailureValue(id value) {
    static NSSet<NSString *> *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ known = [NSSet setWithObjects:@"network", @"provider", @"archive",
        @"store", @"untrusted", @"cancelled", @"configuration", nil]; });
    if (![value isKindOfClass:NSString.class] || ![known containsObject:value]) return @"-";
    return value;
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
        if ([key isEqual:TKAddonHubKeyCode]) {
            NSInteger code = [value isKindOfClass:NSNumber.class] ? [value integerValue] : NSIntegerMin;
            if (code == NSIntegerMin) continue;
            [line appendFormat:@" %@=%ld", key, (long)MAX(MIN(code, (NSInteger)999999), (NSInteger)-999999)];
        } else if ([key isEqual:TKAddonHubKeyCount] || [key isEqual:TKAddonHubKeyStatus] ||
                   [key isEqual:TKAddonHubKeyDuration]) {
            NSInteger count = [value isKindOfClass:NSNumber.class] ? [value integerValue] : -1;
            if (count < 0) continue;
            NSInteger ceiling = [key isEqual:TKAddonHubKeyCount] ? 100000 : 999999;
            [line appendFormat:@" %@=%ld", key, (long)MIN(count, ceiling)];
        } else if ([key isEqual:TKAddonHubKeyProvider]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubProvider(value)];
        } else if ([key isEqual:TKAddonHubKeyDigest]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubDigest(value)];
        } else if ([key isEqual:TKAddonHubKeyFailure]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubFailureValue(value)];
        } else if ([key isEqual:TKAddonHubKeyIdentifier]) {
            [line appendFormat:@" %@=%@", key, TKAddonHubToken(value, 64)];
        } else {
            [line appendFormat:@" %@=%@", key, TKAddonHubToken(value, 48)];
        }
    }
    return line;
}

#pragma mark - Gate and bounded writer

// The switch. Off unless someone turned it on in this app's Settings, which is what makes
// "nothing is recorded during ordinary play" a statement about the shipped build rather than a
// hope about a build configuration.
static BOOL TKAddonHubEnabled;
static BOOL TKAddonHubEnabledKnown;

static void TKAddonHubRefreshEnabled(void) {
    TKAddonHubEnabled = [NSUserDefaults.standardUserDefaults boolForKey:TKAddonHubDiagnosticsEnabledKey];
    TKAddonHubEnabledKnown = YES;
}

BOOL TKAddonHubDiagnosticsEnabled(void) {
    if (!TKAddonHubEnabledKnown) TKAddonHubRefreshEnabled();
    return TKAddonHubEnabled;
}

void TKAddonHubSetDiagnosticsEnabled(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:TKAddonHubDiagnosticsEnabledKey];
    TKAddonHubEnabled = enabled;
    TKAddonHubEnabledKnown = YES;
    if (!enabled) return;
    // Turning it on announces itself, so a log attached later can be dated against the switch.
    TKAddonHubLog(TKAddonHubEventAction, @{ TKAddonHubKeyOutcome: @"succeeded",
        TKAddonHubKeyAction: @"diagnostics", TKAddonHubKeyState: @"enabled" });
}

// The writer. A serial queue with a bounded backlog: a slow disk can drop the oldest lines, but
// it can never grow without limit or block the thread that took the action. Nothing is queued
// while the switch is off, so the disabled path is one flag read and no allocation.
static const NSUInteger TKAddonHubQueueCapacity = 512;

static dispatch_queue_t TKAddonHubQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("local.wolkaraforever.addon-hub", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableArray<NSString *> *TKAddonHubPending;
static BOOL TKAddonHubDraining;
static TKAddonHubSink TKAddonHubSinkBlock;

static void TKAddonHubWrite(NSArray<NSString *> *lines) {
    TKAddonHubSink sink = TKAddonHubSinkBlock;
    if (sink) {
        for (NSString *line in lines) sink(line);
        return;
    }
    for (NSString *line in lines) WKLog("addon-hub", @"%@", line);
}

void TKAddonHubSetSink(TKAddonHubSink sink) {
    TKAddonHubSinkBlock = [sink copy];
}

static void TKAddonHubEnqueue(NSString *line) {
    if (!line.length) return;
    dispatch_async(TKAddonHubQueue(), ^{
        if (!TKAddonHubPending) TKAddonHubPending = [NSMutableArray array];
        if (TKAddonHubPending.count >= TKAddonHubQueueCapacity) [TKAddonHubPending removeObjectAtIndex:0];
        [TKAddonHubPending addObject:line];
        if (TKAddonHubDraining) return;
        TKAddonHubDraining = YES;
        dispatch_async(TKAddonHubQueue(), ^{
            TKAddonHubDraining = NO;
            NSArray<NSString *> *lines = [TKAddonHubPending copy];
            [TKAddonHubPending removeAllObjects];
            if (!TKAddonHubDiagnosticsEnabled()) return;
            TKAddonHubWrite(lines);
        });
    });
}

void TKAddonHubLogFlush(void) {
    dispatch_sync(TKAddonHubQueue(), ^{
        NSArray<NSString *> *lines = TKAddonHubPending.count ? [TKAddonHubPending copy] : @[];
        [TKAddonHubPending removeAllObjects];
        if (!TKAddonHubDiagnosticsEnabled()) return;
        TKAddonHubWrite(lines);
    });
}

void TKAddonHubLog(TKAddonHubEvent event, NSDictionary<NSString *, id> *fields) {
    if (!TKAddonHubDiagnosticsEnabled()) return;
    TKAddonHubEnqueue(TKAddonHubLogLine(event, fields));
}

#pragma mark - The action contract

NSString *TKAddonHubActionName(TKAddonHubActionID action) {
    switch (action) {
        case TKAddonHubActionTab: return @"tab";
        case TKAddonHubActionSearch: return @"search";
        case TKAddonHubActionSort: return @"sort";
        case TKAddonHubActionFilter: return @"filter";
        case TKAddonHubActionColumns: return @"columns";
        case TKAddonHubActionRefresh: return @"refresh";
        case TKAddonHubActionImport: return @"import";
        case TKAddonHubActionKeySetup: return @"key-setup";
        case TKAddonHubActionKeyRemove: return @"key-remove";
        case TKAddonHubActionBrowse: return @"browse";
        case TKAddonHubActionDiscover: return @"discover";
        case TKAddonHubActionLoadMore: return @"load-more";
        case TKAddonHubActionInstall: return @"install";
        case TKAddonHubActionUpdate: return @"update";
        case TKAddonHubActionUpdateSelected: return @"update-selected";
        case TKAddonHubActionUpdateAll: return @"update-all";
        case TKAddonHubActionCancel: return @"cancel";
        case TKAddonHubActionLink: return @"link";
        case TKAddonHubActionUnlink: return @"unlink";
        case TKAddonHubActionDisable: return @"disable";
        case TKAddonHubActionRestore: return @"restore";
        case TKAddonHubActionPin: return @"pin";
        case TKAddonHubActionUnpin: return @"unpin";
        case TKAddonHubActionRemove: return @"remove";
        case TKAddonHubActionGroupCreate: return @"group-create";
        case TKAddonHubActionGroupAssign: return @"group-assign";
        case TKAddonHubActionBundledInstall: return @"bundled-install";
        case TKAddonHubActionBrowser: return @"browser";
        case TKAddonHubActionManage: return @"manage";
    }
    return @"unknown";
}

NSString *TKAddonHubOutcomeName(TKAddonHubOutcome outcome) {
    switch (outcome) {
        case TKAddonHubOutcomeStarted: return @"started";
        case TKAddonHubOutcomeSucceeded: return @"succeeded";
        case TKAddonHubOutcomeFailed: return @"failed";
        case TKAddonHubOutcomeCancelled: return @"cancelled";
        case TKAddonHubOutcomeRefused: return @"refused";
    }
    return @"unknown";
}

NSString *TKAddonHubFailureName(TKAddonHubFailureClass failure) {
    switch (failure) {
        case TKAddonHubFailureNone: return @"-";
        case TKAddonHubFailureNetwork: return @"network";
        case TKAddonHubFailureProvider: return @"provider";
        case TKAddonHubFailureArchive: return @"archive";
        case TKAddonHubFailureStore: return @"store";
        case TKAddonHubFailureUntrusted: return @"untrusted";
        case TKAddonHubFailureCancelled: return @"cancelled";
        case TKAddonHubFailureConfiguration: return @"configuration";
    }
    return @"-";
}

TKAddonHubFailureClass TKAddonHubFailureClassForError(NSError *error) {
    if (!error) return TKAddonHubFailureNone;
    // Only the domain and status are read. The message, the userInfo dictionary and anything a
    // URL or a server wrote into them are not this function's business.
    if ([error.domain isEqual:NSURLErrorDomain]) {
        return error.code == NSURLErrorCancelled ? TKAddonHubFailureCancelled : TKAddonHubFailureNetwork;
    }
    if ([error.domain isEqual:@"WolkaraForever.CurseForge"]) return TKAddonHubFailureProvider;
    if ([error.domain isEqual:@"WolkaraForever.AddOns"]) return TKAddonHubFailureStore;
    if ([error.domain isEqual:NSCocoaErrorDomain]) return TKAddonHubFailureStore;
    if ([error.domain isEqual:NSOSStatusErrorDomain]) return TKAddonHubFailureConfiguration;
    return TKAddonHubFailureStore;
}

@interface TKAddonHubActionToken ()
@property(nonatomic, readwrite) TKAddonHubActionID action;
@property(nonatomic, readwrite, copy) NSDictionary<NSString *, id> *fields;
@property(nonatomic, readwrite) NSTimeInterval started;
@end

@implementation TKAddonHubActionToken
@end

TKAddonHubActionToken *TKAddonHubActionBegin(TKAddonHubActionID action,
                                             NSDictionary<NSString *, id> *fields) {
    // The disabled path returns before anything is allocated or formatted.
    if (!TKAddonHubDiagnosticsEnabled()) return nil;
    TKAddonHubActionToken *token = [TKAddonHubActionToken new];
    token.action = action;
    token.fields = fields ?: @{};
    token.started = NSProcessInfo.processInfo.systemUptime;
    NSMutableDictionary *line = [token.fields mutableCopy];
    line[TKAddonHubKeyAction] = TKAddonHubActionName(action);
    line[TKAddonHubKeyOutcome] = TKAddonHubOutcomeName(TKAddonHubOutcomeStarted);
    TKAddonHubLog(TKAddonHubEventAction, line);
    return token;
}

void TKAddonHubActionFinish(TKAddonHubActionToken *token, TKAddonHubOutcome outcome,
                            TKAddonHubFailureClass failure,
                            NSDictionary<NSString *, id> *fields) {
    // A nil token is the disabled path, and it stays silent: the pair is only meaningful whole.
    if (!token) return;
    NSMutableDictionary *line = [token.fields mutableCopy];
    for (NSString *key in fields) line[key] = fields[key];
    line[TKAddonHubKeyAction] = TKAddonHubActionName(token.action);
    line[TKAddonHubKeyOutcome] = TKAddonHubOutcomeName(outcome);
    if (failure != TKAddonHubFailureNone) line[TKAddonHubKeyFailure] = TKAddonHubFailureName(failure);
    NSTimeInterval elapsed = (NSProcessInfo.processInfo.systemUptime - token.started) * 1000.0;
    line[TKAddonHubKeyDuration] = @((NSInteger)MAX(0.0, MIN(elapsed, 999999.0)));
    TKAddonHubLog(TKAddonHubEventAction, line);
}
