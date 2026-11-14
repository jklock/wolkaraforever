#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The keys of a package's provider identity.
//
// A provider identity is recorded, never inferred. A folder called "Details" is not the
// Details project, and an add-on's display name is not its CurseForge name; the only source of
// these values is the API's own answer at install time. A record without one stays fully
// manageable locally and is deliberately excluded from provider Update and Update All.
FOUNDATION_EXPORT NSString *const TKAddonProviderKind;           // NSString, "curseforge"
FOUNDATION_EXPORT NSString *const TKAddonProviderProjectID;      // NSNumber
FOUNDATION_EXPORT NSString *const TKAddonProviderFileID;         // NSNumber
FOUNDATION_EXPORT NSString *const TKAddonProviderFileName;       // NSString, the downloaded file's name
FOUNDATION_EXPORT NSString *const TKAddonProviderVersion;        // NSString, the file's display version
FOUNDATION_EXPORT NSString *const TKAddonProviderPublishedDate;  // NSString, ISO-8601 as the API sent it
FOUNDATION_EXPORT NSString *const TKAddonProviderCompatibility;  // NSString, "verified" or "unverified"
FOUNDATION_EXPORT NSString *const TKAddonProviderProjectName;    // NSString, the project's own name
FOUNDATION_EXPORT NSString *const TKAddonProviderProjectSlug;    // NSString, the project's own slug

// The two compatibility states a package can be in. They are advice: neither blocks anything.
FOUNDATION_EXPORT NSString *const TKAddonCompatibilityVerified;
FOUNDATION_EXPORT NSString *const TKAddonCompatibilityUnverified;

// Where an installed package came from. Provenance is audit and diagnostics only: it never
// changes a row's controls, and it is never shown as a category the player manages. Four
// acquisition routes exist and each ends in the same catalog.
FOUNDATION_EXPORT NSString *const TKAddonProvenanceAPI;        // the CurseForge API client
FOUNDATION_EXPORT NSString *const TKAddonProvenanceBrowser;    // the in-app browser's download
FOUNDATION_EXPORT NSString *const TKAddonProvenanceFiles;      // a ZIP the player picked
FOUNDATION_EXPORT NSString *const TKAddonProvenanceUnmanaged;  // found on disk, never imported here
// YES only for one of the four. A manifest value this build does not know is not a category.
FOUNDATION_EXPORT BOOL TKAddonProvenanceIsValid(NSString *_Nullable value);

// The persisted form of a record's last update check. Transient phases (checking, downloading)
// are deliberately absent: a relaunch must not claim work that is not running.
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateUpToDate;      // "up-to-date"
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateAvailable;     // "update-available"
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateBrowser;       // "needs-browser-confirmation"
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateUnlinked;      // "unlinked"
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateUnavailable;   // "unavailable-no-compatible-file"
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateRetryable;     // "failed-retryable"
FOUNDATION_EXPORT NSString *const TKAddonStoredUpdateTerminal;      // "failed-terminal"

FOUNDATION_EXPORT BOOL TKAddonProviderIsCurseForge(NSDictionary *_Nullable provider);

@interface TKAddonRecord : NSObject
@property(nonatomic, copy) NSString *identifier;
// Stable package identity. Survives an update of the package's contents, so a package is one
// thing across versions even when the archive renames or adds folders.
@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *version;
// The TOC's own author line, when it declares one. Advisory display text.
@property(nonatomic, copy, nullable) NSString *author;
@property(nonatomic, copy) NSString *source;
// One of TKAddonProvenance*. The store fills this in on read for a record written before
// format 3 existed, so it is never empty for a record that came from -records.
@property(nonatomic, copy) NSString *provenance;
@property(nonatomic, copy) NSArray<NSString *> *folders;
@property(nonatomic) BOOL managed;
@property(nonatomic) BOOL disabled;
@property(nonatomic) BOOL pinned;
// Every TOC `## Interface:` number the package declares, as strings. Advisory only.
@property(nonatomic, copy) NSArray<NSString *> *tocInterface;
// TKAddonCompatibilityVerified or TKAddonCompatibilityUnverified, as a stored string so it
// round-trips through the manifest unchanged.
@property(nonatomic, copy) NSString *compatibility;
// The provider identity, or nil. Never derived from `name` or `folders`.
@property(nonatomic, copy, nullable) NSDictionary<NSString *, id> *provider;
// YES only when the record carries a CurseForge project *and* file identity.
@property(nonatomic, readonly) BOOL providerUpdatable;
// YES when the record names the project it came from, even if it does not know which of that
// project's files it holds. A browser install that returned to the row is this.
@property(nonatomic, readonly) BOOL linked;
// The SHA-256 of the archive this package was installed from, when it was installed here.
@property(nonatomic, copy, nullable) NSString *digest;
// A stable key for a locally cached icon. Never a path and never a URL.
@property(nonatomic, copy, nullable) NSString *iconCacheKey;
// When this store installed or last updated the package, ISO-8601. Nil for a package found on
// disk and never imported, because the honest answer there is "not known".
@property(nonatomic, copy, nullable) NSString *installedAt;
// When the last update check finished, ISO-8601, and what it concluded. Both are diagnostics and
// the row's starting state after a relaunch; neither authorizes anything.
@property(nonatomic, copy, nullable) NSString *lastCheckedAt;
@property(nonatomic, copy, nullable) NSString *lastUpdateState;
// The archive URL the package most recently came from, when a provider named one. Diagnostic
// detail; it is never logged.
@property(nonatomic, copy, nullable) NSString *sourceURL;
@end

// A local organization of the same records. A group is a view over packages that already exist;
// joining one moves no file and changes no ownership.
@interface TKAddonGroup : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
// Record `uuid` values, in the order the player added them.
@property(nonatomic, copy) NSArray<NSString *> *members;
@end

// Owns only packages explicitly imported by WolkaraForever. Existing add-ons are
// discovered and displayed but cannot be removed by this store.
//
// The manifest it writes is format 3. Formats 1 and 2 are migrated on first read, through a
// journal and a backup, so an interrupted migration is recovered rather than left half-applied.
@interface TKAddonStore : NSObject
- (instancetype)initWithAddOnsDirectory:(NSString *)directory product:(NSString *)product gameVersion:(nullable NSString *)version;
@property(nonatomic, readonly, copy) NSArray<TKAddonRecord *> *records;
@property(nonatomic, readonly, copy) NSArray<TKAddonGroup *> *groups;
// 3 once the manifest this store reads and writes is format 3.
@property(nonatomic, readonly) NSInteger manifestFormat;
// Incremented on every committed manifest write. Part of the update contract: a failed update
// leaves the revision exactly where it was.
@property(nonatomic, readonly) NSInteger manifestRevision;
// YES when the last -reload recovered an interrupted migration or update by rolling back.
@property(nonatomic, readonly) BOOL recoveredInterruptedWrite;
// YES when the manifest on disk is a format this build does not write. The records stay visible
// and every mutation is refused, so a newer build's file is never silently downgraded here.
@property(nonatomic, readonly) BOOL manifestReadOnly;

- (void)reload;

// Recovery, run by -reload before anything is shown. Exposed so a test can drive the
// interrupted cases directly instead of timing a kill.
- (BOOL)recoverManifestIfNeeded:(NSError **)error;

// Structural validation only: a readable TOC in at least one folder, and interface numbers
// parsed as *advisory* metadata. A package that declares no matching interface is accepted and
// marked unverified - a version tag is advice, not a gate.
- (BOOL)validatePackageFolders:(NSArray<NSString *> *)folders from:(NSString *)extract
                    interfaces:(NSArray<NSString *> *_Nullable *_Nullable)interfaces
                 compatibility:(NSString *_Nullable *_Nullable)compatibility
                         error:(NSError **)error;

- (BOOL)importZIPAtURL:(NSURL *)url error:(NSError **)error;
// The same import with a provider identity recorded in the same transaction, so a package is
// never briefly updatable-looking without the identity that makes it updatable.
- (BOOL)importZIPAtURL:(NSURL *)url provider:(nullable NSDictionary *)provider error:(NSError **)error;
// The designated import: the same transaction, plus the acquisition route that produced the
// archive. `provenance` must be one of TKAddonProvenance*; an unknown value is refused rather
// than stored, because provenance is what the audit reads.
- (BOOL)importZIPAtURL:(NSURL *)url provider:(nullable NSDictionary *)provider
            provenance:(NSString *)provenance error:(NSError **)error;

// Replace one managed package's contents from an archive, transactionally.
//
// Download and extraction happen before anything is mutated. Under the shared update lock the
// old owned folders are staged aside, the new ones are moved in, and the format-2 manifest is
// committed; any error - or a relaunch that finds the journal - restores both the folders and
// the manifest revision. Disabled and pinned state are preserved, and a folder this store does
// not own is never deleted.
- (BOOL)updateRecord:(TKAddonRecord *)record archiveURL:(NSURL *)url
            provider:(nullable NSDictionary *)provider error:(NSError **)error;
- (BOOL)updateRecord:(TKAddonRecord *)record archiveURL:(NSURL *)url
            provider:(nullable NSDictionary *)provider provenance:(nullable NSString *)provenance
               error:(NSError **)error;

- (BOOL)setDisabled:(BOOL)disabled record:(TKAddonRecord *)record error:(NSError **)error;
- (BOOL)removeRecord:(TKAddonRecord *)record error:(NSError **)error;
- (BOOL)setPinned:(BOOL)pinned record:(TKAddonRecord *)record error:(NSError **)error;
// Keep a project's artwork with the identity the package already has. Nothing a row acts on
// changes: the folders, the file identity and the stored update answer are untouched, so a
// thumbnail request can never make a package look checked or updatable.
- (BOOL)setProviderArtwork:(NSString *)logoURLString record:(TKAddonRecord *)record
                     error:(NSError **)error;

// Record a project identity for a package that arrived as files or was found on disk. Nothing on
// disk moves: the folders keep running exactly as they were. This is the player naming the
// project, never a guess from a folder or display name.
- (BOOL)linkRecord:(TKAddonRecord *)record provider:(NSDictionary *)provider
        provenance:(NSString *)provenance error:(NSError **)error;
- (BOOL)unlinkRecord:(TKAddonRecord *)record error:(NSError **)error;

// Persist the outcome of update checks for several packages in one commit. `states` maps a
// record `uuid` to one of the stored TKAddonStoredUpdate* values; an empty string clears one.
- (BOOL)setUpdateStates:(NSDictionary<NSString *, NSString *> *)states
              checkedAt:(nullable NSString *)checkedAt error:(NSError **)error;

// Groups: local organization only. Creating one writes no file, and no member is curated by
// this store - a group holds record identities, not packages.
- (nullable TKAddonGroup *)createGroupNamed:(NSString *)name error:(NSError **)error;
- (BOOL)setGroup:(TKAddonGroup *)group member:(TKAddonRecord *)record joined:(BOOL)joined
           error:(NSError **)error;
- (BOOL)removeGroup:(TKAddonGroup *)group error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
