#import "AddonStore.h"
#import "AddonHubLog.h"
#include <stdio.h>

#define CHECK(condition, message) do { if (!(condition)) { fprintf(stderr, "FAIL: %s (%s)\n", message, error.localizedDescription.UTF8String ?: "no error"); return 1; } } while (0)
// The managed record the store is holding now. Each mutation reloads, so the object from before
// one is not the object to pass to the next - and the directory now holds an unmanaged folder
// too, which sorts before the managed one.
static TKAddonRecord *ManagedRecord(TKAddonStore *store) {
    for (TKAddonRecord *record in store.records) if (record.managed) return record;
    return nil;
}
int TestRealAddonImport(const char *fixtures, const char *temporary) {
    @autoreleasepool {
        NSString *root = [NSString stringWithUTF8String:temporary];
        NSString *directory = [root stringByAppendingPathComponent:@"Game/Interface/AddOns"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *error = nil;
        CHECK([fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error], "create sandbox");
        TKAddonStore *store = [[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"1.60.1"];
        NSURL *zip = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"valid.zip"]];
        CHECK([store importZIPAtURL:zip error:&error], "real Swift ZIP imports through Objective-C bridge");
        CHECK(store.records.count == 1 && store.records.firstObject.managed, "managed manifest survives reload");
        NSString *toc = [directory stringByAppendingPathComponent:@"Fixture/Fixture.toc"];
        NSData *before = [NSData dataWithContentsOfFile:toc];
        CHECK(![store importZIPAtURL:zip error:&error], "duplicate import refused");
        CHECK([before isEqual:[NSData dataWithContentsOfFile:toc]], "duplicate preserves original bytes");
        CHECK([store setDisabled:YES record:store.records.firstObject error:&error], "disable imported addon");
        CHECK(store.records.firstObject.disabled && ![fm fileExistsAtPath:toc], "disabled state");
        CHECK([store setDisabled:NO record:store.records.firstObject error:&error], "restore imported addon");
        CHECK([before isEqual:[NSData dataWithContentsOfFile:toc]], "restore preserves bytes");
        CHECK([store removeRecord:store.records.firstObject error:&error], "remove owned addon");
        CHECK(store.records.count == 0 && ![fm fileExistsAtPath:toc], "removed state");
        // A removal that cannot write its record must not move anything. The state that loses
        // a package is folders moved aside while the record still claims them, so the record
        // is written first; making the add-on directory unwritable is what proves the order,
        // and the package has to be there and still be listed afterwards.
        CHECK([store importZIPAtURL:zip error:&error], "re-import for the removal checks");
        NSDictionary *permissions = [fm attributesOfItemAtPath:directory error:&error];
        CHECK([fm setAttributes:@{ NSFilePosixPermissions: @(0500) } ofItemAtPath:directory error:&error], "make the add-on directory unwritable");
        CHECK(![store removeRecord:store.records.firstObject error:&error], "removal refused when its record cannot be written");
        CHECK([fm fileExistsAtPath:toc], "and the package's folders are still there");
        CHECK([fm setAttributes:@{ NSFilePosixPermissions: permissions[NSFilePosixPermissions] } ofItemAtPath:directory error:&error], "put the directory back");
        CHECK(store.records.count == 1 && store.records.firstObject.managed, "and it is still listed as managed");
        CHECK([store removeRecord:store.records.firstObject error:&error], "removal works once it can write again");
        CHECK(store.records.count == 0 && ![fm fileExistsAtPath:toc], "and then removes it");
        // One previous copy per package, not one per removal: nothing reads that directory,
        // so a copy per removal was storage that grew for ever and could never be used.
        CHECK([store importZIPAtURL:zip error:&error], "re-import for the pruning check");
        CHECK([store removeRecord:store.records.firstObject error:&error], "remove a second time");
        NSString *previousRoot = [[store valueForKey:@"support"] stringByAppendingPathComponent:@"previous"];
        NSUInteger copies = 0;
        for (NSString *name in [fm contentsOfDirectoryAtPath:previousRoot error:&error]) if ([name hasPrefix:@"Fixture-"]) copies += 1;
        CHECK(copies == 1, "one previous copy is kept, not one per removal");
        NSURL *bad = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"corrupt.zip"]];
        NSString *support = [store valueForKey:@"support"];
        NSArray *jobsBefore = [fm contentsOfDirectoryAtPath:support error:&error];
        CHECK(![store importZIPAtURL:bad error:&error], "corrupt ZIP rejected by real store");
        NSArray *jobsAfter = [fm contentsOfDirectoryAtPath:support error:&error];
        CHECK([[NSSet setWithArray:jobsBefore] isEqual:[NSSet setWithArray:jobsAfter]], "failed extraction leaves no staging job");
        // --- provider identity is recorded, never inferred
        NSDictionary *identity = @{ @"kind": @"curseforge", @"projectID": @61284,
                                    @"fileID": @100, @"fileName": @"Fixture-1.zip",
                                    @"version": @"1", @"compatibility": @"verified",
                                    @"logo": @"https://media.forgecdn.net/avatars/fixture.png" };
        CHECK([store importZIPAtURL:zip provider:identity error:&error], "import records a provider identity");
        TKAddonRecord *owned = ManagedRecord(store);
        CHECK(owned.providerUpdatable, "a package with a CurseForge project and file is provider-updatable");
        CHECK([owned.provider[@"projectID"] isEqual:@61284], "the identity is the API's, not the folder's");
        CHECK([owned.provider[@"logo"] isEqual:identity[@"logo"]], "the project thumbnail survives the manifest write");
        CHECK(owned.uuid.length > 0, "the package has a stable identity of its own");
        CHECK([owned.compatibility isEqual:@"verified"], "a TOC declaring Forever's interface is verified");
        // An add-on the user already had is displayed and left alone, and it is never treated
        // as a CurseForge package just because its folder has a familiar name.
        NSString *unmanaged = [directory stringByAppendingPathComponent:@"Details"];
        CHECK([fm createDirectoryAtPath:unmanaged withIntermediateDirectories:YES attributes:nil error:&error], "create an unmanaged folder");
        CHECK([@"## Title: Details\n## Version: 1\n## Interface: 11509\n" writeToFile:[unmanaged stringByAppendingPathComponent:@"Details.toc"]
              atomically:YES encoding:NSUTF8StringEncoding error:&error], "with its own TOC");
        [store reload];
        TKAddonRecord *foreign = nil;
        for (TKAddonRecord *record in store.records) if ([record.identifier isEqual:@"Details"]) foreign = record;
        CHECK(foreign != nil && !foreign.managed, "an existing folder is not managed");
        CHECK(!foreign.providerUpdatable, "and never becomes provider-updatable from its name");
        CHECK([foreign.compatibility isEqual:@"unverified"], "an older interface is unverified, not refused");

        // A single add-on folder can include manifests for multiple game clients. The Forever
        // manifest must supply the displayed metadata rather than whichever name sorts first.
        NSString *multi = [directory stringByAppendingPathComponent:@"MultiClient"];
        CHECK([fm createDirectoryAtPath:multi withIntermediateDirectories:YES attributes:nil error:&error], "create a multi-client add-on");
        CHECK([@"## Title: Retail name\n## Version: retail\n## Interface: 11509\n" writeToFile:[multi stringByAppendingPathComponent:@"MultiClient.toc"] atomically:YES encoding:NSUTF8StringEncoding error:&error], "write the retail manifest");
        CHECK([@"## Title: Forever name\n## Version: forever\n## Interface: 16001\n" writeToFile:[multi stringByAppendingPathComponent:@"MultiClient_Forever.toc"] atomically:YES encoding:NSUTF8StringEncoding error:&error], "write the Forever manifest");
        [store reload];
        TKAddonRecord *multiRecord = nil;
        for (TKAddonRecord *record in store.records) if ([record.identifier isEqual:@"MultiClient"]) multiRecord = record;
        CHECK([multiRecord.name isEqual:@"Forever name"] && [multiRecord.version isEqual:@"forever"], "the active Forever manifest supplies add-on metadata");
        CHECK([multiRecord.compatibility isEqual:@"verified"], "all multi-client manifests retain compatibility metadata");

        // --- a pinned package is not updated, and unpinning restores the ability
        CHECK([store setPinned:YES record:owned error:&error], "pin the package");
        // Each mutation reloads, so the object to pass on is the one the store is holding now.
        TKAddonRecord *pinned = ManagedRecord(store);
        CHECK(pinned.pinned, "the store reports it pinned");
        CHECK(![store updateRecord:pinned archiveURL:zip provider:pinned.provider error:&error],
              "a pinned package is refused, because pinned means leave it alone");
        CHECK([store setPinned:NO record:ManagedRecord(store) error:&error], "unpin it");

        // --- the transactional update itself
        NSInteger beforeUpdate = store.manifestRevision;
        NSDictionary *next = @{ @"kind": @"curseforge", @"projectID": @61284, @"fileID": @101,
                                @"fileName": @"Fixture-2.zip", @"version": @"2", @"compatibility": @"verified" };
        CHECK([store updateRecord:ManagedRecord(store) archiveURL:zip provider:next error:&error],
              "a managed package updates from an archive");
        CHECK(store.manifestRevision > beforeUpdate, "and the manifest revision moves");
        CHECK([ManagedRecord(store).provider[@"fileID"] isEqual:@101], "the record now names the new file");
        CHECK([fm fileExistsAtPath:toc], "the package's folders are where they were");

        // --- a failed update changes nothing at all
        NSInteger beforeFailure = store.manifestRevision;
        NSData *bytesBefore = [NSData dataWithContentsOfFile:toc];
        NSURL *corrupt = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:fixtures] stringByAppendingPathComponent:@"corrupt.zip"]];
        CHECK(![store updateRecord:ManagedRecord(store) archiveURL:corrupt provider:next error:&error],
              "a corrupt archive is refused before anything is mutated");
        CHECK(store.manifestRevision == beforeFailure, "the manifest revision does not move");
        CHECK([bytesBefore isEqual:[NSData dataWithContentsOfFile:toc]], "and the installed bytes are untouched");
        CHECK([ManagedRecord(store).provider[@"fileID"] isEqual:@101], "and the record still names the installed file");

        // --- disabled state survives an update, and the package updates where it actually is
        CHECK([store setDisabled:YES record:ManagedRecord(store) error:&error], "disable the package");
        CHECK(![fm fileExistsAtPath:toc], "a disabled package is stored privately");
        CHECK([store updateRecord:ManagedRecord(store) archiveURL:zip provider:next error:&error],
              "a disabled package updates in place");
        CHECK(ManagedRecord(store).disabled, "and stays disabled");
        CHECK([store setDisabled:NO record:ManagedRecord(store) error:&error], "restore it");

        // --- users may remove any listed package; the operation stays inside its exact folder
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove the managed package");
        CHECK([fm fileExistsAtPath:[unmanaged stringByAppendingPathComponent:@"Details.toc"]],
              "the existing folder remains until the user removes it");
        CHECK([store removeRecord:foreign error:&error], "remove an existing package at the user's request");
        CHECK(![fm fileExistsAtPath:[unmanaged stringByAppendingPathComponent:@"Details.toc"]],
              "the requested existing folder is removed");
        TKAddonRecord *unsafe = [TKAddonRecord new];
        unsafe.folders = @[@".."];
        unsafe.managed = NO;
        CHECK(![store removeRecord:unsafe error:&error], "refuse an existing-package removal outside AddOns");

        // --- format 1 and format 2 -> format 3 migration, and recovery from an interrupted one
        NSString *legacyRoot = [root stringByAppendingPathComponent:@"Legacy/Interface/AddOns"];
        CHECK([fm createDirectoryAtPath:[legacyRoot stringByAppendingPathComponent:@"LegacyAddon"]
                withIntermediateDirectories:YES attributes:nil error:&error], "create a legacy installation");
        CHECK([@"## Title: Legacy Addon\n## Version: 1\n## Interface: 16001\n"
                writeToFile:[[legacyRoot stringByAppendingPathComponent:@"LegacyAddon"] stringByAppendingPathComponent:@"LegacyAddon.toc"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "with a package");
        NSString *formatOne = @"{\"format\":1,\"product\":\"wowf\",\"gameVersion\":\"1.60.1\",\"packages\":["
            "{\"identifier\":\"LegacyAddon\",\"name\":\"Legacy Addon\",\"version\":\"1\",\"source\":\"zip\","
            "\"archiveSHA256\":\"abc\",\"folders\":[\"LegacyAddon\"],\"pinned\":true,\"disabled\":false}]}";
        CHECK([formatOne writeToFile:[legacyRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "write a format-1 manifest");
        TKAddonStore *legacy = [[TKAddonStore alloc] initWithAddOnsDirectory:legacyRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(legacy.manifestFormat == 3, "a format-1 manifest is migrated on first read");
        CHECK(legacy.manifestRevision >= 1, "and the migration commits a revision");
        CHECK(legacy.records.count == 1 && legacy.records.firstObject.managed, "the package survives the migration");
        CHECK(legacy.records.firstObject.uuid.length > 0, "and gains a stable identity");
        CHECK(legacy.records.firstObject.pinned, "and keeps its pinned state");
        // Format 3 states how the package arrived rather than inventing a route: a record with
        // no CurseForge identity was imported as files.
        CHECK([legacy.records.firstObject.provenance isEqualToString:TKAddonProvenanceFiles],
              "and records the route it actually arrived by");
        CHECK([legacy.records.firstObject.digest isEqualToString:@"abc"],
              "and the digest the old format stored under its old name");
        CHECK(legacy.records.firstObject.iconCacheKey.length > 0, "and an icon cache key");
        CHECK(legacy.records.firstObject.installedAt == nil,
              "and does not invent an install time the old format never recorded");
        CHECK(legacy.groups.count == 0, "and no groups the old format never had");

        // The interrupted case: the journal is on disk, the format-2 write never finished.
        NSString *legacySupport = [legacy valueForKey:@"support"];
        CHECK([fm createDirectoryAtPath:legacySupport withIntermediateDirectories:YES attributes:nil error:&error], "create the legacy support folder");
        CHECK([formatOne writeToFile:[legacySupport stringByAppendingPathComponent:@"manifest-v1-backup.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "keep the format-1 backup");
        CHECK([@"{\"from\":1,\"to\":3,\"revision\":2}" writeToFile:[legacySupport stringByAppendingPathComponent:@"manifest-journal.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "and the journal");
        CHECK([@"{\"format\":3,\"revision\":2,\"packages\":[{\"identifier\":\"LegacyAddon\"}]}"
                writeToFile:[legacyRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "and a half-written format-3 manifest");
        TKAddonStore *recovered = [[TKAddonStore alloc] initWithAddOnsDirectory:legacyRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(recovered.recoveredInterruptedWrite, "an interrupted migration is reported as recovered");
        CHECK(recovered.records.count == 1 && recovered.records.firstObject.managed,
              "and the package that was there before is back");
        CHECK(recovered.manifestFormat == 3, "and the retried migration completes");

        // --- a manifest this build does not write is shown and never downgraded
        // A newer build's file is the one thing a read must not "repair": the records stay
        // visible so the page can describe them, every mutation is refused, and the bytes on
        // disk are exactly what the newer build left.
        NSString *futureRoot = [root stringByAppendingPathComponent:@"Future/Interface/AddOns"];
        CHECK([fm createDirectoryAtPath:[futureRoot stringByAppendingPathComponent:@"FutureAddon"]
                withIntermediateDirectories:YES attributes:nil error:&error], "create a newer-format installation");
        CHECK([@"## Title: Future Addon\n## Version: 9\n## Interface: 16001\n"
                writeToFile:[[futureRoot stringByAppendingPathComponent:@"FutureAddon"]
                    stringByAppendingPathComponent:@"FutureAddon.toc"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "with a package");
        NSString *futureManifest = @"{\"format\":4,\"product\":\"wowf\",\"gameVersion\":\"1.60.1\","
            "\"revision\":7,\"packages\":[{\"identifier\":\"FutureAddon\",\"uuid\":\"future-1\","
            "\"name\":\"Future Addon\",\"version\":\"9\",\"folders\":[\"FutureAddon\"],"
            "\"pinned\":false,\"disabled\":false}],\"groups\":[],\"links\":[]}";
        NSString *futureManifestPath = [futureRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"];
        CHECK([futureManifest writeToFile:futureManifestPath atomically:YES encoding:NSUTF8StringEncoding error:&error],
              "write a format-4 manifest");
        NSData *futureBytes = [NSData dataWithContentsOfFile:futureManifestPath];
        TKAddonStore *future = [[TKAddonStore alloc] initWithAddOnsDirectory:futureRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(future.manifestReadOnly, "a manifest from a newer build is read-only here");
        CHECK(future.records.count == 1 && future.records.firstObject.managed, "and its package is still listed");
        CHECK(![future setPinned:YES record:ManagedRecord(future) error:&error],
              "and every mutation is refused rather than downgrading the file");
        CHECK([futureBytes isEqual:[NSData dataWithContentsOfFile:futureManifestPath]],
              "leaving the newer build's bytes untouched");

        // Clean only this fixture's private support directories, never another import.
        CHECK([fm removeItemAtPath:support error:&error], "remove fixture staging and backups");
        CHECK([fm removeItemAtPath:legacySupport error:&error], "remove the legacy support folder");
        // A read-only manifest never creates a support folder, so there is usually nothing here.
        NSString *futureSupport = [future valueForKey:@"support"];
        CHECK(![fm fileExistsAtPath:futureSupport] || [fm removeItemAtPath:futureSupport error:&error],
              "remove the newer-format support folder if one was made");
        puts("ADDON IMPORT PASS: real ZIP -> Objective-C bridge -> store -> provider identity, migration, transactional update, rollback, unmanaged folders, a newer manifest read-only");
        return 0;
    }
}

// The suite's first act: nothing this process does is recorded unless a test turns it on. The
// switch is stored, so a run that failed before its cleanup would otherwise leave the next run
// writing into the machine's own log.
void TestAddonHubLogOff(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:TKAddonHubDiagnosticsEnabledKey];
    TKAddonHubSetDiagnosticsEnabled(NO);
    TKAddonHubLogFlush();
}

// The manager's action-event contract, asserted where it can be: no file, no network, no app.
//
// Off by default is the whole point of the switch - a shipped run must record nothing - so this
// asserts the disabled path first, and only then turns it on and reads the pair back through a
// sink. The prohibited data is passed in deliberately: a URL with a token, a home directory and
// a free-form value. If any of it reaches a line, this fails.
int TestAddonHubContract(void) {
    @autoreleasepool {
        NSError *error = nil;
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        TKAddonHubSetSink(^(NSString *line) { @synchronized (lines) { [lines addObject:line]; } });
        // --- off by default: nothing is built, nothing is written
        [NSUserDefaults.standardUserDefaults removeObjectForKey:TKAddonHubDiagnosticsEnabledKey];
        TKAddonHubSetDiagnosticsEnabled(NO);
        TKAddonHubLogFlush();
        [lines removeAllObjects];
        CHECK(!TKAddonHubDiagnosticsEnabled(), "logging is off by default");
        CHECK(TKAddonHubActionBegin(TKAddonHubActionUpdate, nil) == nil, "the disabled path allocates no token");
        TKAddonHubLog(TKAddonHubEventArchive, @{ TKAddonHubKeyIdentifier: @"Fixture" });
        TKAddonHubLogFlush();
        CHECK(lines.count == 0, "and writes nothing at all");

        // --- enabled: one pair, in order, with the contract's own fields
        TKAddonHubSetDiagnosticsEnabled(YES);
        TKAddonHubLogFlush();
        [lines removeAllObjects];
        CHECK(TKAddonHubDiagnosticsEnabled(), "the switch is read back");
        CHECK([NSUserDefaults.standardUserDefaults boolForKey:TKAddonHubDiagnosticsEnabledKey], "and it is stored");
        TKAddonHubActionToken *token = TKAddonHubActionBegin(TKAddonHubActionUpdate, @{
            TKAddonHubKeyIdentifier: @"Fixture",
            TKAddonHubKeyProvider: TKAddonProvenanceAPI,
            // Deliberately prohibited values, in keys this log does not have.
            @"url": @"https://media.forgecdn.net/files/1/2/x.zip?token=secret",
            @"path": @"/Users/someone/Library/x",
            TKAddonHubKeyReason: @"a:b",
        });
        CHECK(token != nil, "the enabled path returns a token");
        TKAddonHubActionFinish(token, TKAddonHubOutcomeFailed, TKAddonHubFailureProvider,
                               @{ TKAddonHubKeyCount: @1 });
        TKAddonHubLogFlush();
        CHECK(lines.count == 2, "start and end are one pair");
        if (lines.count == 2) {
            CHECK([lines[0] containsString:@"event=action"], "the start line is an action event");
            CHECK([lines[0] containsString:@"action=update"], "the start line names the action");
            CHECK([lines[0] containsString:@"outcome=started"], "and that it started");
            CHECK([lines[0] containsString:@"provider=api identifier=Fixture"], "and its safe fields");
            CHECK([lines[1] containsString:@"outcome=failed"], "the end line names the outcome");
            CHECK([lines[1] containsString:@"failure=provider"], "and the failure class");
            CHECK([lines[1] containsString:@"action=update"], "the end line still names the action");
            CHECK([lines[1] containsString:@"duration="], "and how long it took");
            CHECK([lines[1] containsString:@"count=1"], "and the fields it was given at the end");
            CHECK([lines[0] containsString:@"reason=-"], "a value with an unexpected shape is not printed");
        }
        for (NSString *line in lines) {
            for (NSString *prohibited in @[@"http", @"secret", @"/Users", @"token", @"Library"]) {
                CHECK([line rangeOfString:prohibited].location == NSNotFound,
                      "no URL, path, token or free text in any line");
            }
        }

        // --- the failure class reads the domain and the status, never the message
        CHECK(TKAddonHubFailureClassForError(nil) == TKAddonHubFailureNone, "no error means no class");
        CHECK(TKAddonHubFailureClassForError([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]) == TKAddonHubFailureNetwork, "a timeout is a network failure");
        CHECK(TKAddonHubFailureClassForError([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]) == TKAddonHubFailureCancelled, "a cancellation is its own class");
        CHECK(TKAddonHubFailureClassForError([NSError errorWithDomain:@"WolkaraForever.CurseForge" code:1 userInfo:nil]) == TKAddonHubFailureProvider, "a provider refusal is the provider");
        CHECK(TKAddonHubFailureClassForError([NSError errorWithDomain:@"WolkaraForever.AddOns" code:1 userInfo:nil]) == TKAddonHubFailureStore, "a store refusal is the store");

        // Leave the process as it was found, so a later suite in the same run writes nothing.
        TKAddonHubSetDiagnosticsEnabled(NO);
        TKAddonHubLogFlush();
        TKAddonHubSetSink(nil);
        puts("ADDON HUB CONTRACT PASS: off by default, no token while off, start/end pair with outcome, failure class and duration, no URL, path, key or free text");
        return 0;
    }
}

// The bundled WolkaraRoue package, installed the way the recommendation page installs it:
// explicitly, through the store, from the archive the app ships. The good and the tampered
// archives come from `package_addon_zip.py --fixtures`, so this is the same pair the
// verifier is tested against.
int TestBundledPackageInstall(const char *packageFixtures, const char *temporary) {
    @autoreleasepool {
        NSString *fixtures = [NSString stringWithUTF8String:packageFixtures];
        NSString *good = [fixtures stringByAppendingPathComponent:@"good"];
        NSString *root = [NSString stringWithUTF8String:temporary];
        NSString *directory = [root stringByAppendingPathComponent:@"Bundled/Interface/AddOns"];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *error = nil;
        CHECK([fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error], "create the bundled sandbox");
        NSString *archiveName = nil;
        for (NSString *name in [fm contentsOfDirectoryAtPath:good error:&error])
            if ([name hasPrefix:@"WolkaraRoue-"] && [name hasSuffix:@".zip"]) { archiveName = name; break; }
        CHECK(archiveName != nil, "the package fixture names its archive");
        NSURL *archive = [NSURL fileURLWithPath:[good stringByAppendingPathComponent:archiveName]];
        TKAddonStore *store = [[TKAddonStore alloc] initWithAddOnsDirectory:directory product:@"wowf" gameVersion:@"1.60.1"];
        CHECK([store importZIPAtURL:archive error:&error], "the bundled package installs through the store");
        CHECK(store.records.count == 1, "and is listed exactly once");
        CHECK([store.records.firstObject.folders containsObject:@"WolkaraRoue"], "as its own reviewed folder");
        NSString *toc = [directory stringByAppendingPathComponent:@"WolkaraRoue/WolkaraRoue.toc"];
        CHECK([fm fileExistsAtPath:toc], "with the reviewed TOC in place");
        // A second Install is an Update of the one record, not a second copy of the folder.
        CHECK([store updateRecord:store.records.firstObject archiveURL:archive provider:nil error:&error],
              "reinstalling updates the one record");
        CHECK(store.records.count == 1, "and does not add a second");
        // A tampered archive is refused and leaves the installed tree exactly as it was.
        NSData *before = [NSData dataWithContentsOfFile:toc];
        NSURL *tampered = [NSURL fileURLWithPath:[fixtures stringByAppendingPathComponent:
            [@"tampered" stringByAppendingPathComponent:archiveName]]];
        CHECK(![store importZIPAtURL:tampered error:&error], "a tampered bundled archive is refused");
        CHECK([before isEqual:[NSData dataWithContentsOfFile:toc]], "and nothing installed was replaced");
        puts("BUNDLED PACKAGE PASS: installs, updates in place, refuses a tampered archive");
        return 0;
    }
}
