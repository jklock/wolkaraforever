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

// The keys this log accepts. Anything else is dropped before the line is built.
FOUNDATION_EXPORT NSString *const TKAddonHubKeyOutcome;    // "outcome"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyProvider;   // "provider"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyDigest;     // "digest"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyIdentifier; // "identifier"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyState;      // "state"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyAction;     // "action"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyReason;     // "reason"
FOUNDATION_EXPORT NSString *const TKAddonHubKeyCount;      // "count"

/// Write one bounded line. `fields` is filtered against the whitelist above; a nil or empty
/// message still records the event, because "it happened" is the part that matters.
void TKAddonHubLog(TKAddonHubEvent event, NSDictionary<NSString *, id> *_Nullable fields);

/// The line this log would write, without writing it. Exposed so a fixture can assert the
/// privacy boundary instead of grepping a log file after the fact.
NSString *TKAddonHubLogLine(TKAddonHubEvent event, NSDictionary<NSString *, id> *_Nullable fields);

/// The digest form used in the log: the first 16 hex characters of a SHA-256, or `-`. Long
/// enough to tell two archives apart, short enough to stay one field.
NSString *TKAddonHubDigest(NSString *_Nullable digest);

NS_ASSUME_NONNULL_END
