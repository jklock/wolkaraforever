#import "AddonStore.h"
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
                                    @"version": @"1", @"compatibility": @"verified" };
        CHECK([store importZIPAtURL:zip provider:identity error:&error], "import records a provider identity");
        TKAddonRecord *owned = ManagedRecord(store);
        CHECK(owned.providerUpdatable, "a package with a CurseForge project and file is provider-updatable");
        CHECK([owned.provider[@"projectID"] isEqual:@61284], "the identity is the API's, not the folder's");
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

        // --- removing a managed package never removes a folder it does not own
        CHECK([store removeRecord:ManagedRecord(store) error:&error], "remove the managed package");
        CHECK([fm fileExistsAtPath:[unmanaged stringByAppendingPathComponent:@"Details.toc"]],
              "the unmanaged folder is still there");

        // --- format-1 -> format-2 migration, and recovery from an interrupted one
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
        CHECK(legacy.manifestFormat == 2, "a format-1 manifest is migrated on first read");
        CHECK(legacy.manifestRevision >= 1, "and the migration commits a revision");
        CHECK(legacy.records.count == 1 && legacy.records.firstObject.managed, "the package survives the migration");
        CHECK(legacy.records.firstObject.uuid.length > 0, "and gains a stable identity");
        CHECK(legacy.records.firstObject.pinned, "and keeps its pinned state");

        // The interrupted case: the journal is on disk, the format-2 write never finished.
        NSString *legacySupport = [legacy valueForKey:@"support"];
        CHECK([fm createDirectoryAtPath:legacySupport withIntermediateDirectories:YES attributes:nil error:&error], "create the legacy support folder");
        CHECK([formatOne writeToFile:[legacySupport stringByAppendingPathComponent:@"manifest-v1-backup.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "keep the format-1 backup");
        CHECK([@"{\"from\":1,\"to\":2,\"revision\":2}" writeToFile:[legacySupport stringByAppendingPathComponent:@"manifest-journal.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "and the journal");
        CHECK([@"{\"format\":2,\"revision\":2,\"packages\":[{\"identifier\":\"LegacyAddon\"}]}"
                writeToFile:[legacyRoot stringByAppendingPathComponent:@".wolkaraforever-addons.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error], "and a half-written format-2 manifest");
        TKAddonStore *recovered = [[TKAddonStore alloc] initWithAddOnsDirectory:legacyRoot product:@"wowf" gameVersion:@"1.60.1"];
        CHECK(recovered.recoveredInterruptedWrite, "an interrupted migration is reported as recovered");
        CHECK(recovered.records.count == 1 && recovered.records.firstObject.managed,
              "and the package that was there before is back");
        CHECK(recovered.manifestFormat == 2, "and the retried migration completes");

        // Clean only this fixture's private support directories, never another import.
        CHECK([fm removeItemAtPath:support error:&error], "remove fixture staging and backups");
        CHECK([fm removeItemAtPath:legacySupport error:&error], "remove the legacy support folder");
        puts("ADDON IMPORT PASS: real ZIP -> Objective-C bridge -> store -> provider identity, migration, transactional update, rollback, unmanaged folders");
        return 0;
    }
}
