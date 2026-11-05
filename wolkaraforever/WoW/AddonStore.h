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

// The two compatibility states a package can be in. They are advice: neither blocks anything.
FOUNDATION_EXPORT NSString *const TKAddonCompatibilityVerified;
FOUNDATION_EXPORT NSString *const TKAddonCompatibilityUnverified;

FOUNDATION_EXPORT BOOL TKAddonProviderIsCurseForge(NSDictionary *_Nullable provider);

@interface TKAddonRecord : NSObject
@property(nonatomic, copy) NSString *identifier;
// Stable package identity. Survives an update of the package's contents, so a package is one
// thing across versions even when the archive renames or adds folders.
@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *version;
@property(nonatomic, copy) NSString *source;
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
@end

// Owns only packages explicitly imported by WolkaraForever. Existing add-ons are
// discovered and displayed but cannot be removed by this store.
//
// The manifest it writes is format 2. A format-1 manifest is migrated on first read, through a
// journal and a backup, so an interrupted migration is recovered rather than left half-applied.
@interface TKAddonStore : NSObject
- (instancetype)initWithAddOnsDirectory:(NSString *)directory product:(NSString *)product gameVersion:(nullable NSString *)version;
@property(nonatomic, readonly, copy) NSArray<TKAddonRecord *> *records;
// 2 once the manifest this store reads and writes is format 2.
@property(nonatomic, readonly) NSInteger manifestFormat;
// Incremented on every committed manifest write. Part of the update contract: a failed update
// leaves the revision exactly where it was.
@property(nonatomic, readonly) NSInteger manifestRevision;
// YES when the last -reload recovered an interrupted migration or update by rolling back.
@property(nonatomic, readonly) BOOL recoveredInterruptedWrite;

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

// Replace one managed package's contents from an archive, transactionally.
//
// Download and extraction happen before anything is mutated. Under the shared update lock the
// old owned folders are staged aside, the new ones are moved in, and the format-2 manifest is
// committed; any error - or a relaunch that finds the journal - restores both the folders and
// the manifest revision. Disabled and pinned state are preserved, and a folder this store does
// not own is never deleted.
- (BOOL)updateRecord:(TKAddonRecord *)record archiveURL:(NSURL *)url
            provider:(nullable NSDictionary *)provider error:(NSError **)error;

- (BOOL)setDisabled:(BOOL)disabled record:(TKAddonRecord *)record error:(NSError **)error;
- (BOOL)removeRecord:(TKAddonRecord *)record error:(NSError **)error;
- (BOOL)setPinned:(BOOL)pinned record:(TKAddonRecord *)record error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
