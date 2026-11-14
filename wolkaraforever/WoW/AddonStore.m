#import "AddonStore.h"
#import "AddonHubLog.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#import <objc/message.h>
#import "UpdateLock.h"
#import "../App/WKLocalization.h"

NSString *const TKAddonProviderKind          = @"kind";
NSString *const TKAddonProviderProjectID     = @"projectID";
NSString *const TKAddonProviderFileID        = @"fileID";
NSString *const TKAddonProviderFileName      = @"fileName";
NSString *const TKAddonProviderVersion       = @"version";
NSString *const TKAddonProviderPublishedDate = @"publishedDate";
NSString *const TKAddonProviderCompatibility = @"compatibility";
NSString *const TKAddonProviderProjectName   = @"projectName";
NSString *const TKAddonProviderProjectSlug   = @"projectSlug";

NSString *const TKAddonCompatibilityVerified   = @"verified";
NSString *const TKAddonCompatibilityUnverified = @"unverified";

NSString *const TKAddonProvenanceAPI       = @"api";
NSString *const TKAddonProvenanceBrowser   = @"browser";
NSString *const TKAddonProvenanceFiles     = @"files";
NSString *const TKAddonProvenanceUnmanaged = @"unmanaged";

NSString *const TKAddonStoredUpdateUpToDate    = @"up-to-date";
NSString *const TKAddonStoredUpdateAvailable   = @"update-available";
NSString *const TKAddonStoredUpdateBrowser     = @"needs-browser-confirmation";
NSString *const TKAddonStoredUpdateUnlinked    = @"unlinked";
NSString *const TKAddonStoredUpdateUnavailable = @"unavailable-no-compatible-file";
NSString *const TKAddonStoredUpdateRetryable   = @"failed-retryable";
NSString *const TKAddonStoredUpdateTerminal    = @"failed-terminal";

// The manifest this store writes. Format 1 stored a folder list and a digest; format 2 added a
// stable package identity and an optional provider identity, which is what makes a per-package
// Update possible at all. Format 3 adds the normalized record: an explicit acquisition route
// (`provenance`), the author line, an icon cache key, when the package was installed, the
// outcome of its last update check, and the local groups a player organized it into.
//
// Every migration is journalled, so a process that dies between the backup and the new write is
// recovered on the next launch instead of showing an Add-ons page built from half a manifest.
static NSString *const ManifestName      = @".wolkaraforever-addons.json";
static NSString *const JournalName       = @"manifest-journal.json";
static NSString *const BackupNameV1      = @"manifest-v1-backup.json";
static NSString *const BackupNameV2      = @"manifest-v2-backup.json";
static NSString *const CorruptName       = @"manifest-corrupt.json";
static NSString *const UpdateJournalName = @"update-journal.json";
static NSString *const UpdateBackupName  = @"update-manifest-backup.json";
static const NSInteger ManifestFormat    = 3;

// Forever's released product interface. Advisory only: a package that does not declare it is
// imported, shown and used, and marked unverified.
static NSString *const ForeverInterface = @"16001";

static BOOL Fail(NSError **error, NSString *message) { if(error)*error=[NSError errorWithDomain:@"WolkaraForever.AddOns" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return NO; }
static NSString *TOC(NSString *folder) {
    NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for(NSString *name in names) if([name.pathExtension.lowercaseString isEqual:@"toc"]) {
        NSData *data=[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:name] options:0 error:NULL];
        if(data.length && data.length<=256*1024) return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]?:[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    return nil;
}
static NSString *Value(NSString *toc,NSString *key) {
    for(NSString *line in [toc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) if([line hasPrefix:[@"## " stringByAppendingString:key]]) {
        NSString *value=[[line substringFromIndex:key.length+3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(value.length&&value.length<512)return value;
    }
    return nil;
}
// Every interface number a TOC declares, as strings, so they can go in the manifest unchanged.
static NSArray<NSString *> *Interfaces(NSString *toc) {
    NSString *declared = toc ? Value(toc, @"Interface:") : nil;
    if (!declared.length) return @[];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSString *part in [declared componentsSeparatedByString:@","]) {
        NSString *value = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length && ![values containsObject:value]) [values addObject:value];
    }
    return values;
}
static NSString *CompatibilityForInterfaces(NSArray<NSString *> *interfaces) {
    return [interfaces containsObject:ForeverInterface] ? TKAddonCompatibilityVerified : TKAddonCompatibilityUnverified;
}
static NSString *Digest(NSData *data) { unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);NSMutableString *s=[NSMutableString new];for(NSUInteger i=0;i<sizeof(hash);i++)[s appendFormat:@"%02x",hash[i]];return s; }
static BOOL Managed(NSDictionary *item) { return [item[@"folders"] isKindOfClass:NSArray.class] && [item[@"identifier"] isKindOfClass:NSString.class]; }
static BOOL SafeFolderName(NSString *name) {
    return [name isKindOfClass:NSString.class] && name.length && ![name containsString:@"/"] &&
        ![name isEqual:@"."] && ![name isEqual:@".."];
}
// Only the documented keys survive a write, so a stray value cannot be smuggled into the
// manifest through a provider dictionary.
static NSDictionary *CleanProvider(NSDictionary *provider) {
    if (![provider isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *copy = [NSMutableDictionary dictionary];
    for (NSString *key in @[TKAddonProviderKind, TKAddonProviderProjectID, TKAddonProviderFileID,
                            TKAddonProviderFileName, TKAddonProviderVersion,
                            TKAddonProviderPublishedDate, TKAddonProviderCompatibility,
                            TKAddonProviderProjectName, TKAddonProviderProjectSlug,
                            @"logo"]) {
        id value = provider[key];
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length) copy[key] = value;
        else if ([value isKindOfClass:NSNumber.class]) copy[key] = value;
    }
    return copy.count ? copy : nil;
}

// A stored update state this build knows, or nil. An unknown string from a newer build is
// dropped rather than shown, so a row never displays a word it has no localized sentence for.
static NSString *CleanUpdateState(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    static NSSet<NSString *> *known;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ known = [NSSet setWithObjects:TKAddonStoredUpdateUpToDate,
        TKAddonStoredUpdateAvailable, TKAddonStoredUpdateBrowser, TKAddonStoredUpdateUnlinked,
        TKAddonStoredUpdateUnavailable, TKAddonStoredUpdateRetryable, TKAddonStoredUpdateTerminal, nil]; });
    return [known containsObject:value] ? value : nil;
}

// An ISO-8601 instant, or nil. Only a value this build wrote is accepted back.
static NSString *CleanInstant(id value) {
    if (![value isKindOfClass:NSString.class] || ((NSString *)value).length > 40) return nil;
    return [(NSString *)value length] ? value : nil;
}

// The icon key is a digest, so it can never be a path or a URL that leaks into a log.
static NSString *IconKey(NSString *uuid, NSString *name) {
    NSString *seed = [NSString stringWithFormat:@"%@\n%@", uuid ?: @"", name ?: @""];
    return [Digest([seed dataUsingEncoding:NSUTF8StringEncoding]) substringToIndex:32];
}

BOOL TKAddonProvenanceIsValid(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    return [value isEqual:TKAddonProvenanceAPI] || [value isEqual:TKAddonProvenanceBrowser] ||
           [value isEqual:TKAddonProvenanceFiles] || [value isEqual:TKAddonProvenanceUnmanaged];
}

BOOL TKAddonProviderIsCurseForge(NSDictionary *provider) {
    if (![provider isKindOfClass:NSDictionary.class]) return NO;
    if (![provider[TKAddonProviderKind] isEqual:@"curseforge"]) return NO;
    return [provider[TKAddonProviderProjectID] isKindOfClass:NSNumber.class] &&
           [provider[TKAddonProviderFileID] isKindOfClass:NSNumber.class];
}

@implementation TKAddonRecord
- (BOOL)providerUpdatable { return TKAddonProviderIsCurseForge(self.provider); }
- (BOOL)linked {
    if (![self.provider isKindOfClass:NSDictionary.class]) return NO;
    if (![self.provider[TKAddonProviderKind] isEqual:@"curseforge"]) return NO;
    return [self.provider[TKAddonProviderProjectID] isKindOfClass:NSNumber.class];
}
@end

@implementation TKAddonGroup
@end

@implementation TKAddonStore {
    NSString *_directory, *_product, *_version, *_support;
    NSArray<TKAddonRecord *> *_records;
    NSArray<TKAddonGroup *> *_groups;
    NSArray<NSDictionary *> *_links;
    NSInteger _manifestFormat;
    NSInteger _manifestRevision;
    BOOL _recoveredInterruptedWrite;
    BOOL _manifestReadOnly;
}

- (instancetype)initWithAddOnsDirectory:(NSString *)directory product:(NSString *)product gameVersion:(NSString *)version {
    if(!(self=[super init]))return nil;_directory=directory.copy;_product=product.copy;_version=version.copy?:@"unknown";
    NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    _support=[[[base stringByAppendingPathComponent:@"WolkaraForever/AddOns"] stringByAppendingPathComponent:_product] stringByAppendingPathComponent:Digest([directory dataUsingEncoding:NSUTF8StringEncoding])];[self reload];return self;
}
- (NSArray<TKAddonRecord *> *)records { return _records?:@[]; }
- (NSArray<TKAddonGroup *> *)groups { return _groups?:@[]; }
- (NSInteger)manifestFormat { return _manifestFormat; }
- (NSInteger)manifestRevision { return _manifestRevision; }
- (BOOL)recoveredInterruptedWrite { return _recoveredInterruptedWrite; }
- (BOOL)manifestReadOnly { return _manifestReadOnly; }

#pragma mark - Manifest reading

- (NSString *)manifestPath { return [_directory stringByAppendingPathComponent:ManifestName]; }
- (NSData *)manifestData { return [NSData dataWithContentsOfFile:[self manifestPath]]; }
- (NSDictionary *)parsedManifest:(NSData *)data {
    if (!data.length || data.length >= 2*1024*1024) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
// A format-2 manifest is only used when every package record is well formed. A manifest that
// parsed as JSON but carries a malformed package is treated as absent rather than as truth:
// showing half a manifest is the failure mode this whole journal exists to prevent.
- (BOOL)validPackages:(NSArray *)packages {
    if (![packages isKindOfClass:NSArray.class]) return NO;
    for (id item in packages) {
        if (![item isKindOfClass:NSDictionary.class]) return NO;
        if (![item[@"identifier"] isKindOfClass:NSString.class] || !((NSString *)item[@"identifier"]).length) return NO;
        if (!Managed(item)) return NO;
        for (id folder in item[@"folders"])
            if (![folder isKindOfClass:NSString.class] || ![folder length] || [folder containsString:@"/"]) return NO;
    }
    return YES;
}
- (NSDictionary *)manifest {
    NSDictionary *value = [self parsedManifest:[self manifestData]];
    NSInteger format = value ? [value[@"format"] integerValue] : 0;
    if (value && format == ManifestFormat) return value;
    if (value && format == 1) return value;   // not yet migrated
    if (value && format == 2) return value;   // not yet migrated
    // A manifest this build does not write. It is still read, so the page can show what the
    // newer build recorded, but nothing here may rewrite it.
    if (value && format > ManifestFormat) return value;
    return @{ @"format": @(ManifestFormat), @"revision": @0, @"packages": @[], @"groups": @[] };
}
- (BOOL)savePackages:(NSArray *)packages groups:(NSArray *)groups revision:(NSInteger)revision error:(NSError **)error {
    if (_manifestReadOnly) return Fail(error, @"This add-on list was written by a newer WolkaraForever and is read-only here.");
    NSDictionary *value=@{ @"format":@(ManifestFormat),@"product":_product,@"gameVersion":_version,
                           @"revision":@(revision),@"packages":packages,@"groups":groups?:@[],
                           @"links":_links?:@[] };
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:error];
    if (!data) return NO;
    return [data writeToFile:[self manifestPath] options:NSDataWritingAtomic error:error];
}
- (BOOL)saveManifest:(NSArray *)packages revision:(NSInteger)revision error:(NSError **)error {
    return [self savePackages:packages groups:_groups ?: @[] revision:revision error:error];
}

// Groups as stored, with every member that is not a record this build shows dropped. A group is
// a view over records; a membership that names nothing would render as an empty row.
- (NSArray<TKAddonGroup *> *)parsedGroups:(id)value knownIdentities:(NSSet<NSString *> *)known {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<TKAddonGroup *> *groups = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (id item in value) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = [item[@"id"] isKindOfClass:NSString.class] ? item[@"id"] : nil;
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : nil;
        if (!identifier.length || !name.length || name.length > 120) continue;
        if ([seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        NSMutableArray<NSString *> *members = [NSMutableArray array];
        for (id member in [item[@"members"] isKindOfClass:NSArray.class] ? item[@"members"] : @[])
            if ([member isKindOfClass:NSString.class] && [known containsObject:member] &&
                ![members containsObject:member]) [members addObject:member];
        TKAddonGroup *group = [TKAddonGroup new];
        group.identifier = identifier;
        group.name = name;
        group.members = members;
        [groups addObject:group];
    }
    return groups;
}

// Link entries for packages this store does not own. Only a folder name and a recorded project
// identity survive a read: a link is a statement about which project a folder is, nothing more.
- (NSArray<NSDictionary *> *)parsedLinks:(id)value {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *links = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (id item in value) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *folder = [item[@"folder"] isKindOfClass:NSString.class] ? item[@"folder"] : nil;
        if (!SafeFolderName(folder) || [seen containsObject:folder]) continue;
        [seen addObject:folder];
        NSMutableDictionary *copy = [NSMutableDictionary dictionary];
        copy[@"folder"] = folder;
        if ([item[@"uuid"] isKindOfClass:NSString.class]) copy[@"uuid"] = item[@"uuid"];
        NSDictionary *provider = CleanProvider(item[@"provider"]);
        if (provider) copy[@"provider"] = provider;
        if (TKAddonProvenanceIsValid(item[@"provenance"])) copy[@"provenance"] = item[@"provenance"];
        if (CleanInstant(item[@"linkedAt"])) copy[@"linkedAt"] = item[@"linkedAt"];
        if (CleanInstant(item[@"lastCheckedAt"])) copy[@"lastCheckedAt"] = item[@"lastCheckedAt"];
        NSString *state = CleanUpdateState(item[@"lastUpdateState"]);
        if (state) copy[@"lastUpdateState"] = state;
        if ([item[@"sourceURL"] isKindOfClass:NSString.class] && [item[@"sourceURL"] length] <= 512)
            copy[@"sourceURL"] = item[@"sourceURL"];
        [links addObject:copy];
    }
    return links;
}
- (NSMutableArray *)mutableLinks { return [_links mutableCopy] ?: [NSMutableArray array]; }
- (BOOL)writeLinks:(NSArray *)links packages:(NSArray *)packages error:(NSError **)error {
    NSInteger revision = _manifestRevision + 1;
    NSArray *previous = _links;
    _links = links;
    if (![self savePackages:packages groups:[self mutableGroups] revision:revision error:error]) {
        _links = previous;
        return NO;
    }
    _manifestRevision = revision;
    _manifestFormat = ManifestFormat;
    return YES;
}

#pragma mark - Recovery and migration

- (BOOL)recoverManifestIfNeeded:(NSError **)error {
    _recoveredInterruptedWrite = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    // An interrupted package update first: it holds folders, not just a file.
    NSString *updateJournal = [_support stringByAppendingPathComponent:UpdateJournalName];
    if ([fm fileExistsAtPath:updateJournal]) {
        [self rollbackUpdateJournal:updateJournal error:NULL];
        _recoveredInterruptedWrite = YES;
    }
    NSString *journal = [_support stringByAppendingPathComponent:JournalName];
    if (![fm fileExistsAtPath:journal]) return YES;
    NSDictionary *current = [self parsedManifest:[self manifestData]];
    BOOL completed = current && [current[@"format"] integerValue] == ManifestFormat &&
                     [self validPackages:current[@"packages"]];
    if (!completed) {
        // The new-format write did not finish. Put the previous bytes back, so the user sees the
        // packages that were there before rather than an empty Add-ons page. The journal names
        // the backup it took, so a migrated format-2 manifest is restored from its own copy.
        NSDictionary *note = [self parsedManifest:[NSData dataWithContentsOfFile:journal]];
        NSString *backupName = [note[@"backup"] isKindOfClass:NSString.class] ? note[@"backup"] : BackupNameV1;
        NSData *backup = [NSData dataWithContentsOfFile:[_support stringByAppendingPathComponent:backupName]];
        if (backup.length) {
            NSError *restore = nil;
            if (![backup writeToFile:[self manifestPath] options:NSDataWritingAtomic error:&restore]) {
                if (error) *error = restore;
                return NO;
            }
            _recoveredInterruptedWrite = YES;
        }
    }
    [fm removeItemAtPath:journal error:NULL];
    if (_recoveredInterruptedWrite)
        TKAddonHubLog(TKAddonHubEventRecovery, @{ TKAddonHubKeyOutcome: @"recovered",
                                                   TKAddonHubKeyReason: @"interrupted-write" });
    return YES;
}

// Every older format -> format 3, with a backup of the exact old bytes and a journal that
// survives a crash. Nothing is written until every migrated record validates.
//
// Format 2 added identity; format 3 adds the normalized record. Provenance is *recorded*, never
// guessed: an existing record with a CurseForge identity came in through the API client, and one
// without came in as files this app imported. Both are facts about how it arrived, and the
// migration states them rather than inventing a route the app did not have.
- (BOOL)migrateManifestIfNeeded:(NSError **)error {
    NSData *data = [self manifestData];
    NSDictionary *value = [self parsedManifest:data];
    if (!value) return YES;
    NSInteger from = [value[@"format"] integerValue];
    if (from < 1 || from >= ManifestFormat) return YES;
    NSArray *packages = [value[@"packages"] isKindOfClass:NSArray.class] ? value[@"packages"] : @[];
    NSMutableArray *migrated = [NSMutableArray array];
    for (id item in packages) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        if (![item[@"identifier"] isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *copy = [item mutableCopy];
        if (![copy[@"uuid"] isKindOfClass:NSString.class]) copy[@"uuid"] = NSUUID.UUID.UUIDString;
        if (![copy[@"folders"] isKindOfClass:NSArray.class]) copy[@"folders"] = @[];
        NSMutableArray *all = [NSMutableArray array];
        NSString *firstTOC = nil;
        for (NSString *folder in copy[@"folders"]) {
            if (![folder isKindOfClass:NSString.class]) continue;
            NSString *toc = TOC([_directory stringByAppendingPathComponent:folder]);
            if (toc && !firstTOC) firstTOC = toc;
            for (NSString *each in Interfaces(toc)) if (![all containsObject:each]) [all addObject:each];
        }
        if (![copy[@"tocInterface"] isKindOfClass:NSArray.class] || ![copy[@"tocInterface"] count])
            copy[@"tocInterface"] = all;
        if (![copy[@"compatibility"] isKindOfClass:NSString.class])
            copy[@"compatibility"] = CompatibilityForInterfaces(copy[@"tocInterface"]);
        if (from < 3) {
            NSDictionary *provider = [copy[@"provider"] isKindOfClass:NSDictionary.class] ? copy[@"provider"] : nil;
            if (!TKAddonProvenanceIsValid(copy[@"provenance"]))
                copy[@"provenance"] = TKAddonProviderIsCurseForge(provider) ? TKAddonProvenanceAPI
                                                                          : TKAddonProvenanceFiles;
            // Format 2 stored the archive digest under its old name. It becomes the record's
            // digest so the audit reads one field whichever format wrote it.
            if (![copy[@"digest"] isKindOfClass:NSString.class] && [copy[@"archiveSHA256"] isKindOfClass:NSString.class])
                copy[@"digest"] = copy[@"archiveSHA256"];
            [copy removeObjectForKey:@"archiveSHA256"];
            if (![copy[@"author"] isKindOfClass:NSString.class] && firstTOC) {
                NSString *author = Value(firstTOC, @"Author:");
                if (author.length) copy[@"author"] = author;
            }
            NSString *uuid = [copy[@"uuid"] isKindOfClass:NSString.class] ? copy[@"uuid"] : @"";
            NSString *name = [copy[@"name"] isKindOfClass:NSString.class] ? copy[@"name"] : @"";
            if (![copy[@"iconCacheKey"] isKindOfClass:NSString.class]) copy[@"iconCacheKey"] = IconKey(uuid, name);
            // An install time is not invented: a format-2 manifest never recorded one, and a
            // folder's modification date is when something last touched it, not when it arrived.
            if (!CleanInstant(copy[@"installedAt"])) [copy removeObjectForKey:@"installedAt"];
            if (!CleanInstant(copy[@"lastCheckedAt"])) [copy removeObjectForKey:@"lastCheckedAt"];
            if (!CleanUpdateState(copy[@"lastUpdateState"])) [copy removeObjectForKey:@"lastUpdateState"];
        }
        [migrated addObject:copy];
    }
    if (![self validPackages:migrated]) return Fail(error, @"The stored add-on manifest could not be migrated.");
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *failure = nil;
    if (![fm createDirectoryAtPath:_support withIntermediateDirectories:YES attributes:nil error:&failure])
        return Fail(error, failure.localizedDescription ?: @"The add-on support folder could not be created.");
    NSString *backupName = from == 1 ? BackupNameV1 : BackupNameV2;
    NSString *backup = [_support stringByAppendingPathComponent:backupName];
    if (![data writeToFile:backup options:NSDataWritingAtomic error:&failure])
        return Fail(error, failure.localizedDescription ?: @"The old add-on manifest could not be backed up.");
    NSInteger revision = [value[@"revision"] integerValue] + 1;
    NSDictionary *journal = @{ @"from": @(from), @"to": @(ManifestFormat), @"revision": @(revision),
                               @"backup": backupName };
    NSData *journalData = [NSJSONSerialization dataWithJSONObject:journal options:NSJSONWritingSortedKeys error:NULL];
    NSString *journalPath = [_support stringByAppendingPathComponent:JournalName];
    if (!journalData || ![journalData writeToFile:journalPath options:NSDataWritingAtomic error:&failure])
        return Fail(error, failure.localizedDescription ?: @"The migration journal could not be written.");
    NSMutableSet<NSString *> *identities = [NSMutableSet new];
    for (NSDictionary *item in migrated)
        if ([item[@"uuid"] isKindOfClass:NSString.class]) [identities addObject:item[@"uuid"]];
    if (![self savePackages:migrated groups:[self parsedGroups:value[@"groups"] knownIdentities:identities]
                   revision:revision error:&failure]) {
        // Leave the old bytes in place; the journal goes so the next read retries cleanly.
        [fm removeItemAtPath:journalPath error:NULL];
        return Fail(error, failure.localizedDescription ?: @"The migrated add-on manifest could not be written.");
    }
    [fm removeItemAtPath:journalPath error:NULL];
    TKAddonHubLog(TKAddonHubEventRecordMigration, @{
        TKAddonHubKeyOutcome: @"committed",
        TKAddonHubKeyReason: [NSString stringWithFormat:@"v%ld-to-v%ld", (long)from, (long)ManifestFormat],
        TKAddonHubKeyCount: @(migrated.count) });
    return YES;
}

#pragma mark - Reload

// A manifest that parsed but is not usable is kept, once, before anything can rewrite it. It is
// the only copy of whatever the player had, and "the Add-ons page is empty" is a much worse
// answer than "here are the bytes, they can be read by hand".
- (void)preserveCorruptManifestIfNeeded {
    NSData *data = [self manifestData];
    if (!data.length) return;
    NSDictionary *value = [self parsedManifest:data];
    NSInteger format = value ? [value[@"format"] integerValue] : 0;
    BOOL usable = value && (format == 1 || format == 2 || format == ManifestFormat || format > ManifestFormat);
    if (format == ManifestFormat || format == 1 || format == 2) usable = [self validPackages:value[@"packages"]];
    if (usable) return;
    NSString *path = [_support stringByAppendingPathComponent:CorruptName];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) return;
    [NSFileManager.defaultManager createDirectoryAtPath:_support withIntermediateDirectories:YES attributes:nil error:NULL];
    [data writeToFile:path options:NSDataWritingAtomic error:NULL];
}

- (void)reload {
    [self recoverManifestIfNeeded:NULL];
    [self preserveCorruptManifestIfNeeded];
    [self migrateManifestIfNeeded:NULL];
    NSDictionary *manifest = [self manifest];
    NSInteger format = [manifest[@"format"] integerValue];
    BOOL current = format == ManifestFormat;
    _manifestReadOnly = format > ManifestFormat;
    _manifestFormat = current ? ManifestFormat : format;
    _manifestRevision = current ? [manifest[@"revision"] integerValue] : 0;
    NSMutableDictionary *owned=[NSMutableDictionary new];
    for(id item in manifest[@"packages"])if([item isKindOfClass:NSDictionary.class]&&[item[@"identifier"] isKindOfClass:NSString.class])owned[item[@"identifier"]]=item;
    NSMutableArray *found=[NSMutableArray new];
    NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:_directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for(NSString *folder in names) { if([folder hasPrefix:@"."])continue;NSString *path=[_directory stringByAppendingPathComponent:folder];BOOL isDirectory=NO;if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]||!isDirectory)continue;NSString *toc=TOC(path);if(!toc)continue;
        NSDictionary *item=owned[folder];TKAddonRecord *record=[TKAddonRecord new];record.identifier=folder;record.name=Value(toc,@"Title:")?:folder;record.version=Value(toc,@"Version:")?:WKLocalized(@"addons.version.unknown");record.author=Value(toc,@"Author:");record.source=item?@"WolkaraForever import":@"Existing";record.folders=item[@"folders"]?:@[folder];record.managed=item!=nil;record.disabled=NO;record.pinned=[item[@"pinned"] boolValue];
        record.uuid=[item[@"uuid"] isKindOfClass:NSString.class]?item[@"uuid"]:folder;
        record.provider=CleanProvider(item[@"provider"]);
        // A package this store never imported has no acquisition route to claim: it was found.
        record.provenance=TKAddonProvenanceIsValid(item[@"provenance"])?item[@"provenance"]:(item?TKAddonProvenanceFiles:TKAddonProvenanceUnmanaged);
        record.digest=[item[@"digest"] isKindOfClass:NSString.class]?item[@"digest"]:nil;
        record.iconCacheKey=[item[@"iconCacheKey"] isKindOfClass:NSString.class]?item[@"iconCacheKey"]:IconKey(record.uuid,record.name);
        record.installedAt=CleanInstant(item[@"installedAt"]);
        record.lastCheckedAt=CleanInstant(item[@"lastCheckedAt"]);
        record.lastUpdateState=CleanUpdateState(item[@"lastUpdateState"]);
        record.sourceURL=[item[@"sourceURL"] isKindOfClass:NSString.class]?item[@"sourceURL"]:nil;
        NSArray *tocInterfaces = Interfaces(toc);
        record.tocInterface=[item[@"tocInterface"] isKindOfClass:NSArray.class]?item[@"tocInterface"]:tocInterfaces;
        record.compatibility=[item[@"compatibility"] isKindOfClass:NSString.class]?item[@"compatibility"]:CompatibilityForInterfaces(record.tocInterface.count?record.tocInterface:tocInterfaces);
        [found addObject:record]; }
    for (NSDictionary *item in manifest[@"packages"]) { if (!Managed(item) || ![item[@"disabled"] boolValue]) continue;
        TKAddonRecord *record=[TKAddonRecord new]; record.identifier=item[@"identifier"]; record.name=item[@"name"]?:record.identifier; record.version=item[@"version"]?:WKLocalized(@"addons.version.unknown"); record.source=@"WolkaraForever import"; record.folders=item[@"folders"]; record.managed=YES; record.disabled=YES; record.pinned=[item[@"pinned"] boolValue];
        record.uuid=[item[@"uuid"] isKindOfClass:NSString.class]?item[@"uuid"]:record.identifier;
        record.provider=CleanProvider(item[@"provider"]);
        record.provenance=TKAddonProvenanceIsValid(item[@"provenance"])?item[@"provenance"]:TKAddonProvenanceFiles;
        record.author=[item[@"author"] isKindOfClass:NSString.class]?item[@"author"]:nil;
        record.digest=[item[@"digest"] isKindOfClass:NSString.class]?item[@"digest"]:nil;
        record.iconCacheKey=[item[@"iconCacheKey"] isKindOfClass:NSString.class]?item[@"iconCacheKey"]:IconKey(record.uuid,record.name);
        record.installedAt=CleanInstant(item[@"installedAt"]);
        record.lastCheckedAt=CleanInstant(item[@"lastCheckedAt"]);
        record.lastUpdateState=CleanUpdateState(item[@"lastUpdateState"]);
        record.sourceURL=[item[@"sourceURL"] isKindOfClass:NSString.class]?item[@"sourceURL"]:nil;
        record.tocInterface=[item[@"tocInterface"] isKindOfClass:NSArray.class]?item[@"tocInterface"]:@[];
        record.compatibility=[item[@"compatibility"] isKindOfClass:NSString.class]?item[@"compatibility"]:TKAddonCompatibilityUnverified;
        [found addObject:record];
    }
    _records=found;
    NSMutableSet<NSString *> *identities=[NSMutableSet new];
    for (TKAddonRecord *record in found) if (record.uuid.length) [identities addObject:record.uuid];
    _groups=[self parsedGroups:manifest[@"groups"] knownIdentities:identities];
    _links=[self parsedLinks:manifest[@"links"]];
    // A link is how a folder this store never imported carries a project identity. It is applied
    // to the record on read, so every later reader sees the same facts whichever route the
    // package arrived by.
    for (NSDictionary *link in _links) {
        NSString *folder=[link[@"folder"] isKindOfClass:NSString.class]?link[@"folder"]:nil;
        if (!folder.length) continue;
        for (TKAddonRecord *record in found) {
            if (record.managed || ![record.identifier isEqual:folder]) continue;
            record.provider=CleanProvider(link[@"provider"]);
            if (TKAddonProvenanceIsValid(link[@"provenance"])) record.provenance=link[@"provenance"];
            record.lastCheckedAt=CleanInstant(link[@"lastCheckedAt"]);
            record.lastUpdateState=CleanUpdateState(link[@"lastUpdateState"]);
            if ([link[@"sourceURL"] isKindOfClass:NSString.class]) record.sourceURL=link[@"sourceURL"];
            break;
        }
    }
}

#pragma mark - Locking and validation

- (int)lock:(NSError **)error {
    NSString *root=[[_directory stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    return TKWoWAcquireUpdateLock(root,error);
}
// Structural validation only.
//
// What used to be here was a version gate: a ZIP whose TOC did not declare interface 16001 was
// refused, and a project with no 1.60.1 file was refused before anything was downloaded. Both
// turned a piece of advice into a denial of the user's own files. What must still be true is
// that the package is a real add-on: a readable TOC, at least one folder, nothing unsafe.
- (BOOL)validatePackageFolders:(NSArray<NSString *> *)folders from:(NSString *)extract
                    interfaces:(NSArray<NSString *> *_Nullable *_Nullable)interfaces
                 compatibility:(NSString *_Nullable *_Nullable)compatibility
                         error:(NSError **)error {
    if (!folders.count) return Fail(error, @"The ZIP contains no add-on folder with a .toc manifest.");
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    for (NSString *name in folders) {
        if (![name isKindOfClass:NSString.class] || !name.length || [name containsString:@"/"] ||
            [name isEqual:@"."] || [name isEqual:@".."])
            return Fail(error, [NSString stringWithFormat:@"%@ is not a usable add-on folder name.", name]);
        NSString *toc = TOC([extract stringByAppendingPathComponent:name]);
        if (!toc) return Fail(error, [NSString stringWithFormat:@"%@ has no readable .toc manifest.", name]);
        for (NSString *each in Interfaces(toc)) if (![all containsObject:each]) [all addObject:each];
    }
    if (interfaces) *interfaces = all;
    if (compatibility) *compatibility = CompatibilityForInterfaces(all);
    return YES;
}

#pragma mark - Manifest mutation

- (NSMutableArray *)mutablePackages { return [[self manifest][@"packages"] mutableCopy]?:[NSMutableArray new]; }- (BOOL)writePackages:(NSArray *)packages error:(NSError **)error {
    NSInteger revision = _manifestRevision + 1;
    if (![self saveManifest:packages revision:revision error:error]) return NO;
    _manifestRevision = revision;
    _manifestFormat = ManifestFormat;
    return YES;
}
- (NSDictionary *)packageForRecord:(TKAddonRecord *)record packages:(NSArray *)packages index:(NSUInteger *)index {
    for (NSUInteger i=0;i<packages.count;i++) {
        NSDictionary *item = packages[i];
        if (![item isKindOfClass:NSDictionary.class]) continue;
        // The stable identity wins, because an update can legitimately change which folders a
        // package owns while remaining the same package.
        if (record.uuid.length && [item[@"uuid"] isEqual:record.uuid]) { if(index)*index=i; return item; }
        if ([item[@"identifier"] isEqual:record.identifier]) { if(index)*index=i; return item; }
    }
    return nil;
}

#pragma mark - Import

// The extractor the app ships is Swift; the fixture substitutes a class of the same name, which
// is why it is found by name rather than linked.
- (BOOL)extractArchiveAtURL:(NSURL *)url into:(NSString *)destination error:(NSError **)error {
    Class archiveClass=NSClassFromString(@"TKAddonArchive");SEL selector=NSSelectorFromString(@"extractArchiveAtURL:toDirectoryURL:error:");
    if(!archiveClass||![archiveClass respondsToSelector:selector])return Fail(error,@"ZIP support is unavailable in this build.");
    BOOL (*extractor)(id,SEL,NSURL *,NSURL *,NSError **)= (void *)objc_msgSend;
    return extractor(archiveClass,selector,url,[NSURL fileURLWithPath:destination],error);
}
// The folders an extraction produced, looking inside a single wrapper directory when the
// archive was packed that way. Returns the directory those folders are actually in.
- (NSArray<NSString *> *)foldersIn:(NSString *)extract root:(NSString **)outRoot error:(NSError **)error {
    NSArray *top=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:extract error:error] sortedArrayUsingSelector:@selector(compare:)];NSMutableArray *folders=[NSMutableArray new];
    NSString *root = extract;
    for(NSString *name in top){NSString *path=[extract stringByAppendingPathComponent:name];if(TOC(path))[folders addObject:name];}
    if(!folders.count&&top.count==1){NSString *wrapper=[extract stringByAppendingPathComponent:top[0]];for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:wrapper error:NULL])if(TOC([wrapper stringByAppendingPathComponent:name]))[folders addObject:name];if(folders.count)root=wrapper;}
    if (outRoot) *outRoot = root;
    return folders;
}

- (BOOL)importZIPAtURL:(NSURL *)url error:(NSError **)error {
    return [self importZIPAtURL:url provider:nil provenance:TKAddonProvenanceFiles error:error];
}
- (BOOL)importZIPAtURL:(NSURL *)url provider:(NSDictionary *)provider error:(NSError **)error {
    return [self importZIPAtURL:url provider:provider provenance:TKAddonProvenanceFiles error:error];
}
- (BOOL)importZIPAtURL:(NSURL *)url provider:(NSDictionary *)provider
            provenance:(NSString *)provenance error:(NSError **)error {
    // An unknown route is refused rather than stored: provenance is what the audit reads back,
    // and a value this build cannot name is a value it must not claim on the record's behalf.
    NSString *route = TKAddonProvenanceIsValid(provenance) ? provenance : nil;
    if (!route) return Fail(error, @"That add-on's acquisition route is not one this app records.");
    NSData *archive=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];if(!archive||archive.length>128*1024*1024)return Fail(error,@"The selected ZIP is missing or exceeds the 128 MiB limit.");
    NSString *job=[_support stringByAppendingPathComponent:NSUUID.UUID.UUIDString],*extract=[job stringByAppendingPathComponent:@"extract"];
    if(![NSFileManager.defaultManager createDirectoryAtPath:job withIntermediateDirectories:YES attributes:nil error:error])return NO;
    @try {
    if (![self extractArchiveAtURL:url into:extract error:error]) return NO;
    NSString *root = extract;
    NSMutableArray *folders=[[self foldersIn:extract root:&root error:error] mutableCopy];
    if(!folders.count)return Fail(error,@"The ZIP contains no add-on folder with a .toc manifest.");
    NSArray<NSString *> *interfaces = nil; NSString *compatibility = nil;
    if(![self validatePackageFolders:folders from:root interfaces:&interfaces compatibility:&compatibility error:error])return NO;
    int lock=[self lock:error];if(lock<0)return NO;BOOL success=NO;
    // The folders this call actually created, so a failure cleans up after itself and
    // nothing else. The cleanup used to remove every folder in the import on any failure,
    // and the duplicate check returns through that path - so trying to install an add-on
    // that was already there deleted the one that was already there. Found by the fixture
    // in wolkaraforever/WoW/tests/test_wow_launcher_app.m, which is the coverage the audit asked
    // for; the manifest kept saying the package was owned while its folder was gone.
    NSMutableArray<NSString *> *created=[NSMutableArray new];
    @try { for(NSString *name in folders)if([NSFileManager.defaultManager fileExistsAtPath:[_directory stringByAppendingPathComponent:name]])return Fail(error,[NSString stringWithFormat:@"%@ already exists; remove or disable the managed package first.",name]);
        NSMutableArray *packages=[self mutablePackages];NSString *identifier=folders.firstObject;NSString *toc=TOC([root stringByAppendingPathComponent:identifier]);
        NSString *uuid=NSUUID.UUID.UUIDString, *name=Value(toc,@"Title:")?:identifier;
        NSMutableDictionary *item = [@{ @"identifier":identifier,@"uuid":uuid,@"name":name,@"version":Value(toc,@"Version:")?:@"Unknown version",@"source":@"zip",@"digest":Digest(archive),@"folders":folders,@"pinned":@NO,@"disabled":@NO,@"tocInterface":interfaces?:@[],@"compatibility":compatibility?:TKAddonCompatibilityUnverified,@"provenance":route,@"installedAt":CleanInstant([self now]),@"iconCacheKey":IconKey(uuid,name) } mutableCopy];
        NSString *author=Value(toc,@"Author:"); if (author.length) item[@"author"]=author;
        NSDictionary *clean = CleanProvider(provider);
        if (clean) item[@"provider"] = clean;
        [packages addObject:item];
        // The destination is recorded *before* the copy, not after. `copyItemAtPath:` can
        // fail with a half-written folder already in place, and the cleanup below only
        // knows the names in this list - so recording it afterwards left a stray folder
        // that the next reload would show as an add-on the user never installed. Nothing
        // but the cleanup reads this list: the manifest carries `folders`, so a failed
        // import still never claims a folder it did not install.
        for(NSString *name in folders) { [created addObject:name]; if(![NSFileManager.defaultManager copyItemAtPath:[root stringByAppendingPathComponent:name] toPath:[_directory stringByAppendingPathComponent:name] error:error])return NO; }
        if(![self writePackages:packages error:error])return NO;success=YES;[self reload];
        TKAddonHubLog(TKAddonHubEventArchive, @{ TKAddonHubKeyOutcome: @"imported",
            TKAddonHubKeyProvider: route, TKAddonHubKeyIdentifier: identifier,
            TKAddonHubKeyDigest: Digest(archive) });
        return YES;
    } @finally {TKWoWReleaseUpdateLock(lock);if(!success)for(NSString *name in created)[NSFileManager.defaultManager removeItemAtPath:[_directory stringByAppendingPathComponent:name] error:NULL];}
    } @finally { [NSFileManager.defaultManager removeItemAtPath:job error:NULL]; }
}

#pragma mark - Transactional package update

// Undo everything an interrupted update did. Folders first: the manifest is only meaningful
// once the tree it describes is back.
- (void)rollbackUpdateJournal:(NSString *)journalPath error:(NSError **)error {
    (void)error;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSData *data = [NSData dataWithContentsOfFile:journalPath];
    NSDictionary *record = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if ([record isKindOfClass:NSDictionary.class]) {
        NSString *base = [record[@"base"] isKindOfClass:NSString.class] ? record[@"base"] : _directory;
        NSString *previous = [record[@"previous"] isKindOfClass:NSString.class] ? record[@"previous"] : nil;
        NSArray *newFolders = [record[@"newFolders"] isKindOfClass:NSArray.class] ? record[@"newFolders"] : @[];
        NSArray *oldFolders = [record[@"oldFolders"] isKindOfClass:NSArray.class] ? record[@"oldFolders"] : @[];
        for (NSString *folder in newFolders) {
            if ([oldFolders containsObject:folder]) continue;   // handled with the old ones
            [fm removeItemAtPath:[base stringByAppendingPathComponent:folder] error:NULL];
        }
        if (previous) {
            for (NSString *folder in oldFolders) {
                NSString *destination = [base stringByAppendingPathComponent:folder];
                NSString *staged = [previous stringByAppendingPathComponent:folder];
                if (![fm fileExistsAtPath:staged]) continue;
                [fm removeItemAtPath:destination error:NULL];
                [fm moveItemAtPath:staged toPath:destination error:NULL];
            }
            [fm removeItemAtPath:previous error:NULL];
        }
        NSData *manifestBytes = [NSData dataWithContentsOfFile:[_support stringByAppendingPathComponent:UpdateBackupName]];
        if (manifestBytes.length) [manifestBytes writeToFile:[self manifestPath] options:NSDataWritingAtomic error:NULL];
    }
    [fm removeItemAtPath:[_support stringByAppendingPathComponent:UpdateBackupName] error:NULL];
    [fm removeItemAtPath:journalPath error:NULL];
    TKAddonHubLog(TKAddonHubEventRollback, @{ TKAddonHubKeyOutcome: @"restored",
        TKAddonHubKeyIdentifier: [record[@"identifier"] isKindOfClass:NSString.class] ? record[@"identifier"] : nil });
}

- (BOOL)updateRecord:(TKAddonRecord *)record archiveURL:(NSURL *)url
            provider:(NSDictionary *)provider error:(NSError **)error {
    return [self updateRecord:record archiveURL:url provider:provider
                   provenance:record.provenance error:error];
}
- (BOOL)updateRecord:(TKAddonRecord *)record archiveURL:(NSURL *)url
            provider:(NSDictionary *)provider provenance:(NSString *)provenance
               error:(NSError **)error {
    // A folder this store did not install may still be updated once the player has named its
    // project: that is an explicit ownership transfer, not a guess. Updating it adopts it, and
    // the same journal that protects a managed update protects this one, so a failure restores
    // the player's folder exactly as it was.
    if (!record.managed && !record.linked)
        return Fail(error, @"WolkaraForever only updates a folder it installed, or one you have linked to its project.");
    if (record.pinned) return Fail(error, @"This package is pinned. Unpin it before updating.");
    // An update records the route it arrived by unless the caller names one, and never invents
    // one: an unmanaged or unknown value leaves the record's own route in place.
    NSString *route = TKAddonProvenanceIsValid(provenance) ? provenance : nil;
    NSData *archive = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!archive || archive.length > 128*1024*1024)
        return Fail(error, @"The downloaded archive is missing or exceeds the 128 MiB limit.");
    // Everything that can be checked is checked before a single folder changes.
    NSString *job = [_support stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *extract = [job stringByAppendingPathComponent:@"extract"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:job withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    @try {
        if (![self extractArchiveAtURL:url into:extract error:error]) return NO;
        NSString *scanRoot = extract;
        NSMutableArray *newFolders = [[self foldersIn:extract root:&scanRoot error:error] mutableCopy];
        NSArray<NSString *> *interfaces = nil; NSString *compatibility = nil;
        if (![self validatePackageFolders:newFolders from:scanRoot interfaces:&interfaces compatibility:&compatibility error:error]) return NO;

        int lock = [self lock:error];
        if (lock < 0) return NO;
        BOOL committed = NO;
        @try {
            NSMutableArray *packages = [self mutablePackages];
            NSUInteger index = NSNotFound;
            NSMutableDictionary *item = [[self packageForRecord:record packages:packages index:&index] mutableCopy];
            BOOL adopting = (item == nil && record.linked && !record.managed);
            if (!item && !adopting) return Fail(error, @"The package ownership record is missing.");
            BOOL disabled = [item[@"disabled"] boolValue];
            NSString *base = disabled ? [[_support stringByAppendingPathComponent:@"disabled"] stringByAppendingPathComponent:record.identifier] : _directory;
            NSArray *oldFolders = [item[@"folders"] isKindOfClass:NSArray.class] ? item[@"folders"] : record.folders;
            if (![NSFileManager.defaultManager fileExistsAtPath:base])
                return Fail(error, @"The package's folders are not where the record says they are.");
            // A folder this package does not own must not be overwritten, and must not be
            // deleted afterwards either. Collisions are refused rather than resolved.
            for (NSString *folder in newFolders) {
                if ([oldFolders containsObject:folder]) continue;
                if ([NSFileManager.defaultManager fileExistsAtPath:[base stringByAppendingPathComponent:folder]])
                    return Fail(error, [NSString stringWithFormat:@"%@ already exists and does not belong to this package.", folder]);
            }
            NSString *previous = [job stringByAppendingPathComponent:@"previous"];
            if (![NSFileManager.defaultManager createDirectoryAtPath:previous withIntermediateDirectories:YES attributes:nil error:error]) return NO;
            NSInteger revision = _manifestRevision;
            NSData *manifestBackup = [self manifestData];
            if (manifestBackup.length && ![manifestBackup writeToFile:[_support stringByAppendingPathComponent:UpdateBackupName] options:NSDataWritingAtomic error:error]) return NO;
            NSDictionary *journal = @{ @"identifier": record.identifier, @"uuid": item[@"uuid"] ?: record.identifier,
                                       @"base": base, @"previous": previous, @"newFolders": newFolders,
                                       @"oldFolders": oldFolders, @"revision": @(revision) };
            NSData *journalData = [NSJSONSerialization dataWithJSONObject:journal options:NSJSONWritingSortedKeys error:error];
            NSString *journalPath = [_support stringByAppendingPathComponent:UpdateJournalName];
            if (!journalData || ![journalData writeToFile:journalPath options:NSDataWritingAtomic error:error]) return NO;

            // 1. Stage the folders this package owns aside.
            for (NSString *folder in oldFolders) {
                NSString *source = [base stringByAppendingPathComponent:folder];
                if (![NSFileManager.defaultManager fileExistsAtPath:source]) continue;
                if (![NSFileManager.defaultManager moveItemAtPath:source toPath:[previous stringByAppendingPathComponent:folder] error:error]) return NO;
            }
            // 2. Move the validated new folders in.
            for (NSString *folder in newFolders) {
                if (![NSFileManager.defaultManager copyItemAtPath:[scanRoot stringByAppendingPathComponent:folder]
                                                           toPath:[base stringByAppendingPathComponent:folder] error:error]) return NO;
            }
            // 3. Commit the manifest. Until this line the old record is still the truth, which
            //    is why the journal can always put the tree back.
            NSString *toc = TOC([base stringByAppendingPathComponent:newFolders.firstObject ?: record.identifier]);
            if (!item) {
                // The adopted record is created here, inside the transaction, so the manifest
                // never briefly describes a package the tree does not contain.
                item = [@{
                    @"identifier": record.identifier,
                    @"uuid": [record.uuid isKindOfClass:NSString.class] ? record.uuid : record.identifier,
                    @"source": @"zip",
                    @"pinned": @NO,
                    @"disabled": @NO,
                    @"provenance": record.provenance ?: TKAddonProvenanceFiles,
                } mutableCopy];
                NSUInteger adopted = packages.count;
                [packages addObject:item];
                index = adopted;
            }
            item[@"folders"] = newFolders;
            if (Value(toc, @"Title:")) item[@"name"] = Value(toc, @"Title:");
            if (Value(toc, @"Version:")) item[@"version"] = Value(toc, @"Version:");
            if (Value(toc, @"Author:")) item[@"author"] = Value(toc, @"Author:");
            item[@"digest"] = Digest(archive);
            [item removeObjectForKey:@"archiveSHA256"];
            item[@"tocInterface"] = interfaces ?: @[];
            item[@"compatibility"] = compatibility ?: TKAddonCompatibilityUnverified;
            item[@"pinned"] = @(record.pinned);
            item[@"disabled"] = @(disabled);
            item[@"installedAt"] = CleanInstant([self now]);
            // The package just changed, so whatever the last check concluded is no longer a
            // fact about it. A stale "up to date" is the one word the row must never carry.
            [item removeObjectForKey:@"lastUpdateState"];
            [item removeObjectForKey:@"lastCheckedAt"];
            if (![item[@"uuid"] isKindOfClass:NSString.class]) item[@"uuid"] = NSUUID.UUID.UUIDString;
            if (![item[@"iconCacheKey"] isKindOfClass:NSString.class])
                item[@"iconCacheKey"] = IconKey(item[@"uuid"], item[@"name"] ?: record.name);
            if (route) item[@"provenance"] = route;
            NSDictionary *clean = CleanProvider(provider);
            if (clean) item[@"provider"] = clean;
            packages[index] = item;
            if (![self writePackages:packages error:error]) return NO;
            committed = YES;
            // 4. The old folders are only removed once the manifest that stopped claiming them
            //    is on disk. A crash before this line leaves staging behind and is cleaned up
            //    on the next launch, with the new package already installed.
            [NSFileManager.defaultManager removeItemAtPath:previous error:NULL];
            [NSFileManager.defaultManager removeItemAtPath:journalPath error:NULL];
            [NSFileManager.defaultManager removeItemAtPath:[_support stringByAppendingPathComponent:UpdateBackupName] error:NULL];
            [self reload];
            TKAddonHubLog(TKAddonHubEventArchive, @{ TKAddonHubKeyOutcome: @"updated",
                TKAddonHubKeyProvider: item[@"provenance"] ?: record.provenance,
                TKAddonHubKeyIdentifier: record.identifier, TKAddonHubKeyDigest: Digest(archive) });
            return YES;
        } @finally {
            TKWoWReleaseUpdateLock(lock);
            if (!committed) {
                [self rollbackUpdateJournal:[_support stringByAppendingPathComponent:UpdateJournalName] error:NULL];
                [self reload];
            }
        }
    } @finally {
        [NSFileManager.defaultManager removeItemAtPath:job error:NULL];
    }
}

#pragma mark - State changes

- (BOOL)setDisabled:(BOOL)disabled record:(TKAddonRecord *)record error:(NSError **)error {
    if (!record.managed) return Fail(error,@"WolkaraForever only changes folders it installed.");
    int lock=[self lock:error]; if(lock<0)return NO; BOOL success=NO;
    @try { NSMutableArray *packages=[self mutablePackages]; NSUInteger index=NSNotFound; NSMutableDictionary *item=[[self packageForRecord:record packages:packages index:&index] mutableCopy]; if(!item)return Fail(error,@"The package ownership record is missing.");
        NSString *disabledRoot=[[_support stringByAppendingPathComponent:@"disabled"] stringByAppendingPathComponent:record.identifier]; NSFileManager *fm=NSFileManager.defaultManager;
        if(disabled) { if([fm fileExistsAtPath:disabledRoot])return Fail(error,@"A disabled copy already exists."); if(![fm createDirectoryAtPath:disabledRoot withIntermediateDirectories:YES attributes:nil error:error])return NO; for(NSString *folder in record.folders) { NSString *source=[_directory stringByAppendingPathComponent:folder]; if(![fm fileExistsAtPath:source]||![fm moveItemAtPath:source toPath:[disabledRoot stringByAppendingPathComponent:folder] error:error])return NO; } }
        else { for(NSString *folder in record.folders) { NSString *source=[disabledRoot stringByAppendingPathComponent:folder],*destination=[_directory stringByAppendingPathComponent:folder]; if([fm fileExistsAtPath:destination])return Fail(error,@"An existing folder blocks restore."); if(![fm moveItemAtPath:source toPath:destination error:error])return NO; } [fm removeItemAtPath:disabledRoot error:NULL]; }
        item[@"disabled"]=@(disabled); packages[index]=item; if(![self writePackages:packages error:error])return NO; success=YES; [self reload]; return YES;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
}
- (BOOL)removeRecord:(TKAddonRecord *)record error:(NSError **)error {
    int lock=[self lock:error];if(lock<0)return NO; BOOL success=NO;
    if (!record.managed) {
        // Existing add-ons are listed from their actual AddOns directory. Removal is limited to
        // that one current, top-level TOC folder and cannot cross the game directory boundary.
        NSFileManager *fm=NSFileManager.defaultManager;
        @try {
            if (record.folders.count != 1 || !SafeFolderName(record.folders.firstObject))
                return Fail(error,@"This add-on does not name one safe top-level folder.");
            NSString *path=[_directory stringByAppendingPathComponent:record.folders.firstObject];
            if (!TOC(path)) return Fail(error,@"The selected add-on folder no longer has a readable .toc manifest.");
            if (![fm removeItemAtPath:path error:error]) return NO;
            success=YES; [self reload]; return YES;
        } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
    }
    // The ownership record is dropped *before* anything moves. The other order had one
    // bad state: folders already moved aside and the manifest still claiming them, which
    // is a package that has vanished while its record says it is installed. This way a
    // failed write moves nothing, and a failed move leaves an ordinary unmanaged folder
    // that the user still has - the recoverable half of the mistake, not the lost one.
    NSFileManager *fm=NSFileManager.defaultManager; NSString *identifier=record.identifier;
    @try { NSMutableArray *packages=[self mutablePackages];NSUInteger index=NSNotFound;NSDictionary *item=[self packageForRecord:record packages:packages index:&index];if(!item)return Fail(error,@"The package ownership record is missing.");NSString *base=[item[@"disabled"] boolValue]?[[_support stringByAppendingPathComponent:@"disabled"] stringByAppendingPathComponent:identifier]:_directory;[packages removeObjectAtIndex:index];if(![self writePackages:packages error:error])return NO;NSString *previous=[[_support stringByAppendingPathComponent:@"previous"] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",identifier,NSUUID.UUID.UUIDString]];if(![fm createDirectoryAtPath:previous withIntermediateDirectories:YES attributes:nil error:error])return Fail(error,@"Nothing was installed by that name any more. There was nothing to move; the folders are still in the add-on directory.");for(NSString *folder in record.folders){NSString *source=[base stringByAppendingPathComponent:folder];if([fm fileExistsAtPath:source]&&![fm moveItemAtPath:source toPath:[previous stringByAppendingPathComponent:folder] error:error])return Fail(error,@"The package is no longer managed, and its folders could not be set aside. They are still in the add-on directory; remove them by hand.");}NSString *keeping=previous.lastPathComponent,*root=previous.stringByDeletingLastPathComponent;for(NSString *name in [fm contentsOfDirectoryAtPath:root error:NULL])if([name hasPrefix:[identifier stringByAppendingString:@"-"]]&&![name isEqual:keeping])[fm removeItemAtPath:[root stringByAppendingPathComponent:name] error:NULL];success=YES;[self reload];return YES; } @finally { TKWoWReleaseUpdateLock(lock);if(!success)[self reload]; }
}
- (BOOL)setPinned:(BOOL)pinned record:(TKAddonRecord *)record error:(NSError **)error { if(!record.managed)return Fail(error,@"Only managed packages can be pinned.");int lock=[self lock:error];if(lock<0)return NO;BOOL success=NO;@try {NSMutableArray *packages=[self mutablePackages];NSUInteger index=NSNotFound;NSMutableDictionary *item=[[self packageForRecord:record packages:packages index:&index] mutableCopy];if(!item)return Fail(error,@"The package ownership record is missing.");item[@"pinned"]=@(pinned);packages[index]=item;if(![self writePackages:packages error:error])return NO;[self reload];success=YES;return YES;} @finally {TKWoWReleaseUpdateLock(lock);if(!success)[self reload];} }

// The project's artwork, kept beside the identity the package already has.
//
// A package installed before thumbnails were recorded still names its project, so one batched
// provider query can fill every missing picture without touching anything a row acts on: the
// folders, the file identity and the update answer are left exactly as they were. Only the
// artwork key changes, and it is never the source of a decision.
- (BOOL)setProviderArtwork:(NSString *)logoURLString record:(TKAddonRecord *)record
                     error:(NSError **)error {
    if (![logoURLString isKindOfClass:NSString.class] || !logoURLString.length)
        return Fail(error, @"There is no artwork URL to keep.");
    int lock=[self lock:error]; if(lock<0) return NO; BOOL success=NO;
    @try {
        NSMutableArray *packages=[self mutablePackages];
        NSUInteger index=NSNotFound;
        NSMutableDictionary *item=[[self packageForRecord:record packages:packages index:&index] mutableCopy];
        if(item){
            NSMutableDictionary *provider=[item[@"provider"] isKindOfClass:NSDictionary.class]
                ? [item[@"provider"] mutableCopy] : [NSMutableDictionary dictionary];
            provider[@"logo"]=logoURLString;
            item[@"provider"]=provider;
            packages[index]=item;
            if(![self writePackages:packages error:error])return NO;
            [self reload];success=YES;return YES;
        }
        // A folder this store does not own keeps its identity in the link table beside the
        // ownership records, so its artwork belongs there too. Only the artwork key changes:
        // the link, the project and the folder stay exactly as the player left them.
        NSMutableArray *links=[self mutableLinks];
        NSUInteger existing=NSNotFound;
        for (NSUInteger i=0;i<links.count;i++) {
            if (![links[i] isKindOfClass:NSDictionary.class]) continue;
            if ((record.uuid.length && [links[i][@"uuid"] isEqual:record.uuid]) ||
                [links[i][@"folder"] isEqual:record.identifier]) { existing=i; break; }
        }
        if(existing==NSNotFound) return Fail(error,@"That add-on has no linked project to keep artwork for.");
        NSMutableDictionary *link=[links[existing] mutableCopy];
        NSMutableDictionary *provider=[link[@"provider"] isKindOfClass:NSDictionary.class]
            ? [link[@"provider"] mutableCopy] : [NSMutableDictionary dictionary];
        provider[@"logo"]=logoURLString;
        link[@"provider"]=provider;
        links[existing]=link;
        if(![self writeLinks:links packages:packages error:error])return NO;
        [self reload];success=YES;return YES;
    } @finally {TKWoWReleaseUpdateLock(lock);if(!success)[self reload];}
}

#pragma mark - Source linking

- (NSString *)now {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSISO8601DateFormatter new]; });
    return [formatter stringFromDate:NSDate.date];
}

// The player naming the project a package belongs to. Nothing on disk is touched - the folders
// are exactly as they were and keep running - and only a project identity this store can update
// from is accepted. A folder name is not a project, and this method never looks at one.
- (BOOL)linkRecord:(TKAddonRecord *)record provider:(NSDictionary *)provider
        provenance:(NSString *)provenance error:(NSError **)error {
    NSDictionary *clean = CleanProvider(provider);
    if (!TKAddonProviderIsCurseForge(clean))
        return Fail(error, @"That is not a CurseForge project this app can update from.");
    NSString *route = TKAddonProvenanceIsValid(provenance) ? provenance : nil;
    if (!route) return Fail(error, @"That add-on's acquisition route is not one this app records.");
    int lock=[self lock:error]; if(lock<0) return NO; BOOL success=NO;
    @try {
        NSMutableArray *packages=[self mutablePackages];
        NSUInteger index=NSNotFound;
        NSMutableDictionary *item=[[self packageForRecord:record packages:packages index:&index] mutableCopy];
        if (item) {
            item[@"provider"]=clean;
            item[@"provenance"]=route;
            item[@"sourceURL"]=[clean[@"projectSlug"] isKindOfClass:NSString.class]
                ? [@"https://www.curseforge.com/wow/addons/" stringByAppendingString:clean[@"projectSlug"]]
                : nil;
            if (!item[@"sourceURL"]) [item removeObjectForKey:@"sourceURL"];
            [item removeObjectForKey:@"lastUpdateState"];
            [item removeObjectForKey:@"lastCheckedAt"];
            packages[index]=item;
        } else {
            // A folder this store does not own still gets a link, kept beside the ownership
            // records rather than inside them: the record says which project it is, and the
            // folder stays the player's file.
            NSMutableArray *links=[self mutableLinks];
            NSMutableDictionary *link=[NSMutableDictionary dictionary];
            link[@"folder"]=record.identifier;
            link[@"uuid"]=record.uuid ?: record.identifier;
            link[@"provider"]=clean;
            link[@"provenance"]=route;
            link[@"linkedAt"]=CleanInstant([self now]);
            NSUInteger existing=NSNotFound;
            for (NSUInteger i=0;i<links.count;i++)
                if ([links[i] isKindOfClass:NSDictionary.class] && [links[i][@"uuid"] isEqual:link[@"uuid"]]) { existing=i; break; }
            if (existing!=NSNotFound) links[existing]=link; else [links addObject:link];
            if (![self writeLinks:links packages:packages error:error]) return NO;
            [self reload]; success=YES;
            TKAddonHubLog(TKAddonHubEventSource, @{ TKAddonHubKeyOutcome: @"linked",
                TKAddonHubKeyProvider: route, TKAddonHubKeyIdentifier: record.identifier,
                TKAddonHubKeyAction: @"found-on-disk" });
            return YES;
        }
        if (![self writePackages:packages error:error]) return NO;
        [self reload]; success=YES;
        TKAddonHubLog(TKAddonHubEventSource, @{ TKAddonHubKeyOutcome: @"linked",
            TKAddonHubKeyProvider: route, TKAddonHubKeyIdentifier: record.identifier });
        return YES;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
}

- (BOOL)unlinkRecord:(TKAddonRecord *)record error:(NSError **)error {
    int lock=[self lock:error]; if(lock<0) return NO; BOOL success=NO;
    @try {
        NSMutableArray *packages=[self mutablePackages];
        NSUInteger index=NSNotFound;
        NSMutableDictionary *item=[[self packageForRecord:record packages:packages index:&index] mutableCopy];
        if (item) {
            [item removeObjectForKey:@"provider"];
            [item removeObjectForKey:@"sourceURL"];
            [item removeObjectForKey:@"lastUpdateState"];
            [item removeObjectForKey:@"lastCheckedAt"];
            packages[index]=item;
            if (![self writePackages:packages error:error]) return NO;
            [self reload]; success=YES; return YES;
        }
        NSMutableArray *links=[self mutableLinks];
        NSUInteger existing=NSNotFound;
        for (NSUInteger i=0;i<links.count;i++)
            if ([links[i] isKindOfClass:NSDictionary.class] && [links[i][@"uuid"] isEqual:record.uuid]) { existing=i; break; }
        if (existing==NSNotFound) return Fail(error, @"That add-on has no linked project.");
        [links removeObjectAtIndex:existing];
        if (![self writeLinks:links packages:packages error:error]) return NO;
        [self reload]; success=YES; return YES;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
}

#pragma mark - Update state

- (BOOL)setUpdateStates:(NSDictionary<NSString *, NSString *> *)states
              checkedAt:(NSString *)checkedAt error:(NSError **)error {
    if (!states.count) return YES;
    int lock=[self lock:error]; if(lock<0) return NO; BOOL success=NO;
    @try {
        NSMutableArray *packages=[self mutablePackages];
        BOOL changed=NO;
        for (NSUInteger i=0;i<packages.count;i++) {
            NSDictionary *item=packages[i];
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *uuid=[item[@"uuid"] isKindOfClass:NSString.class]?item[@"uuid"]:item[@"identifier"];
            if (![uuid isKindOfClass:NSString.class] || !states[uuid]) continue;
            NSMutableDictionary *copy=[item mutableCopy];
            NSString *state=states[uuid];
            NSString *clean=CleanUpdateState(state);
            if (clean) copy[@"lastUpdateState"]=clean; else [copy removeObjectForKey:@"lastUpdateState"];
            if (checkedAt) copy[@"lastCheckedAt"]=checkedAt; else [copy removeObjectForKey:@"lastCheckedAt"];
            packages[i]=copy; changed=YES;
        }
        // A Files/unmanaged record has no ownership entry, so its link entry carries the state.
        NSMutableArray *links=[self mutableLinks];
        for (NSUInteger i=0;i<links.count;i++) {
            NSDictionary *link=links[i];
            if (![link isKindOfClass:NSDictionary.class]) continue;
            NSString *uuid=[link[@"uuid"] isKindOfClass:NSString.class]?link[@"uuid"]:link[@"folder"];
            if (![uuid isKindOfClass:NSString.class] || !states[uuid]) continue;
            NSMutableDictionary *copy=[link mutableCopy];
            NSString *clean=CleanUpdateState(states[uuid]);
            if (clean) copy[@"lastUpdateState"]=clean; else [copy removeObjectForKey:@"lastUpdateState"];
            if (checkedAt) copy[@"lastCheckedAt"]=checkedAt; else [copy removeObjectForKey:@"lastCheckedAt"];
            links[i]=copy; changed=YES;
        }
        if (!changed) return YES;
        if (![self writeLinks:links packages:packages error:error]) return NO;
        [self reload]; success=YES; return YES;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
}

#pragma mark - Groups

- (NSMutableArray *)mutableGroups {
    NSMutableArray *groups=[NSMutableArray array];
    for (TKAddonGroup *group in _groups ?: @[]) {
        [groups addObject:[@{ @"id": group.identifier, @"name": group.name,
                              @"members": group.members ?: @[] } mutableCopy]];
    }
    return groups;
}

// Groups are stored in the same file as the packages, so one commit changes both and the
// revision counts either. A group is never a claim about a file.
- (BOOL)writeGroups:(NSArray *)groups error:(NSError **)error {
    NSInteger revision = _manifestRevision + 1;
    if (![self savePackages:[self mutablePackages] groups:groups revision:revision error:error]) return NO;
    _manifestRevision = revision;
    _manifestFormat = ManifestFormat;
    return YES;
}

- (TKAddonGroup *)createGroupNamed:(NSString *)name error:(NSError **)error {
    NSString *trimmed=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length>120) { Fail(error, @"A group needs a name of at most 120 characters."); return nil; }
    int lock=[self lock:error]; if(lock<0) return nil;
    TKAddonGroup *created=nil;
    @try {
        NSMutableArray *groups=[self mutableGroups];
        for (NSDictionary *item in groups)
            if ([item[@"name"] isKindOfClass:NSString.class] &&
                [item[@"name"] caseInsensitiveCompare:trimmed]==NSOrderedSame) {
                Fail(error, @"A group with that name already exists.");
                return nil;
            }
        NSString *identifier=NSUUID.UUID.UUIDString;
        [groups addObject:[@{ @"id": identifier, @"name": trimmed, @"members": @[] } mutableCopy]];
        if (![self writeGroups:groups error:error]) return nil;
        [self reload];
        for (TKAddonGroup *group in _groups) if ([group.identifier isEqual:identifier]) created=group;
        return created;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!created)[self reload]; }
}

- (BOOL)setGroup:(TKAddonGroup *)group member:(TKAddonRecord *)record joined:(BOOL)joined
           error:(NSError **)error {
    if (!group.identifier.length || !record.uuid.length)
        return Fail(error, @"A group holds packages, and this one names none.");
    int lock=[self lock:error]; if(lock<0) return NO; BOOL success=NO;
    @try {
        NSMutableArray *groups=[self mutableGroups];
        NSUInteger index=NSNotFound;
        for (NSUInteger i=0;i<groups.count;i++)
            if ([groups[i][@"id"] isEqual:group.identifier]) { index=i; break; }
        if (index==NSNotFound) return Fail(error, @"That group no longer exists.");
        NSMutableArray *members=[[groups[index][@"members"] isKindOfClass:NSArray.class]?groups[index][@"members"]:@[] mutableCopy];
        [members removeObject:record.uuid];
        if (joined) [members addObject:record.uuid];
        groups[index][@"members"]=members;
        if (![self writeGroups:groups error:error]) return NO;
        [self reload]; success=YES; return YES;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
}

- (BOOL)removeGroup:(TKAddonGroup *)group error:(NSError **)error {
    int lock=[self lock:error]; if(lock<0) return NO; BOOL success=NO;
    @try {
        NSMutableArray *groups=[self mutableGroups];
        NSUInteger index=NSNotFound;
        for (NSUInteger i=0;i<groups.count;i++)
            if ([groups[i][@"id"] isEqual:group.identifier]) { index=i; break; }
        if (index==NSNotFound) return Fail(error, @"That group no longer exists.");
        [groups removeObjectAtIndex:index];
        if (![self writeGroups:groups error:error]) return NO;
        [self reload]; success=YES; return YES;
    } @finally { TKWoWReleaseUpdateLock(lock); if(!success)[self reload]; }
}
@end
