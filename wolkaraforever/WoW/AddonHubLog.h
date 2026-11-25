#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The `addon-hub` log vocabulary.
//
// One tag, a fixed set of events and a fixed set of value keys. This file exists because the
// alternative - passing formatted strings from wherever something interesting happened - is how
// a CurseForge URL carrying a signed token, a WebKit cookie, the API key or a player's home
// directory ends up in a log that gets attached to a pull request. Nothing outside the
// whitelists below is ever written: an unknown key is dropped, a value with an unexpected shape
// is replaced by `-`, and a URL is not a value this log has a key for at all.
//
// What is logged is the *outcome* of a decision - a digest, the provider kind, a package
// identifier, a state name, a count - which is what the queue ordering and the per-row result
// can be reconstructed from afterwards.
typedef NSString *TKAddonHubEvent NS_TYPED_EXTENSIBLE_ENUM;

// A manifest was migrated from an older format, or recovered after an interrupted write.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventRecordMigration;   // "record-migration"
// A project identity was recorded, linked or unlinked.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventSource;            // "source"
// The in-app browser opened, returned, or refused a download.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventHandoff;           // "handoff"
// Every in-app browser delegate callback. URL query values and page contents are never logged.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventWeb;               // "web"
// An archive import or update transaction committed, or rolled back.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventArchive;           // "archive"
// An update check or queue moved.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventUpdate;            // "update"
// One row's own action produced an outcome.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventRow;               // "row"
// A serialized update run was cancelled by the player.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventCancel;            // "cancel"
// A transaction was rolled back after a failure.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventRollback;          // "rollback"
// A relaunch found and repaired an interrupted transaction.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventRecovery;          // "recovery"
// One manager action, from the control that started it to its outcome.
FOUNDATION_EXPORT TKAddonHubEvent const TKAddonHubEventAction;            // "action"

// The keys this log accepts. Anything else is dropped before the line is built.
FOUNDATION_EXPORT NSString *const TKAddonHubKeyOutcome;    // "outcome"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyProvider;   // "provider"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyDigest;     // "digest"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyIdentifier; // "identifier"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyState;      // "state"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyAction;     // "action"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyReason;     // "reason"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyCount;      // "count"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyHost;       // "host"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyRoute;      // "route"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyMIME;       // "mime"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyStatus;     // "status"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyCode;       // "code"
// How long an action took, in whole milliseconds, capped like every other count.
FOUNDATION_EXPORT NSString *const TKAddonHubKeyDuration;   // "duration"
// What kind of failure ended an action, from a closed vocabulary. Never a message.
FOUNDATION_EXPORT NSString *const TKAddonHubKeyFailure;    // "failure"

#pragma mark - The action-event contract

// Events are a development aid and are **off by default**. While they are off nothing is built
// and nothing is written: the only cost of a tap is one flag read. The flag is stored in the
// app's own defaults, so it survives a relaunch and is visible in the same place a person turned
// it on. It is never switched on by a build configuration.
FOUNDATION_EXPORT NSString *const TKAddonHubDiagnosticsEnabledKey;  // "WolkaraForever.AddOns.Diagnostics"

BOOL TKAddonHubDiagnosticsEnabled(void);
void TKAddonHubSetDiagnosticsEnabled(BOOL enabled);

// Every action this manager can start. A closed vocabulary: a string that is not one of these is
// not an action name, so a caller cannot invent a field that carries user content.
typedef NS_ENUM(NSInteger, TKAddonHubActionID) {
    TKAddonHubActionTab = 0,
    TKAddonHubActionSearch,
    TKAddonHubActionSort,
    TKAddonHubActionFilter,
    TKAddonHubActionColumns,
    TKAddonHubActionRefresh,
    TKAddonHubActionImport,
    TKAddonHubActionKeySetup,
    TKAddonHubActionKeyRemove,
    TKAddonHubActionBrowse,
    TKAddonHubActionDiscover,
    TKAddonHubActionLoadMore,
    TKAddonHubActionInstall,
    TKAddonHubActionUpdate,
    TKAddonHubActionUpdateSelected,
    TKAddonHubActionUpdateAll,
    TKAddonHubActionCancel,
    TKAddonHubActionLink,
    TKAddonHubActionUnlink,
    TKAddonHubActionDisable,
    TKAddonHubActionRestore,
    TKAddonHubActionPin,
    TKAddonHubActionUnpin,
    TKAddonHubActionRemove,
    TKAddonHubActionGroupCreate,
    TKAddonHubActionGroupAssign,
    TKAddonHubActionBundledInstall,
    TKAddonHubActionBrowser,
    TKAddonHubActionManage,
};

// The outcome of one action, and what kind of failure ended it.
typedef NS_ENUM(NSInteger, TKAddonHubOutcome) {
    TKAddonHubOutcomeStarted = 0,
    TKAddonHubOutcomeSucceeded,
    TKAddonHubOutcomeFailed,
    TKAddonHubOutcomeCancelled,
    TKAddonHubOutcomeRefused,
};

typedef NS_ENUM(NSInteger, TKAddonHubFailureClass) {
    TKAddonHubFailureNone = 0,
    TKAddonHubFailureNetwork,
    TKAddonHubFailureProvider,
    TKAddonHubFailureArchive,
    TKAddonHubFailureStore,
    TKAddonHubFailureUntrusted,
    TKAddonHubFailureCancelled,
    TKAddonHubFailureConfiguration,
};

FOUNDATION_EXPORT NSString *TKAddonHubActionName(TKAddonHubActionID action);
FOUNDATION_EXPORT NSString *TKAddonHubOutcomeName(TKAddonHubOutcome outcome);
// The failure class an error belongs to. Only the error's domain and HTTP status are read; its
// message, userInfo and any URL inside it are never looked at.
FOUNDATION_EXPORT TKAddonHubFailureClass TKAddonHubFailureClassForError(NSError *_Nullable error);
FOUNDATION_EXPORT NSString *TKAddonHubFailureName(TKAddonHubFailureClass failure);

// One action, in two halves. Begin returns a token that carries the action, the fields it was
// given and the instant it started; Finish writes one line with start and end state, outcome,
// failure class and duration. The token is nil while events are off, so a caller pays two flag
// reads and no allocation. `fields` accepts only the whitelisted keys above.
@interface TKAddonHubActionToken : NSObject
@property(nonatomic, readonly) TKAddonHubActionID action;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, id> *fields;
@end

FOUNDATION_EXPORT TKAddonHubActionToken *_Nullable TKAddonHubActionBegin(
    TKAddonHubActionID action, NSDictionary<NSString *, id> *_Nullable fields);
FOUNDATION_EXPORT void TKAddonHubActionFinish(TKAddonHubActionToken *_Nullable token,
                                              TKAddonHubOutcome outcome,
                                              TKAddonHubFailureClass failure,
                                              NSDictionary<NSString *, id> *_Nullable fields);

// Write queued lines now, on the calling thread. Used by the device self-test, by a fixture that
// has to read its own output, and before the process goes away.
FOUNDATION_EXPORT void TKAddonHubLogFlush(void);

// A receiver for every line, in place of the log file. Set only by a test or the self-test; the
// app never sets it. With a sink installed nothing reaches wolkaraforever.log, which is what
// lets a fixture assert the contract without writing into the machine's own home folder.
typedef void (^TKAddonHubSink)(NSString *line);
FOUNDATION_EXPORT void TKAddonHubSetSink(TKAddonHubSink _Nullable sink);

/// Queue one bounded line. `fields` is filtered against the whitelist above; a nil or empty
/// message still records the event, because "it happened" is the part that matters. Nothing is
/// queued while `TKAddonHubDiagnosticsEnabled()` is NO, and the queue is bounded and drained on
/// its own thread, so a logging call never blocks the caller or grows without limit.
void TKAddonHubLog(TKAddonHubEvent event, NSDictionary<NSString *, id> *_Nullable fields);

/// The line this log would write, without writing it. Exposed so a fixture can assert the
/// privacy boundary instead of grepping a log file after the fact.
NSString *TKAddonHubLogLine(TKAddonHubEvent event, NSDictionary<NSString *, id> *_Nullable fields);

/// The digest form used in the log: the first 16 hex characters of a SHA-256, or `-`. Long
/// enough to tell two archives apart, short enough to stay one field.
NSString *TKAddonHubDigest(NSString *_Nullable digest);

NS_ASSUME_NONNULL_END
