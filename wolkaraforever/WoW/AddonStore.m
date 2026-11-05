#import "AddonStore.h"
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

NSString *const TKAddonCompatibilityVerified   = @"verified";
NSString *const TKAddonCompatibilityUnverified = @"unverified";

// The manifest this store writes. Format 1 stored a folder list and a digest; format 2 adds a
// stable package identity and an optional provider identity, which is what makes a per-package
// Update possible at all. The migration is journalled, so a process that dies between the
// backup and the format-2 write is recovered on the next launch instead of showing an Add-ons
// page built from half a manifest.
static NSString *const ManifestName      = @".wolkaraforever-addons.json";
static NSString *const JournalName       = @"manifest-journal.json";
static NSString *const BackupName        = @"manifest-v1-backup.json";
static NSString *const UpdateJournalName = @"update-journal.json";
static NSString *const UpdateBackupName  = @"update-manifest-backup.json";
static const NSInteger ManifestFormat    = 2;

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
// Only the six documented keys survive a write, so a stray value cannot be smuggled into the
// manifest through a provider dictionary.
static NSDictionary *CleanProvider(NSDictionary *provider) {
    if (![provider isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *copy = [NSMutableDictionary dictionary];
    for (NSString *key in @[TKAddonProviderKind, TKAddonProviderProjectID, TKAddonProviderFileID,
                            TKAddonProviderFileName, TKAddonProviderVersion,
                            TKAddonProviderPublishedDate, TKAddonProviderCompatibility]) {
        id value = provider[key];
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length) copy[key] = value;
        else if ([value isKindOfClass:NSNumber.class]) copy[key] = value;
    }
    return copy.count ? copy : nil;
}

BOOL TKAddonProviderIsCurseForge(NSDictionary *provider) {
    if (![provider isKindOfClass:NSDictionary.class]) return NO;
    if (![provider[TKAddonProviderKind] isEqual:@"curseforge"]) return NO;
    return [provider[TKAddonProviderProjectID] isKindOfClass:NSNumber.class] &&
           [provider[TKAddonProviderFileID] isKindOfClass:NSNumber.class];
}

@implementation TKAddonRecord
- (BOOL)providerUpdatable { return TKAddonProviderIsCurseForge(self.provider); }
@end

@implementation TKAddonStore {
    NSString *_directory, *_product, *_version, *_support;
    NSArray<TKAddonRecord *> *_records;
    NSInteger _manifestFormat;
    NSInteger _manifestRevision;
    BOOL _recoveredInterruptedWrite;
}

- (instancetype)initWithAddOnsDirectory:(NSString *)directory product:(NSString *)product gameVersion:(NSString *)version {
    if(!(self=[super init]))return nil;_directory=directory.copy;_product=product.copy;_version=version.copy?:@"unknown";
    NSString *base=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject;
    _support=[[[base stringByAppendingPathComponent:@"WolkaraForever/AddOns"] stringByAppendingPathComponent:_product] stringByAppendingPathComponent:Digest([directory dataUsingEncoding:NSUTF8StringEncoding])];[self reload];return self;
}
- (NSArray<TKAddonRecord *> *)records { return _records?:@[]; }
- (NSInteger)manifestFormat { return _manifestFormat; }
- (NSInteger)manifestRevision { return _manifestRevision; }
- (BOOL)recoveredInterruptedWrite { return _recoveredInterruptedWrite; }

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
    if (value && [value[@"format"] integerValue] == ManifestFormat) return value;
    if (value && [value[@"format"] integerValue] == 1) return value;   // not yet migrated
    return @{ @"format": @(ManifestFormat), @"revision": @0, @"packages": @[] };
}
- (BOOL)saveManifest:(NSArray *)packages revision:(NSInteger)revision error:(NSError **)error {
    NSDictionary *value=@{ @"format":@(ManifestFormat),@"product":_product,@"gameVersion":_version,
                           @"revision":@(revision),@"packages":packages };
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:error];
    if (!data) return NO;
    return [data writeToFile:[self manifestPath] options:NSDataWritingAtomic error:error];
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
        // The format-2 write did not finish. Put the format-1 bytes back, so the user sees the
        // packages that were there before rather than an empty Add-ons page.
        NSData *backup = [NSData dataWithContentsOfFile:[_support stringByAppendingPathComponent:BackupName]];
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
    return YES;
}

// Format 1 -> format 2, with a backup of the exact old bytes and a journal that survives a
// crash. Nothing is written until every migrated record validates.
- (BOOL)migrateManifestIfNeeded:(NSError **)error {
    NSData *data = [self manifestData];
    NSDictionary *value = [self parsedManifest:data];
    if (!value || [value[@"format"] integerValue] != 1) return YES;
    NSArray *packages = [value[@"packages"] isKindOfClass:NSArray.class] ? value[@"packages"] : @[];
    NSMutableArray *migrated = [NSMutableArray array];
    for (id item in packages) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        if (![item[@"identifier"] isKindOfClass:NSString.class]) continue;
        NSMutableDictionary *copy = [item mutableCopy];
        if (![copy[@"uuid"] isKindOfClass:NSString.class]) copy[@"uuid"] = NSUUID.UUID.UUIDString;
        if (![copy[@"folders"] isKindOfClass:NSArray.class]) copy[@"folders"] = @[];
        NSMutableArray *all = [NSMutableArray array];
        for (NSString *folder in copy[@"folders"]) {
            if (![folder isKindOfClass:NSString.class]) continue;
            NSString *toc = TOC([_directory stringByAppendingPathComponent:folder]);
            for (NSString *each in Interfaces(toc)) if (![all containsObject:each]) [all addObject:each];
        }
        if (![copy[@"tocInterface"] isKindOfClass:NSArray.class] || ![copy[@"tocInterface"] count])
            copy[@"tocInterface"] = all;
        if (![copy[@"compatibility"] isKindOfClass:NSString.class])
            copy[@"compatibility"] = CompatibilityForInterfaces(copy[@"tocInterface"]);
        [migrated addObject:copy];
    }
    if (![self validPackages:migrated]) return Fail(error, @"The stored add-on manifest could not be migrated.");
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *failure = nil;
    if (![fm createDirectoryAtPath:_support withIntermediateDirectories:YES attributes:nil error:&failure])
        return Fail(error, failure.localizedDescription ?: @"The add-on support folder could not be created.");
    NSString *backup = [_support stringByAppendingPathComponent:BackupName];
    if (![data writeToFile:backup options:NSDataWritingAtomic error:&failure])
        return Fail(error, failure.localizedDescription ?: @"The old add-on manifest could not be backed up.");
    NSInteger revision = [value[@"revision"] integerValue] + 1;
    NSDictionary *journal = @{ @"from": @1, @"to": @(ManifestFormat), @"revision": @(revision),
                               @"backup": BackupName };
    NSData *journalData = [NSJSONSerialization dataWithJSONObject:journal options:NSJSONWritingSortedKeys error:NULL];
    NSString *journalPath = [_support stringByAppendingPathComponent:JournalName];
    if (!journalData || ![journalData writeToFile:journalPath options:NSDataWritingAtomic error:&failure])
        return Fail(error, failure.localizedDescription ?: @"The migration journal could not be written.");
    if (![self saveManifest:migrated revision:revision error:&failure]) {
        // Leave the old bytes in place; the journal goes so the next read retries cleanly.
        [fm removeItemAtPath:journalPath error:NULL];
        return Fail(error, failure.localizedDescription ?: @"The migrated add-on manifest could not be written.");
    }
    [fm removeItemAtPath:journalPath error:NULL];
    return YES;
}

#pragma mark - Reload

- (void)reload {
    [self recoverManifestIfNeeded:NULL];
    [self migrateManifestIfNeeded:NULL];
    NSDictionary *manifest = [self manifest];
    BOOL current = [manifest[@"format"] integerValue] == ManifestFormat;
    _manifestFormat = current ? ManifestFormat : 1;
    _manifestRevision = current ? [manifest[@"revision"] integerValue] : 0;
    NSMutableDictionary *owned=[NSMutableDictionary new];
    for(id item in manifest[@"packages"])if([item isKindOfClass:NSDictionary.class]&&[item[@"identifier"] isKindOfClass:NSString.class])owned[item[@"identifier"]]=item;
    NSMutableArray *found=[NSMutableArray new];
    NSArray *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:_directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for(NSString *folder in names) { if([folder hasPrefix:@"."])continue;NSString *path=[_directory stringByAppendingPathComponent:folder];BOOL isDirectory=NO;if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]||!isDirectory)continue;NSString *toc=TOC(path);if(!toc)continue;
        NSDictionary *item=owned[folder];TKAddonRecord *record=[TKAddonRecord new];record.identifier=folder;record.name=Value(toc,@"Title:")?:folder;record.version=Value(toc,@"Version:")?:WKLocalized(@"addons.version.unknown");record.source=item?@"WolkaraForever import":@"Existing";record.folders=item[@"folders"]?:@[folder];record.managed=item!=nil;record.disabled=NO;record.pinned=[item[@"pinned"] boolValue];
        record.uuid=[item[@"uuid"] isKindOfClass:NSString.class]?item[@"uuid"]:folder;
        record.provider=CleanProvider(item[@"provider"]);
        NSArray *tocInterfaces = Interfaces(toc);
        record.tocInterface=[item[@"tocInterface"] isKindOfClass:NSArray.class]?item[@"tocInterface"]:tocInterfaces;
        record.compatibility=[item[@"compatibility"] isKindOfClass:NSString.class]?item[@"compatibility"]:CompatibilityForInterfaces(record.tocInterface.count?record.tocInterface:tocInterfaces);
        [found addObject:record]; }
    for (NSDictionary *item in manifest[@"packages"]) { if (!Managed(item) || ![item[@"disabled"] boolValue]) continue;
        TKAddonRecord *record=[TKAddonRecord new]; record.identifier=item[@"identifier"]; record.name=item[@"name"]?:record.identifier; record.version=item[@"version"]?:WKLocalized(@"addons.version.unknown"); record.source=@"WolkaraForever import"; record.folders=item[@"folders"]; record.managed=YES; record.disabled=YES; record.pinned=[item[@"pinned"] boolValue];
        record.uuid=[item[@"uuid"] isKindOfClass:NSString.class]?item[@"uuid"]:record.identifier;
        record.provider=CleanProvider(item[@"provider"]);
        record.tocInterface=[item[@"tocInterface"] isKindOfClass:NSArray.class]?item[@"tocInterface"]:@[];
        record.compatibility=[item[@"compatibility"] isKindOfClass:NSString.class]?item[@"compatibility"]:TKAddonCompatibilityUnverified;
        [found addObject:record];
    }
    _records=found;
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

- (NSMutableArray *)mutablePackages { return [[self manifest][@"packages"] mutableCopy]?:[NSMutableArray new]; }
- (BOOL)writePackages:(NSArray *)packages error:(NSError **)error {
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
    return [self importZIPAtURL:url provider:nil error:error];
}
- (BOOL)importZIPAtURL:(NSURL *)url provider:(NSDictionary *)provider error:(NSError **)error {
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
        NSMutableDictionary *item = [@{ @"identifier":identifier,@"uuid":NSUUID.UUID.UUIDString,@"name":Value(toc,@"Title:")?:identifier,@"version":Value(toc,@"Version:")?:@"Unknown version",@"source":@"zip",@"archiveSHA256":Digest(archive),@"folders":folders,@"pinned":@NO,@"disabled":@NO,@"tocInterface":interfaces?:@[],@"compatibility":compatibility?:TKAddonCompatibilityUnverified } mutableCopy];
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
        if(![self writePackages:packages error:error])return NO;success=YES;[self reload];return YES;
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
}

- (BOOL)updateRecord:(TKAddonRecord *)record archiveURL:(NSURL *)url
            provider:(NSDictionary *)provider error:(NSError **)error {
    if (!record.managed) return Fail(error, @"WolkaraForever only updates folders it installed.");
    if (record.pinned) return Fail(error, @"This package is pinned. Unpin it before updating.");
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
            if (!item) return Fail(error, @"The package ownership record is missing.");
            BOOL disabled = [item[@"disabled"] boolValue];
            NSString *base = disabled ? [[_support stringByAppendingPathComponent:@"disabled"] stringByAppendingPathComponent:record.identifier] : _directory;
            NSArray *oldFolders = [item[@"folders"] isKindOfClass:NSArray.class] ? item[@"folders"] : @[];
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
            item[@"folders"] = newFolders;
            if (Value(toc, @"Title:")) item[@"name"] = Value(toc, @"Title:");
            if (Value(toc, @"Version:")) item[@"version"] = Value(toc, @"Version:");
            item[@"archiveSHA256"] = Digest(archive);
            item[@"tocInterface"] = interfaces ?: @[];
            item[@"compatibility"] = compatibility ?: TKAddonCompatibilityUnverified;
            item[@"pinned"] = @(record.pinned);
            item[@"disabled"] = @(disabled);
            if (![item[@"uuid"] isKindOfClass:NSString.class]) item[@"uuid"] = NSUUID.UUID.UUIDString;
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
    if(!record.managed)return Fail(error,@"WolkaraForever only removes folders it installed."); int lock=[self lock:error];if(lock<0)return NO; BOOL success=NO;
    // The ownership record is dropped *before* anything moves. The other order had one
    // bad state: folders already moved aside and the manifest still claiming them, which
    // is a package that has vanished while its record says it is installed. This way a
    // failed write moves nothing, and a failed move leaves an ordinary unmanaged folder
    // that the user still has - the recoverable half of the mistake, not the lost one.
    NSFileManager *fm=NSFileManager.defaultManager; NSString *identifier=record.identifier;
    @try { NSMutableArray *packages=[self mutablePackages];NSUInteger index=NSNotFound;NSDictionary *item=[self packageForRecord:record packages:packages index:&index];if(!item)return Fail(error,@"The package ownership record is missing.");NSString *base=[item[@"disabled"] boolValue]?[[_support stringByAppendingPathComponent:@"disabled"] stringByAppendingPathComponent:identifier]:_directory;[packages removeObjectAtIndex:index];if(![self writePackages:packages error:error])return NO;NSString *previous=[[_support stringByAppendingPathComponent:@"previous"] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",identifier,NSUUID.UUID.UUIDString]];if(![fm createDirectoryAtPath:previous withIntermediateDirectories:YES attributes:nil error:error])return Fail(error,@"Nothing was installed by that name any more. There was nothing to move; the folders are still in the add-on directory.");for(NSString *folder in record.folders){NSString *source=[base stringByAppendingPathComponent:folder];if([fm fileExistsAtPath:source]&&![fm moveItemAtPath:source toPath:[previous stringByAppendingPathComponent:folder] error:error])return Fail(error,@"The package is no longer managed, and its folders could not be set aside. They are still in the add-on directory; remove them by hand.");}NSString *keeping=previous.lastPathComponent,*root=previous.stringByDeletingLastPathComponent;for(NSString *name in [fm contentsOfDirectoryAtPath:root error:NULL])if([name hasPrefix:[identifier stringByAppendingString:@"-"]]&&![name isEqual:keeping])[fm removeItemAtPath:[root stringByAppendingPathComponent:name] error:NULL];success=YES;[self reload];return YES; } @finally { TKWoWReleaseUpdateLock(lock);if(!success)[self reload]; }
}
- (BOOL)setPinned:(BOOL)pinned record:(TKAddonRecord *)record error:(NSError **)error { if(!record.managed)return Fail(error,@"Only managed packages can be pinned.");int lock=[self lock:error];if(lock<0)return NO;BOOL success=NO;@try {NSMutableArray *packages=[self mutablePackages];NSUInteger index=NSNotFound;NSMutableDictionary *item=[[self packageForRecord:record packages:packages index:&index] mutableCopy];if(!item)return Fail(error,@"The package ownership record is missing.");item[@"pinned"]=@(pinned);packages[index]=item;if(![self writePackages:packages error:error])return NO;[self reload];success=YES;return YES;} @finally {TKWoWReleaseUpdateLock(lock);if(!success)[self reload];} }
@end
