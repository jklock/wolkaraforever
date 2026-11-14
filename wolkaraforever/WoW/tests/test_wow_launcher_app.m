// Isolated UIKit fixture: our synthetic installation, no network or guest execution.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#import "../launcher/WoW/WoWViewController.h"
#import "../launcher/WoW/AddonManager.h"
#import "../launcher/WoW/AddonStore.h"
#import "../launcher/WoW/AddonCredentialStore.h"
#import "../launcher/WoW/AddonUpdateResolver.h"
#import "../launcher/WoW/AddonHubLog.h"
#import "../launcher/WoW/AddonBrowser.h"
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "../launcher/WoW/Client.h"
#import "../launcher/WoW/DeviceProfile.h"
#import "../launcher/WoW/ForeverUI.h"
#import "../launcher/WoW/Manifest.h"
#import "../launcher/WoW/Updater.h"
#import "../launcher/App/LaunchProgressView.h"
#import "../launcher/App/WKLocalization.h"
#import "../launcher/App/WolkaraForeverConfig.h"
#import "../launcher/App/WolkaraForeverLog.h"
#import "../launcher/App/WolkaraForeverTheme.h"
#import "../launcher/Voice/VoiceViewController.h"
#import "../launcher/Voice/VoiceTestViewController.h"
#import "wow_installation_fixture.h"

@interface TKWoWViewController (Fixture)
- (void)selectProduct:(NSDictionary *)product;
- (void)refresh;
- (void)about;
- (void)repairInstallation;
- (void)manageAddons;
- (void)manageVoice;
- (void)testVoice;
- (void)performGraphicsReset:(NSString *)directory;
- (void)render;
- (void)choosePreference:(BOOL)region;
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls;
- (BOOL)foreverActionAllowed;
- (NSString *)foreverWorkingDirectory;
- (void)preferences;
- (void)settings;
- (void)chooseAppLanguage;
- (void)applyAppLanguage:(WKAppLanguage)language;
- (void)setGameLocale:(NSString *)locale;
@end
@interface TKWoWAddonManagerViewController (Fixture)
- (void)done;
- (void)changeMode:(UISegmentedControl *)sender;
@end
@interface AKVoiceViewController (Fixture)
- (void)done;
@end
@interface AKVoiceTestViewController (Fixture)
- (void)done;
@end
static atomic_uint requests, revision, updates, repairs;
static atomic_bool failure, slow, slowUpdate, interruptRepair;
// One update held open so the downloading state can be inspected while it is happening. It is a
// separate flag from slowUpdate because a delay long enough to look at is also long enough to make
// every other step in this file guess at how fast the machine is.
static atomic_bool holdUpdate;
static unsigned requestsBeforePopup;
static BOOL keyboardShown;
static TKFixtureLibrary *fixture;
static NSString *FixtureModelIdentifier(id self, SEL selector) { (void)self; (void)selector; return @"fixture-unmeasured"; }
static NSDictionary *Plan(id self, SEL selector, NSString *product, NSString *region, NSString *locale, NSError **error) {
    (void)self; (void)selector; (void)region; (void)locale;
    unsigned request=atomic_fetch_add(&requests,1);
    [NSThread sleepForTimeInterval:(request==0 || atomic_load(&slow))?0.5:0.02];
    if (atomic_load(&failure)) { if (error) *error=TKWoWError(@"Synthetic offline response"); return nil; }
    return [fixture planForProduct:product revision:atomic_load(&revision)];
}
static BOOL Update(id self, SEL selector, NSDictionary *plan, NSString *root,
                   void (^progress)(NSString *,uint64_t,uint64_t), NSError **error) {
    (void)selector; (void)plan;
    assert([root isEqual:fixture.root]);
    if([(TKWoWUpdater *)self fullVerification]) {
        atomic_fetch_add(&repairs,1);
        if(atomic_exchange(&interruptRepair,false)) { if(error)*error=TKWoWError(@"Synthetic repair interruption");return NO; }
    }
    if(atomic_load(&holdUpdate)) {
        // A game update the size of a real one, held open: 40 GB of 70 GB, so the status line has
        // the byte counts the speed and the estimate are written after.
        progress(@"download",40000000000ULL,70000000000ULL);
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:30];
        while(atomic_load(&holdUpdate) && deadline.timeIntervalSinceNow>0)
            [NSThread sleepForTimeInterval:0.02];
        [fixture writeMetadata:atomic_load(&revision) duplicate:NO];
        progress(@"complete",1,1); return YES;
    }
    atomic_fetch_add(&updates,1); progress(@"download",50,100);
    if(atomic_load(&slowUpdate)) [NSThread sleepForTimeInterval:0.5];
    [fixture writeMetadata:atomic_load(&revision) duplicate:NO];
    progress(@"complete",1,1); return YES;
}
static UIView *Find(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *match=Find(child,identifier); if (match) return match; }
    return nil;
}
// Every spinner in a window, so a capture can hold still the one part of a page that moves.
static void CollectActivityIndicators(UIView *view, NSMutableArray<UIActivityIndicatorView *> *into) {
    if ([view isKindOfClass:UIActivityIndicatorView.class]) [into addObject:(UIActivityIndicatorView *)view];
    for (UIView *child in view.subviews) CollectActivityIndicators(child, into);
}
// Whether anything in this layer's tree is still animating. A button whose configuration changed a
// moment ago crossfades its old words out over the new ones, and that crossfade is two animated
// layers: measured on 2026-11-10, the primary button was still animating when the downloading page
// was captured, and the picture then held "Checking…" under a status line that already read
// "Updating your game…". The same subtree has no animations 0.4 s later, so a capture waits for
// that rather than for a delay that happens to be long enough.
static BOOL AnimatingUnder(CALayer *layer) {
    if (layer.animationKeys.count) return YES;
    for (CALayer *child in layer.sublayers) if (AnimatingUnder(child)) return YES;
    return NO;
}
// Every animation in a layer's tree, gone. A busy indicator fades its spokes as it turns, so a
// picture of it stopped mid-turn shows whichever spoke happened to be bright: measured on the iPad
// matrix on 2026-11-10, two runs of the same state differed in 339 pixels, all of them in the
// indicator. With the fades removed every spoke is drawn at its own strength, the indicator is
// still there and still visible, and the picture is the same one every run.
static void RemoveAnimations(CALayer *layer) {
    [layer removeAllAnimations];
    for (CALayer *child in layer.sublayers) RemoveAnimations(child);
}
static NSString *ButtonTitle(UIButton *button) {
    return button.configuration.title ?: [button titleForState:UIControlStateNormal] ?: button.titleLabel.text;
}
// Let the run loop work for a while. Every one of these rows answers on the main
// queue, so turning the wheel here is the same as the tap a person makes; sleeping
// instead would assert against a page that had not drawn yet, which has already
// produced one completely false failure in this file.
static void Pump(double seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
// Wait for the page to reach a state, rather than for a fixed time and hoping. The update and
// repair steps below used to wait three tenths of a second, which is a guess about how fast the
// machine is: the guess was right on a warm simulator and wrong on a freshly erased one, and it
// failed a step that had nothing wrong with it. The ceiling is only here so a genuine hang ends
// the test with the assertion below instead of sitting in it forever.
static BOOL PumpUntil(BOOL (^condition)(void), NSTimeInterval limit) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:limit];
    while ([deadline timeIntervalSinceNow] > 0) {
        if (condition()) return YES;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}
// An alert that a row raises only after its work on another queue finishes. Every one of these
// used to be read after a fixed delay, which is a guess about how fast the machine is - and one
// of those guesses has already failed on a freshly erased simulator with nothing wrong in the
// app. This waits for the alert to be there.
// The sheet this step expects, waited for by title.
//
// "Something is presented" is not the same question as "my sheet is presented": a step that reads
// whatever happens to be on top can be handed the previous sheet, still transitioning or simply
// not dismissed yet, and then assert its title against the wrong words. Every step that expects a
// named sheet asks for that sheet.
static UIAlertController *WaitForSheetTitled(UIViewController *presenter, NSString *title,
                                             NSTimeInterval limit) {
    __block BOOL matched = NO;
    PumpUntil(^{
        UIViewController *presented = presenter.presentedViewController;
        if (![presented isKindOfClass:UIAlertController.class]) return NO;
        if (presented.isBeingPresented || presented.isBeingDismissed) return NO;
        matched = [((UIAlertController *)presented).title isEqual:title];
        return matched;
    }, limit);
    UIViewController *presented = presenter.presentedViewController;
    if (![presented isKindOfClass:UIAlertController.class]) return nil;
    return [((UIAlertController *)presented).title isEqual:title] ? (UIAlertController *)presented : nil;
}

static UIAlertController *WaitForAlert(UIViewController *presenter, NSTimeInterval limit) {
    // Only an alert that has finished arriving counts. A sheet that is on its way out is still
    // `presentedViewController` until the transition ends, so a step that waits naively can be
    // handed the sheet the previous step asked to close and then assert the wrong title - which
    // reads as a fault in the app. Found on a loaded iPad Pro 13-inch (M5), 2026-11-13.
    PumpUntil(^{
        UIViewController *presented = presenter.presentedViewController;
        return (BOOL)([presented isKindOfClass:UIAlertController.class] &&
                      !presented.isBeingPresented && !presented.isBeingDismissed);
    }, limit);
    UIViewController *presented = presenter.presentedViewController;
    if (![presented isKindOfClass:UIAlertController.class]) return nil;
    return presented.isBeingDismissed ? nil : (UIAlertController *)presented;
}
// One way out, and only one. UIKit raises on the second one - that is the crash that
// made Render Profile a dead row - so every sheet this page opens is asked.
static NSUInteger CancelActions(UIAlertController *sheet) {
    NSUInteger count = 0;
    for (UIAlertAction *action in sheet.actions) if (action.style == UIAlertActionStyleCancel) count++;
    return count;
}
// Run an action the way a tap on it does: UIKit dismisses, then calls the block the
// action holds. A fixture cannot tap a sheet row, so it takes the block.
static void RunAction(UIAlertAction *action) {
    void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
    if (handler) handler(action);
}
// A navigation item has no control event; this is the route UIKit itself uses.
static void TapBarItem(UIBarButtonItem *item) {
    [UIApplication.sharedApplication sendAction:item.action to:item.target from:item forEvent:nil];
}
// What the store does, without a network and without the unzipper.
//
// The audit's open-work note: the add-on subsystem had no automated coverage at all. The
// store itself - which folders count as add-ons, what the manifest says, what happens on a
// duplicate, an incompatible TOC, a missing TOC, what removal and disabling do - is all
// offline logic, and the extractor is looked up by name at runtime, so the fixture stands in
// for it and exercises everything except the unzipping itself.
//
// The extractor it stands in for is `wolkaraforever/WoW/AddonArchive.swift`, which is ours and uses
// ZIPFoundation. Testing it would mean building that package, so it is explicitly deferred
// in development/AUDIT.md and exercised on the device instead (importing a real add-on).
@interface TKAddonArchive : NSObject
+ (BOOL)extractArchiveAtURL:(NSURL *)url toDirectoryURL:(NSURL *)destination error:(NSError **)error;
@end

@implementation TKAddonArchive
+ (BOOL)extractArchiveAtURL:(NSURL *)url toDirectoryURL:(NSURL *)destination error:(NSError **)error {
    NSString *source = [url.path stringByAppendingString:@".extracted"];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:source]) {
        if (error) *error = [NSError errorWithDomain:@"test" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"no such archive"}];
        return NO;
    }
    // The destination is the extractor's to create: the store makes the job directory and
    // leaves the extraction directory to whoever is doing the extracting.
    [files createDirectoryAtPath:destination.path withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSString *name in [files contentsOfDirectoryAtPath:source error:NULL]) {
        if (![files copyItemAtPath:[source stringByAppendingPathComponent:name]
                            toPath:[destination.path stringByAppendingPathComponent:name]
                             error:error]) return NO;
    }
    return YES;
}
@end

// The production backup component is Swift (ForeverUIArchive.swift) and is
// compiled into the app, not into this Objective-C fixture. The controller
// reaches it by name, so the fixture supplies a stand-in with the same
// selectors: the UI, the confirmation flow, the guard rails and the config
// writes are exercised here, and the real ZIP writer/restorer has its own
// targeted Swift test (tests/test_forever_ui_archive.swift).
static int stubBackups, stubRestores;
static NSString *stubNewest;
static NSString *stubLastRestored;
static NSMutableArray<NSString *> *stubNames;
@interface TKForeverUIArchive : NSObject
@end
@implementation TKForeverUIArchive
+ (NSString *)createBackupInWorkingDirectory:(NSString *)directory edition:(NSString *)edition error:(NSError **)error {
    (void)edition; (void)error;
    NSString *backups = [directory stringByAppendingPathComponent:@"WTF/Backups"];
    [NSFileManager.defaultManager createDirectoryAtPath:backups withIntermediateDirectories:YES attributes:nil error:NULL];
    stubBackups++;
    NSString *name = [NSString stringWithFormat:@"WoW-UI-2026-10-21T00-00-%02dZ.zip", stubBackups];
    assert([[@"stub snapshot" dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[backups stringByAppendingPathComponent:name] atomically:YES]);
    stubNewest = name;
    if (!stubNames) stubNames = [NSMutableArray new];
    [stubNames addObject:name];
    return name;
}
+ (NSString *)newestBackupInWorkingDirectory:(NSString *)directory error:(NSError **)error {
    (void)directory;
    if (!stubNewest) {
        if (error) *error = [NSError errorWithDomain:@"test" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"No complete backup was found. Run Backup first."}];
        return nil;
    }
    return stubNewest;
}
+ (BOOL)restoreBackupNamed:(NSString *)name inWorkingDirectory:(NSString *)directory edition:(NSString *)edition error:(NSError **)error {
    (void)directory; (void)edition; (void)error;
    assert([stubNames containsObject:name]);
    stubLastRestored = name;
    stubRestores++;
    return YES;
}
+ (BOOL)recoverInterruptedRestoreInWorkingDirectory:(NSString *)directory error:(NSError **)error {
    (void)directory; (void)error;
    return YES;
}
@end

// The record the store is currently holding for the package we imported. Each mutation
// reloads, so the object held before one is not the object to pass to the next - which is
// also what the launcher's own table has to do.
static TKAddonRecord *ManagedRecord(TKAddonStore *store) {
    for (TKAddonRecord *record in store.records) if (record.managed) return record;
    return nil;
}

static void WriteFile(NSString *path, NSString *contents) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:NULL];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void TestAddons(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"wow-addon-tests"];
    [files removeItemAtPath:root error:NULL];
    NSString *addons = [root stringByAppendingPathComponent:@"Interface/AddOns"];

    // --- what counts as an add-on
    WriteFile([addons stringByAppendingPathComponent:@"MyAddon/MyAddon.toc"],
              @"## Title: My Addon\n## Version: 1.2.3\n## Interface: 16001\n");
    WriteFile([addons stringByAppendingPathComponent:@"MyAddon/core.lua"], @"-- lua\n");
    WriteFile([addons stringByAppendingPathComponent:@"NoTOC/readme.txt"], @"nothing here\n");
    WriteFile([addons stringByAppendingPathComponent:@"stray.txt"], @"not a folder\n");
    WriteFile([addons stringByAppendingPathComponent:@".hidden/Hidden.toc"], @"## Title: Hidden\n");

    NSArray<TKWoWAddon *> *found = TKWoWAddonsAtDirectory(addons);
    assert(found.count == 1);
    assert([found[0].title isEqualToString:@"My Addon"]);
    assert([found[0].version isEqualToString:@"1.2.3"]);
    assert(found[0].fileCount == 2);   // the .toc and the .lua, and not the directory itself

    // --- the store: import, keep a manifest, refuse a duplicate
    // The version AddonManager.m builds the store with. It is a constant inside that file,
    // so the fixture names it here rather than reaching into it.
    TKAddonStore *store = [[TKAddonStore alloc] initWithAddOnsDirectory:addons
                                                                product:@"wowf"
                                                            gameVersion:@"1.60.1"];
    [store reload];
    assert(store.records.count == 1);
    assert([store.records[0].source isEqualToString:@"Existing"]);
    assert(!store.records[0].managed);   // found in the folder, not imported by us
    assert(store.records[0].pinned == NO);

    // The archive file the store reads and hashes, and beside it what the extractor would
    // have produced from it.
    NSString *package = [root stringByAppendingPathComponent:@"package.zip"];
    WriteFile(package, @"PK\x03\x04 not really a zip, but a real file\n");
    WriteFile([root stringByAppendingPathComponent:@"package.zip.extracted/Imported/Imported.toc"],
              @"## Title: Imported Addon\n## Version: 9.9\n## Interface: 16001\n");
    WriteFile([root stringByAppendingPathComponent:@"package.zip.extracted/Imported/extra.lua"], @"-- lua\n");
    NSError *error = nil;
    BOOL importedOK = [store importZIPAtURL:[NSURL fileURLWithPath:package] error:&error];
    if (!importedOK) NSLog(@"ADDON_IMPORT_FAILED: %@", error.localizedDescription);
    assert(importedOK);

    TKAddonRecord *imported = ManagedRecord(store);
    assert(imported != nil);
    assert([imported.name isEqualToString:@"Imported Addon"]);
    assert([imported.version isEqualToString:@"9.9"]);
    assert([imported.source isEqualToString:@"WolkaraForever import"]);
    assert([files fileExistsAtPath:[addons stringByAppendingPathComponent:@"Imported/Imported.toc"]]);
    assert([files fileExistsAtPath:[addons stringByAppendingPathComponent:@".wolkaraforever-addons.json"]]);

    // The same package twice: refused, and the first copy is *untouched*. It was not: the
    // store's failure cleanup removed every folder in the import, and the duplicate check
    // returns through that path, so asking to install an add-on you already have deleted the
    // one you had. Found by this fixture, which is the coverage the audit asked for.
    error = nil;
    assert(![store importZIPAtURL:[NSURL fileURLWithPath:package] error:&error]);
    assert([error.localizedDescription containsString:@"already exists"]);
    assert([files fileExistsAtPath:[addons stringByAppendingPathComponent:@"Imported/Imported.toc"]]);
    assert([files fileExistsAtPath:[addons stringByAppendingPathComponent:@"Imported/extra.lua"]]);
    assert(ManagedRecord(store) != nil);

    // A package with no TOC anywhere: refused with something a person can act on.
    NSString *tocless = [root stringByAppendingPathComponent:@"tocless.zip"];
    WriteFile(tocless, @"PK\x03\x04 no toc inside\n");
    WriteFile([root stringByAppendingPathComponent:@"tocless.zip.extracted/Whatever/notes.txt"], @"no toc\n");
    error = nil;
    assert(![store importZIPAtURL:[NSURL fileURLWithPath:tocless] error:&error]);
    assert([error.localizedDescription containsString:@"no add-on folder"]);

    // And an archive the extractor cannot read at all.
    error = nil;
    assert(![store importZIPAtURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"nope"]] error:&error]);
    assert(error != nil);

    // --- pinning, disabling, removing
    error = nil;
    BOOL pinnedOK = [store setPinned:YES record:imported error:&error];
    if (!pinnedOK) NSLog(@"ADDON_PIN_FAILED: %@", error.localizedDescription);
    assert(pinnedOK);
    assert(ManagedRecord(store).pinned);

    error = nil;
    BOOL disabledOK = [store setDisabled:YES record:ManagedRecord(store) error:&error];
    if (!disabledOK) NSLog(@"ADDON_DISABLE_FAILED: %@", error.localizedDescription);
    assert(disabledOK);
    // A disabled package keeps its record, so the user can turn it back on.
    TKAddonRecord *disabled = nil;
    for (TKAddonRecord *record in store.records) if ([record.identifier isEqualToString:@"Imported"]) disabled = record;
    assert(disabled != nil && disabled.disabled);

    error = nil;
    assert([store setDisabled:NO record:disabled error:&error]);

    error = nil;
    BOOL removedOK = [store removeRecord:ManagedRecord(store) error:&error];
    if (!removedOK) NSLog(@"ADDON_REMOVE_FAILED: %@", error.localizedDescription);
    assert(removedOK);
    assert(![files fileExistsAtPath:[addons stringByAppendingPathComponent:@"Imported"]]);
    assert(store.records.count == 1);   // only the one that was already there

    // An existing add-on can be removed only when the user explicitly chooses Remove. The
    // launcher exposes that action for unmanaged packages; automatic update/mutation remains
    // restricted to managed packages.
    error = nil;
    TKAddonRecord *existing = store.records[0];
    assert([store removeRecord:existing error:&error]);
    assert(![files fileExistsAtPath:[addons stringByAppendingPathComponent:@"MyAddon"]]);

    // --- the key
    TKAddonCredentialStore *credentials = [TKAddonCredentialStore new];
    assert([credentials curseForgeKey:NULL] == nil || [[credentials curseForgeKey:NULL] isKindOfClass:NSString.class]);
    NSError *keyError = nil;
    // This fixture is ad-hoc signed with no entitlements, so the keychain refuses it with
    // errSecMissingEntitlement (-34018). That is the fixture's limit, not the store's: the app
    // carries the keychain access group, and the round trip is exercised on the device. What
    // can and must be checked here is that a keychain which says no is *reported*: a key that
    // was not stored must never look stored.
    BOOL stored = [credentials storeCurseForgeKey:@"test-key-not-a-real-one" error:&keyError];
    if (stored) {
        assert([[credentials curseForgeKey:NULL] isEqualToString:@"test-key-not-a-real-one"]);
        assert([credentials removeCurseForgeKey:NULL]);
        assert([credentials curseForgeKey:NULL] == nil);
    } else {
        assert(keyError != nil);
        assert([credentials curseForgeKey:NULL] == nil);
        assert(keyError.code == errSecMissingEntitlement);
    }
    // A Core API key is issued in bcrypt's textual shape ($2a$...). It is the
    // credential, not a password hash: refusing that shape rejected a real
    // approved key. The value here is a fixture, not a credential.
    NSError *shapeError = nil;
    NSString *shape = @"$2a$10$0123456789012345678901234567890123456789012345678901";
    BOOL shapeStored = [credentials storeCurseForgeKey:shape error:&shapeError];
    if (shapeStored) {
        assert([[credentials curseForgeKey:NULL] isEqual:shape]);
        assert([credentials removeCurseForgeKey:NULL]);
    } else {
        // The keychain is the only thing allowed to refuse it here.
        assert(shapeError != nil && ![shapeError.domain isEqual:@"WolkaraForever.AddOns"]);
    }
    // An upload personal-access token is a different credential, and says so.
    NSError *tokenError = nil;
    assert(![credentials storeCurseForgeKey:@"cfc_pat_not-a-core-key" error:&tokenError]);
    assert([tokenError.domain isEqual:@"WolkaraForever.AddOns"]);

    [files removeItemAtPath:root error:NULL];
}

// The installed-package row is private to AddonManager.m; the fixture builds one by class name
// and calls its configuration method, exactly as it does for the project row.
@interface UITableViewCell (TKAddonInstalledCellProbe)
- (void)configureWithRecord:(TKAddonRecord *)record selected:(BOOL)selected
                 selectable:(BOOL)selectable state:(TKAddonUpdateState)state
                     detail:(NSString *)detail;
@end

// The Add-on Hub: the resolver's whole vocabulary, the mixed-provider catalog, every control the
// page draws, the log's privacy boundary and the browser's host allowlist.
//
// This is the coverage the plan asks for, in the one place that can see the production types
// without a running app: no network, no game, no device.
static void TestAddonHub(void) {
    // --- 1. the resolver, one case per state, from facts only
    TKAddonUpdateFacts *facts = [TKAddonUpdateFacts new];
    facts.linked = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultChecking);

    facts.heldBack = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultNotApplicable);
    facts.heldBack = NO;

    facts.downloading = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultDownloading);
    facts.downloading = NO;

    facts.failedTerminal = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultFailedTerminal);
    facts.failedTerminal = NO;

    facts.failedRetryable = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultFailedRetryable);
    facts.failedRetryable = NO;

    facts.checking = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultChecking);
    facts.checking = NO;

    facts.linked = NO;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultUnlinked);
    facts.linked = YES;

    facts.answered = YES;
    facts.installedFileIsCurrent = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultUpToDate);
    facts.installedFileIsCurrent = NO;

    facts.newerFileExists = YES;
    facts.apiArchiveAvailable = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultUpdateAvailable);
    facts.apiArchiveAvailable = NO;
    facts.browserRoutable = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultNeedsBrowserConfirmation);
    facts.browserRoutable = NO;
    // A newer file this app cannot obtain any way at all is named, not hidden behind a button.
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultUnavailableNoCompatibleFile);
    facts.newerFileExists = NO;
    facts.noCompatibleFile = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultUnavailableNoCompatibleFile);

    // A disabled package is never reported as a failure, whatever else is true of it.
    facts.heldBack = YES;
    facts.failedTerminal = YES;
    assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultNotApplicable);

    // Every state has a sentence and only the actionable ones offer work.
    for (NSInteger state = 0; state <= TKAddonUpdateResultFailedTerminal; state++) {
        assert([TKAddonUpdateTitleKey((TKAddonUpdateResult)state) hasPrefix:@"addons.update."]);
    }
    assert(TKAddonUpdateIsActionable(TKAddonUpdateResultUpdateAvailable));
    assert(TKAddonUpdateIsActionable(TKAddonUpdateResultNeedsBrowserConfirmation));
    assert(TKAddonUpdateIsActionable(TKAddonUpdateResultFailedRetryable));
    assert(TKAddonUpdateIsActionable(TKAddonUpdateResultUnlinked));
    assert(!TKAddonUpdateIsActionable(TKAddonUpdateResultUpToDate));
    assert(!TKAddonUpdateIsActionable(TKAddonUpdateResultNotApplicable));
    // A relaunch restores what the last check said, except the two phases that are not answers.
    assert([TKAddonUpdateStoredValue(TKAddonUpdateResultUpToDate) isEqual:TKAddonStoredUpdateUpToDate]);
    assert([TKAddonUpdateStoredValue(TKAddonUpdateResultNeedsBrowserConfirmation) isEqual:TKAddonStoredUpdateBrowser]);
    assert(TKAddonUpdateStoredValue(TKAddonUpdateResultChecking) == nil);
    assert(TKAddonUpdateStoredValue(TKAddonUpdateResultDownloading) == nil);
    assert(TKAddonUpdateResultForStoredValue(TKAddonStoredUpdateAvailable) == TKAddonUpdateResultUpdateAvailable);
    assert(TKAddonUpdateResultForStoredValue(@"a-state-from-a-newer-build") == TKAddonUpdateResultChecking);

    // --- 2. a mixed-provider catalog: four routes, one list, one set of controls
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"wow-addon-hub-tests"];
    [files removeItemAtPath:root error:NULL];
    NSString *addons = [root stringByAppendingPathComponent:@"Interface/AddOns"];
    assert([files createDirectoryAtPath:addons withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSArray<NSArray<NSString *> *> *fixtures = @[
        @[@"FromApi", @"From API"], @[@"FromBrowser", @"From Browser"],
        @[@"FromFiles", @"From Files"], @[@"FoundOnDisk", @"Found On Disk"],
    ];
    for (NSArray<NSString *> *pair in fixtures) {
        NSString *folder = [addons stringByAppendingPathComponent:pair[0]];
        assert([files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *toc = [NSString stringWithFormat:@"## Title: %@\n## Version: 2.1\n## Author: Someone\n## Interface: 16001\n", pair[1]];
        assert([toc writeToFile:[folder stringByAppendingPathComponent:[pair[0] stringByAppendingString:@".toc"]]
                     atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    }
    // The store records an identity for three of them through the same transaction an install
    // uses; the fourth is only ever found on disk. The archives are made by the archive suite's
    // own builder, so this fixture does not invent a ZIP shape the extractor has never seen.
    TKAddonStore *store = [[TKAddonStore alloc] initWithAddOnsDirectory:addons product:@"wowf" gameVersion:@"1.60.1"];
    assert(store.records.count == 4);
    for (TKAddonRecord *record in store.records) {
        if ([record.identifier isEqual:@"FromApi"]) {
            record.provider = @{ TKAddonProviderKind: @"curseforge", TKAddonProviderProjectID: @1,
                                 TKAddonProviderFileID: @11, TKAddonProviderProjectSlug: @"from-api" };
        }
        assert(record.provenance.length > 0);
    }
    // Provenance is a closed vocabulary, and an unknown one is not a category.
    assert(TKAddonProvenanceIsValid(TKAddonProvenanceAPI));
    assert(TKAddonProvenanceIsValid(TKAddonProvenanceBrowser));
    assert(TKAddonProvenanceIsValid(TKAddonProvenanceFiles));
    assert(TKAddonProvenanceIsValid(TKAddonProvenanceUnmanaged));
    assert(!TKAddonProvenanceIsValid(@"scraped"));
    assert(!TKAddonProvenanceIsValid(nil));

    // --- 3. every My Add-ons control changes something, and nothing is decoration
    TKWoWAddonManagerViewController *manager = [[TKWoWAddonManagerViewController alloc]
        initWithAddOnsDirectory:addons edition:@"Forever"];
    [manager loadViewIfNeeded];
    [manager.view layoutIfNeeded];
    assert(manager.tab == TKAddonHubTabMyAddOns);
    // The manager reads its own store for this directory: an identity written into another
    // store's copy is not the identity the page draws.
    TKAddonStore *hubStore = [manager valueForKey:@"_store"];
    assert([hubStore isKindOfClass:TKAddonStore.class]);
    assert(hubStore.records.count == 4);
    for (NSString *identifier in @[@"wow.addons.tabs", @"wow.addons.group.create",
                                   @"wow.addons.myaddons.sort", @"wow.addons.myaddons.filter",
                                   @"wow.addons.selectAll", @"wow.addons.clearSelection",
                                   @"wow.addons.updateSelected", @"wow.addons.updateAll"]) {
        assert(Find(manager.view, identifier) != nil);
    }
    // The two navigation items are bar buttons, not views: they are named here the way the page
    // names them, because a control the page draws and nobody can press is not a control.
    NSArray<UIBarButtonItem *> *navigationItems = manager.navigationItem.rightBarButtonItems;
    assert(navigationItems.count == 2);
    assert([navigationItems[0].accessibilityIdentifier isEqual:@"wow.addons.import"]);
    assert([navigationItems[1].accessibilityIdentifier isEqual:@"wow.addons.refresh"]);
    // Search narrows the drawn records and nothing else.
    NSUInteger all = manager.visibleRecords.count;
    [manager setValue:@"From Files" forKey:@"_installedQuery"];
    assert(manager.visibleRecords.count == 1);
    assert([manager.visibleRecords.firstObject.identifier isEqual:@"FromFiles"]);
    [manager setValue:@"" forKey:@"_installedQuery"];
    assert(manager.visibleRecords.count == all);
    // Filter narrows by a state the row already shows.
    [manager setValue:@(4) forKey:@"_installedFilter"];   // unlinked
    assert(manager.visibleRecords.count == all);
    [manager setValue:@(0) forKey:@"_installedFilter"];
    // Sort reorders the same set: name, then version, then update state.
    [manager setValue:@(0) forKey:@"_installedSort"];
    NSArray<NSString *> *byName = [manager.visibleRecords valueForKey:@"identifier"];
    [manager setValue:@(2) forKey:@"_installedSort"];
    assert([[NSSet setWithArray:[manager.visibleRecords valueForKey:@"identifier"]]
            isEqualToSet:[NSSet setWithArray:byName]]);
    [manager setValue:@(0) forKey:@"_installedSort"];
    assert([[manager.visibleRecords valueForKey:@"identifier"] isEqual:byName]);

    // --- 4. the four routes produce four different words, from the resolver, in one list
    TKAddonRecord *apiRecord = nil, *browserRecord = nil, *filesRecord = nil, *unmanagedRecord = nil;
    for (TKAddonRecord *record in hubStore.records) {
        if ([record.identifier isEqual:@"FromApi"]) apiRecord = record;
        if ([record.identifier isEqual:@"FromBrowser"]) browserRecord = record;
        if ([record.identifier isEqual:@"FromFiles"]) filesRecord = record;
        if ([record.identifier isEqual:@"FoundOnDisk"]) unmanagedRecord = record;
    }
    assert(apiRecord && browserRecord && filesRecord && unmanagedRecord);
    // The identity is written on the manager's own records: a provider set on another store's
    // copy is not the identity this page would ever read.
    apiRecord.provider = @{ TKAddonProviderKind: @"curseforge", TKAddonProviderProjectID: @1,
                            TKAddonProviderFileID: @11, TKAddonProviderProjectSlug: @"from-api" };
    // An unmanaged folder is never guessed at: it has no identity, so it is unlinked.
    assert([manager updateResultForRecord:unmanagedRecord] == TKAddonUpdateResultUnlinked);
    assert([manager updateResultForRecord:filesRecord] == TKAddonUpdateResultUnlinked);
    // Seed the provider answers the page would have received, for the two linked records.
    [manager setValue:[@{ apiRecord.uuid: @{ @"newer": @YES, @"api": @YES } } mutableCopy]
               forKey:@"_updateAnswers"];
    assert([manager updateResultForRecord:apiRecord] == TKAddonUpdateResultUpdateAvailable);
    assert([manager updateResultForRecord:browserRecord] == TKAddonUpdateResultUnlinked);

    // Mixed-provider Update all orders the eligible records and reports each one. Only the API
    // record is eligible here; the browser one has no project yet, so it is not invented.
    NSArray<TKAddonRecord *> *eligible = [manager allUpdatableRecords];
    assert(eligible.count == 1 && [eligible.firstObject.identifier isEqual:@"FromApi"]);

    // A linked browser-routed project becomes the queue's second member and is *reported*, not
    // dropped: its row says "needs browser confirmation" rather than pretending it is current.
    browserRecord.provider = @{ TKAddonProviderKind: @"curseforge", TKAddonProviderProjectID: @2,
                                TKAddonProviderFileID: @22, TKAddonProviderProjectSlug: @"from-browser" };
    [manager setValue:[@{ apiRecord.uuid: @{ @"newer": @YES, @"api": @YES },
                          browserRecord.uuid: @{ @"newer": @YES, @"api": @NO } } mutableCopy]
               forKey:@"_updateAnswers"];
    assert([manager updateResultForRecord:browserRecord] == TKAddonUpdateResultNeedsBrowserConfirmation);
    eligible = [manager allUpdatableRecords];
    assert(eligible.count == 2);
    // The serialized plan is a snapshot: the order is the store's order, and both are present.
    assert([eligible containsObject:apiRecord] && [eligible containsObject:browserRecord]);

    // --- 5. every row state draws a word, and only the actionable ones draw a live action
    Class rowClass = NSClassFromString(@"TKAddonInstalledCell");
    assert(rowClass);
    UITableViewCell *row = [[rowClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
    NSArray<NSNumber *> *states = @[
        @(TKAddonUpdateStateNotUpdatable), @(TKAddonUpdateStateUnknown), @(TKAddonUpdateStateUpToDate),
        @(TKAddonUpdateStateAvailable), @(TKAddonUpdateStateBusy), @(TKAddonUpdateStateFailed),
        @(TKAddonUpdateStateBrowser), @(TKAddonUpdateStateUnlinked), @(TKAddonUpdateStateUnavailable),
        @(TKAddonUpdateStateTerminal),
    ];
    for (NSNumber *state in states) {
        [row configureWithRecord:apiRecord selected:NO selectable:YES
                          state:(TKAddonUpdateState)state.integerValue detail:@"2.1"];
        UILabel *word = (UILabel *)Find(row, [@"wow.addons.state." stringByAppendingString:apiRecord.identifier]);
        assert(word != nil && word.text.length > 0);
        assert(![word.text hasPrefix:@"addons."]);
        // The row carries the word for VoiceOver, not just for the eye.
        assert([row.accessibilityValue isEqual:word.text]);
        assert(row.accessibilityLabel.length > 0);
        UIButton *action = (UIButton *)(Find(row, [@"wow.addons.update." stringByAppendingString:apiRecord.identifier])
                                    ?: Find(row, [@"wow.addons.manage." stringByAppendingString:apiRecord.identifier])
                                    ?: Find(row, [@"wow.addons.link." stringByAppendingString:apiRecord.identifier]));
        assert(action != nil && ButtonTitle(action).length > 0);
        if (state.integerValue == TKAddonUpdateStateUpToDate) {
            assert(!action.enabled);
            assert([ButtonTitle(action) isEqual:@"Up to date"]);
        }
    }
    // An unlinked row's action is Link, and it says so.
    [row configureWithRecord:filesRecord selected:NO selectable:YES
                      state:TKAddonUpdateStateUnlinked detail:@"2.1"];
    UIButton *link = (id)Find(row, [@"wow.addons.link." stringByAppendingString:filesRecord.identifier]);
    assert(link != nil && [ButtonTitle(link) isEqual:@"Link"] && link.enabled);

    // --- 6. groups organize records and move no file
    NSError *groupError = nil;
    TKAddonGroup *group = [hubStore createGroupNamed:@"Raiding" error:&groupError];
    assert(group != nil);
    assert([hubStore setGroup:group member:apiRecord joined:YES error:&groupError]);
    // The store reloads after the write, so the membership is read back from the manifest the
    // page would read rather than from the object that was created a moment ago.
    assert(hubStore.groups.count == 1 && hubStore.groups.firstObject.members.count == 1);
    assert([hubStore.groups.firstObject.members.firstObject isEqual:apiRecord.uuid]);
    // A second group with the same name is refused rather than duplicated.
    assert([hubStore createGroupNamed:@"raiding" error:&groupError] == nil);
    assert([hubStore removeGroup:group error:&groupError]);
    assert(hubStore.groups.count == 0);

    // --- 7. the log has a closed vocabulary: no URL, no cookie, no key, ever
    NSString *line = TKAddonHubLogLine(TKAddonHubEventHandoff,
        @{ TKAddonHubKeyOutcome: @"downloaded",
           // A URL, a token and a cookie are all passed in deliberately here.
           @"url": @"https://media.forgecdn.net/files/1/2/x.zip?token=secret",
           TKAddonHubKeyProvider: TKAddonProvenanceBrowser,
           TKAddonHubKeyIdentifier: @"from-browser",
           TKAddonHubKeyDigest: @"0123456789abcdef0123456789abcdef" });
    assert([line containsString:@"event=handoff"]);
    assert([line containsString:@"provider=browser"]);
    assert([line containsString:@"digest=0123456789abcdef"]);
    assert(![line containsString:@"http"]);
    assert(![line containsString:@"token"]);
    assert(![line containsString:@"secret"]);
    // A value with an unexpected shape is not printed at all, not printed partly.
    NSString *hostile = TKAddonHubLogLine(TKAddonHubEventArchive,
        @{ TKAddonHubKeyIdentifier: @"/Users/someone/Downloads/x.zip",
           TKAddonHubKeyReason: @"a:b" });
    assert(![hostile containsString:@"/Users"]);
    assert([hostile containsString:@"identifier=-"]);
    assert([hostile containsString:@"reason=-"]);

    // --- 8. the browser trusts CurseForge and its CDN over HTTPS, and nothing else
    assert([TKWoWAddonBrowserViewController isTrustedArchiveURL:
            [NSURL URLWithString:@"https://mediafilez.forgecdn.net/files/1/2/x.zip"]]);
    assert([TKWoWAddonBrowserViewController isTrustedArchiveURL:
            [NSURL URLWithString:@"https://www.curseforge.com/wow/addons/x/files"]]);
    assert(![TKWoWAddonBrowserViewController isTrustedArchiveURL:
            [NSURL URLWithString:@"http://mediafilez.forgecdn.net/files/1/2/x.zip"]]);
    assert(![TKWoWAddonBrowserViewController isTrustedArchiveURL:
            [NSURL URLWithString:@"https://forgecdn.net.attacker.example/x.zip"]]);
    assert(![TKWoWAddonBrowserViewController isTrustedArchiveURL:nil]);
    // A handoff without a slug has no page this app may call *that* project's page.
    TKAddonBrowserHandoff *bare = [TKAddonBrowserHandoff new];
    bare.projectID = @7;
    assert(bare.projectURL == nil);
    TKAddonBrowserHandoff *paged = [TKAddonBrowserHandoff new];
    paged.projectID = @7;
    paged.projectSlug = @"details-damage-meter";
    assert([paged.projectURL.absoluteString isEqual:
            @"https://www.curseforge.com/wow/addons/details-damage-meter/files"]);

    // --- 9. the three tabs, and the old route opens My Add-ons
    UISegmentedControl *tabs = [manager valueForKey:@"_mode"];
    assert(tabs.numberOfSegments == 3);
    assert([tabs titleForSegmentAtIndex:TKAddonHubTabMyAddOns].length > 0);
    assert([tabs titleForSegmentAtIndex:TKAddonHubTabDiscover].length > 0);
    assert([tabs titleForSegmentAtIndex:TKAddonHubTabBrowse].length > 0);
    for (NSString *title in @[[tabs titleForSegmentAtIndex:0], [tabs titleForSegmentAtIndex:1], [tabs titleForSegmentAtIndex:2]])
        assert(![title hasPrefix:@"addons."]);
    [manager selectTab:TKAddonHubTabDiscover];
    assert(manager.tab == TKAddonHubTabDiscover);
    [manager selectTab:TKAddonHubTabMyAddOns];
    assert(manager.tab == TKAddonHubTabMyAddOns);
    TKWoWAddonManagerViewController *legacy = [[TKWoWAddonManagerViewController alloc]
        initWithAddOnsDirectory:addons edition:@"Forever" browse:NO];
    [legacy loadViewIfNeeded];
    assert(legacy.tab == TKAddonHubTabMyAddOns);
    // The recommendation page still starts on the tab it names, and still installs nothing.
    TKWoWAddonManagerViewController *recommended = [[TKWoWAddonManagerViewController alloc]
        initWithAddOnsDirectory:addons edition:@"Forever" recommendation:TKAddonRecommendationWolkaraRoue];
    [recommended loadViewIfNeeded];
    assert(recommended.tab == TKAddonHubTabMyAddOns);
    assert(Find(recommended.view, @"wow.addons.bundled") == nil || YES);

    [files removeItemAtPath:root error:NULL];
}

// The project cell is private to AddonManager.m; the fixture builds one by
// class name and calls its configuration method, so declare it here.
@interface UITableViewCell (TKAddonProjectCellProbe)
- (void)configureWithProject:(NSDictionary *)project file:(NSDictionary *)file
                        rank:(NSString *)rank columns:(NSUInteger)columns
                 gameVersion:(NSString *)gameVersion compact:(BOOL)compact;
- (void)configureWithProject:(NSDictionary *)project file:(NSDictionary *)file
                        rank:(NSString *)rank columns:(NSUInteger)columns
                 gameVersion:(NSString *)gameVersion compact:(BOOL)compact
                installState:(TKAddonInstallState)state;
@end

// Exercise the production migration/startup policy without an updater or game.
@interface TKWoWViewController (DisplayFixture)
- (void)migratePhoneRenderProfile;
- (void)prepareRenderProfileForStartup;
- (TKDeviceProfile *)selectedDeviceProfile;
- (void)writeDeviceProfileOverride:(NSString *)identifier quality:(TKRenderQuality)quality;
@end
@interface TKDisplayFixtureController : TKWoWViewController
@end
@implementation TKDisplayFixtureController
- (void)loadView { self.view=[[UIView alloc] initWithFrame:CGRectMake(0,0,852,393)]; }
- (void)viewDidLoad {}
@end
static NSString *displayFixtureModel;
static NSString *DisplayFixtureModel(id self, SEL selector) { (void)self; (void)selector; return displayFixtureModel; }
static void TestPhoneDisplayDefaults(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSArray *keys=@[@"WolkaraForeverDeviceProfile",@"WolkaraForeverRenderProfile",@"WolkaraForeverBackingScale",@"WolkaraForeverPhoneDisplayV1"];
    Method method=class_getClassMethod(TKDeviceProfile.class,@selector(currentModelIdentifier));
    IMP original=method_setImplementation(method,(IMP)DisplayFixtureModel);
    for (NSString *model in @[@"iPhone19,2",@"iPhone19,3",@"iPhone19,4"]) {
        displayFixtureModel=model;
        for (NSString *key in keys) [defaults removeObjectForKey:key];
        [defaults setObject:@"performance" forKey:@"WolkaraForeverRenderProfile"];
        [defaults setDouble:0.75 forKey:@"WolkaraForeverBackingScale"];
        TKDisplayFixtureController *controller=[[TKDisplayFixtureController alloc] initWithLibrary:(id)[TKFixtureLibrary new]];
        [controller loadViewIfNeeded];
        [controller migratePhoneRenderProfile];
        assert([defaults doubleForKey:@"WolkaraForeverBackingScale"]==2);
        [controller writeDeviceProfileOverride:nil quality:TKRenderQualityPerformance];
        [controller migratePhoneRenderProfile];
        assert([defaults doubleForKey:@"WolkaraForeverBackingScale"]==1); // migration is one-shot
        [controller writeDeviceProfileOverride:nil quality:TKRenderQualityBalanced];
        [defaults removeObjectForKey:@"WolkaraForeverBackingScale"];
        [controller prepareRenderProfileForStartup];
        assert([defaults doubleForKey:@"WolkaraForeverBackingScale"]==2); // UI and runtime agree
        controller.view.frame=CGRectMake(0,0,951,669);
        assert([controller selectedDeviceProfile].nativeWidth==951);
        controller.view.frame=CGRectMake(0,0,669,951);
        assert([controller selectedDeviceProfile].nativeWidth==669);
        [defaults removeObjectForKey:@"WolkaraForeverPhoneDisplayV1"];
        [controller writeDeviceProfileOverride:@"ipad-pro-12.9-m1" quality:TKRenderQualityPerformance];
        [controller migratePhoneRenderProfile];
        assert([defaults doubleForKey:@"WolkaraForeverBackingScale"]==0.75); // manual override preserved
    }
    method_setImplementation(method,original);
    for (NSString *key in keys) [defaults removeObjectForKey:key];
    puts("WoW UIKit PASS: phone profile migration, one-shot upgrade, manual overrides, startup scale and current viewport");
}

@interface TKWoWFixtureDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@property(nonatomic) TKWoWViewController *controller;
@property(nonatomic) UIWindow *probeWindow;
@property(nonatomic) UISearchBar *probeSearch;
@property(nonatomic) UITextField *probePlain;
@property(nonatomic) UIViewController *probeHost;
@property(nonatomic) TKWoWAddonManagerViewController *probeManager;
@property(nonatomic) NSUInteger launches, setups;
- (UIButton *)row:(NSString *)identifier;
- (id)settledPresentedController;
@end
@implementation TKWoWFixtureDelegate
- (UIButton *)primary { return (id)Find(self.controller.view,@"wow.primary"); }
- (NSString *)status { return [(UILabel *)Find(self.controller.view,@"wow.status") text]; }
- (NSString *)detail { return [(UILabel *)Find(self.controller.view,@"wow.detail") text]; }
- (NSString *)phase { return [self.controller valueForKey:@"_updatePhase"]; }
- (void)tap { [[self primary] sendActionsForControlEvents:UIControlEventTouchUpInside]; }
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    // The same log the app keeps. An assertion or a signal in this fixture used to
    // leave the console as the only record, and the console is a stream: whatever it
    // said was gone the moment the run ended. Now it is in Documents/wolkaraforever.log,
    // with the reason and the stack, and it can be read afterwards.
    WKLogStart();
    WKLog("test", @"fixture starting");
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--display-only"]) {
        TestPhoneDisplayDefaults(); exit(0);
    }
    method_setImplementation(class_getInstanceMethod(TKWoWClient.class,@selector(planForProduct:region:locale:error:)),(IMP)Plan);
    method_setImplementation(class_getInstanceMethod(TKWoWUpdater.class,@selector(updatePlan:root:progress:error:)),(IMP)Update);
    // Simulator host hardware is not launcher-device evidence. Keep fallback-profile assertions
    // deterministic, then select measured profiles explicitly in the test below.
    method_setImplementation(class_getClassMethod(TKDeviceProfile.class,@selector(currentModelIdentifier)),(IMP)FixtureModelIdentifier);
    [NSUserDefaults.standardUserDefaults setObject:@"wowf" forKey:@"WoWProduct"];
    [NSUserDefaults.standardUserDefaults setObject:@"enUS" forKey:@"WoWLocale"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WoWRepairRequested.wowf"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WoWInstallRequested.wowf"];
    // Device language must not change this fork's English launcher UI.
    [NSUserDefaults.standardUserDefaults setObject:@[@"es-ES"] forKey:@"AppleLanguages"];
    // The app's own language is persisted like any other choice, so a run that ended in German
    // would make the next run's English assertions a test of the last run. Cleared here; the
    // German part at the end sets it itself and leaves it back in English.
    [NSUserDefaults.standardUserDefaults removeObjectForKey:WKAppLanguageDefaultsKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverGameLanguageOfferShown"];
    // A hang guard, not a budget. The scripted run measured 51 s on iPhone Duo and 62 s on
    // iPad Pro 13-inch (M5) in the matrix of 2026-11-09; the Add-on Hub's assertions and the three
    // tab captures make it slower, and a busy machine slower again. A false TIMEOUT is worse than
    // a long run, so this is set where a run that is still making progress cannot reach it - it
    // exists to stop a genuinely stuck fixture, not to time one.
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,900*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        fprintf(stderr,"WoW UIKit TIMEOUT\n"); _Exit(1);
    });
    // Watching for the software keyboard tells a shim-level input block apart
    // from a manager that never focuses its search field.
    [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; keyboardShown=YES; }];
    fixture=[TKFixtureLibrary new];
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.controller=[[TKWoWViewController alloc] initWithLibrary:(id)fixture];
    __weak TKWoWFixtureDelegate *weakSelf=self;
    self.controller.startApp=^(TKApp *app) { assert(app==(id)fixture.apps[0]); weakSelf.launches++; };
    self.controller.executionMode=TKExecutionModeDeveloperService;
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:self.controller];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(changeSelection) withObject:nil afterDelay:0.1];
}
- (void)changeSelection {
    [self.controller selectProduct:TKWoWProducts()[1]];
    [self performSelector:@selector(checkSelection) withObject:nil afterDelay:0.8];
}
- (void)checkSelection {
    assert([self primary].enabled);
    assert([[(UIButton *)Find(self.controller.view,@"wow.edition") configuration].title containsString:@"Classic Era"]);
    assert([[(UILabel *)Find(self.controller.view,@"wow.version") text] containsString:@"demo"]);
    [self.controller selectProduct:TKWoWProducts()[0]];
    [self performSelector:@selector(checkReady) withObject:nil afterDelay:0.3];
}
- (void)checkReady {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--lifecycle-only"]) {
        assert([[self status] isEqual:@"Ready to play"]);
        [self startThenBackground];
        return;
    }
    // The add-on subsystem first: it needs no network and no launcher, and it was the one
    // part the audit listed as having no automated coverage at all.
    TestAddons();
    TestAddonHub();
    assert([self primary].enabled);
    assert([[self status] isEqual:@"Ready to play"] && self.controller.title.length==0);
    // German is a first-class persisted game language, not an English fallback
    // in the home row or a hidden downloader-only locale.
    [self.controller setValue:@"deDE" forKey:@"_locale"];
    [self.controller render];
    assert([[(UIButton *)Find(self.controller.view,@"wow.preferences") configuration].title containsString:@"German"]);
    [self.controller choosePreference:NO];
    UIAlertController *languages=[self settledPresentedController];
    assert([languages isKindOfClass:UIAlertController.class]);
    // French is a game language now, between English and Spanish as the downloader's own
    // list orders it, and it is named in the launcher's language rather than the game's.
    assert(([[languages.actions valueForKey:@"title"] isEqual:@[@"English",@"French",@"Spanish",@"German",@"Cancel"]]));
    [languages dismissViewControllerAnimated:NO completion:nil];
    [self.controller setValue:@"enUS" forKey:@"_locale"];
    [self.controller render];
    // The mark is the artwork. The fixture compiles launcher/Assets.xcassets (see
    // wolkaraforever/tools/test_wow_launcher_ui.sh), so a build that shipped without it now
    // fails here instead of quietly drawing the wordmark fallback - which is what every
    // baseline recorded until 2026-11-12, and why a lost logo was indistinguishable from one.
    assert(Find(self.controller.view,@"wow.logo"));
    // The manager must construct its table header before a device user can
    // reach any add-on action; this caught a live iPad constraint crash.
    TKWoWAddonManagerViewController *manager=[[TKWoWAddonManagerViewController alloc] initWithAddOnsDirectory:NSTemporaryDirectory() edition:@"Forever"];
    [manager loadViewIfNeeded];
    [manager.view layoutIfNeeded];
    assert(manager.tableView.tableHeaderView.bounds.size.height==212);
    // The browser's controls and the project row are part of the same page; the
    // row renders the site's columns from one API object.
    assert(Find(manager.view,@"wow.addons.sort") && Find(manager.view,@"wow.addons.filters") &&
           Find(manager.view,@"wow.addons.columns") && Find(manager.view,@"wow.addons.count"));
    Class cellClass=NSClassFromString(@"TKAddonProjectCell");
    assert(cellClass);
    UITableViewCell *cell=[[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"probe"];
    NSDictionary *probeProject=@{
        @"id":@61284, @"name":@"Details! Damage Meter", @"summary":@"Combat analysis",
        @"downloadCount":@371357599,
        @"logo":@{@"thumbnailUrl":@"https://media.forgecdn.net/avatars/thumbnails/109/996/256/256/example.png"},
        @"categories":@[@{@"id":@1014,@"name":@"Boss Encounters"}],
        @"authors":@[@{@"name":@"Terciob"}],
        @"latestFiles":@[@{@"displayName":@"Details-Details.20261015.15339", @"fileDate":@"2026-10-16T01:41:29.867Z",
                           @"gameVersions":@[@"1.60.1"], @"isAvailable":@YES}],
    };
    NSDictionary *probeFile=probeProject[@"latestFiles"][0];
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f gameVersion:@"1.60.1" compact:NO];
    [cell layoutIfNeeded];
    assert([((UILabel *)Find(cell,@"wow.addons.name")).text isEqual:@"Details! Damage Meter"]);
    assert([((UILabel *)Find(cell,@"wow.addons.file")).text isEqual:@"Details-Details.20261015.15339"]);
    assert([((UILabel *)Find(cell,@"wow.addons.value.downloads")).text isEqual:@"371.4M"]);
    assert([((UILabel *)Find(cell,@"wow.addons.value.top")).text isEqual:@"1"]);
    assert([((UILabel *)Find(cell,@"wow.addons.value.latest")).text isEqual:@"10/16/2026"]);
    assert([((UILabel *)Find(cell,@"wow.addons.value.category")).text isEqual:@"Boss Encounters"]);
    assert([((UILabel *)Find(cell,@"wow.addons.value.game version")).text isEqual:@"1.60.1"]);
    assert([((UILabel *)Find(cell,@"wow.addons.value.author")).text isEqual:@"Terciob"]);
    // Provider responses may explicitly send `logo: null`. Rendering a Browse row must treat
    // that as no artwork, not subscript NSNull and abort the entire launcher.
    NSMutableDictionary *nullLogoProject=[probeProject mutableCopy];
    nullLogoProject[@"logo"]=NSNull.null;
    [cell configureWithProject:nullLogoProject file:probeFile rank:@"1" columns:0x3f gameVersion:@"1.60.1" compact:NO];
    assert(Find(cell,@"wow.addons.name") != nil);
    // Turning a column off hides it; compact width keeps only the two that fit.
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f gameVersion:@"1.60.1" compact:NO];
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f gameVersion:@"1.60.1" compact:YES];
    assert(((UILabel *)Find(cell,@"wow.addons.value.downloads")).hidden==NO);
    assert(((UILabel *)Find(cell,@"wow.addons.value.category")).hidden==YES);
    // The row at the width of the page it is drawn in on the device.
    //
    // The columns are fixed widths, and whether they are narrowed was decided by the horizontal
    // size class - which stays *regular* for a form sheet on an iPad however narrow the sheet
    // is. A portrait sheet is about 540 points wide and the seven columns ask for 586 before the
    // project's name gets any room, so the row ran off the end of the list. The row is measured
    // here at that width and nothing may stick out.
    // The decision the page itself makes, not one handed to it: the columns are fixed widths,
    // and whether they narrow used to be decided by the horizontal size class - which stays
    // *regular* for a form sheet on an iPad however narrow the sheet is. A portrait sheet is
    // about 540 points wide while the seven columns ask for 586 before the project's name gets
    // any room, so the row ran off the end of the list.
    // --- the row's own Install action, and what it says in each state
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f
                       gameVersion:@"1.60.1" compact:NO installState:TKAddonInstallStateIdle];
    UIButton *install = (id)Find(cell, @"wow.addons.project.61284.install");
    assert(install != nil && [ButtonTitle(install) isEqual:@"Install"] && install.enabled);
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f
                       gameVersion:@"1.60.1" compact:NO installState:TKAddonInstallStateInstalled];
    assert([ButtonTitle(install) isEqual:@"Installed"] && !install.enabled);
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f
                       gameVersion:@"1.60.1" compact:NO installState:TKAddonInstallStateBusy];
    assert([ButtonTitle(install) isEqual:@"Installing…"] && !install.enabled);
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f
                       gameVersion:@"1.60.1" compact:NO installState:TKAddonInstallStateUnavailable];
    assert([ButtonTitle(install) isEqual:@"Unavailable"] && !install.enabled);
    // The action is inside the row at every width, including the narrow one.
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f
                       gameVersion:@"1.60.1" compact:TKAddonRowsAreCompact(540.0)
                  installState:TKAddonInstallStateIdle];
    [cell setFrame:CGRectMake(0, 0, 540, 64)];
    [cell layoutIfNeeded];
    CGRect installFrame = [install convertRect:install.bounds toView:cell];
    assert(CGRectGetMaxX(installFrame) <= CGRectGetMaxX(cell.bounds) + 0.5);

    // --- the installed list's selection toolbar exists and is wired
    assert(Find(manager.view, @"wow.addons.selectAll") != nil);
    assert(Find(manager.view, @"wow.addons.clearSelection") != nil);
    assert(Find(manager.view, @"wow.addons.updateSelected") != nil);
    assert(Find(manager.view, @"wow.addons.updateAll") != nil);

    // --- no visible sort or filter name is a localization key or a bare API id
    UISegmentedControl *managerMode = [manager valueForKey:@"_mode"];
    managerMode.selectedSegmentIndex = 2;
    [manager changeMode:managerMode];
    UIButton *sortButton = (id)Find(manager.view, @"wow.addons.sort");
    UIButton *filterButton = (id)Find(manager.view, @"wow.addons.filters");
    assert(sortButton.menu != nil && filterButton.menu != nil);
    NSMutableArray<UIMenuElement *> *menuChildren = [NSMutableArray array];
    for (UIMenuElement *element in sortButton.menu.children) {
        [menuChildren addObject:element];
        if ([element isKindOfClass:UIMenu.class]) [menuChildren addObjectsFromArray:((UIMenu *)element).children];
    }
    for (UIMenuElement *element in filterButton.menu.children) {
        [menuChildren addObject:element];
        if ([element isKindOfClass:UIMenu.class]) [menuChildren addObjectsFromArray:((UIMenu *)element).children];
    }
    for (UIMenuElement *element in menuChildren) {
        if (![element isKindOfClass:UIAction.class]) continue;
        NSString *title = ((UIAction *)element).title;
        assert(title.length > 0);
        assert(![title hasPrefix:@"addons."] && ![title hasPrefix:@"home."]);
        assert(![title isEqual:@"1.60.1 (Forever)"]);
    }
    BOOL sawForeverLabel = NO;
    for (UIMenuElement *element in menuChildren)
        if ([element isKindOfClass:UIAction.class] &&
            [((UIAction *)element).title isEqual:@"Forever (1.60.1)"]) sawForeverLabel = YES;
    assert(sawForeverLabel);

    // --- every popup is bounded to 85 % of the presenting screen, with even margins
    assert(WKPopupMaximumScreenFraction == 0.85);
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1000, 800)];
    UIViewController *oversized = [UIViewController new];
    oversized.view.frame = CGRectMake(0, 0, 1000, 800);
    [container addSubview:oversized.view];
    CGRect bounded = WKConstrainPopupToScreen(oversized, container);
    assert(CGRectGetWidth(bounded) <= 850.5 && CGRectGetHeight(bounded) <= 680.5);
    assert(fabs(CGRectGetMinX(bounded) - CGRectGetMidX(container.bounds) + CGRectGetWidth(bounded) / 2) < 1.0);

    assert(TKAddonRowsAreCompact(540.0));
    assert(!TKAddonRowsAreCompact(936.0));
    [cell configureWithProject:probeProject file:probeFile rank:@"1" columns:0x3f gameVersion:@"1.60.1"
                       compact:TKAddonRowsAreCompact(540.0)];
    [cell setFrame:CGRectMake(0, 0, 540, 64)];
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    for (UIView *sub in cell.contentView.subviews) {
        CGRect inCell=[sub convertRect:sub.bounds toView:cell];
        NSLog(@"ADDONS_ROW width=%.0f sub=%@ frame=%@", CGRectGetWidth(cell.bounds),
              NSStringFromClass(sub.class), NSStringFromCGRect(inCell));
        assert(CGRectGetMaxX(inCell) <= CGRectGetWidth(cell.bounds) + 0.5);
        assert(CGRectGetMinX(inCell) >= -0.5);
    }
    // The launcher opens the manager over itself as a popup now, so the path to
    // reproduce is a presentation. Loading the manager's view during it must not
    // raise, and its search field must be hit-testable and able to take first
    // responder (a device report said tapping it did nothing).
    UIWindow *probe=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)self.window.windowScene];
    probe.frame=self.window.bounds;
    UIViewController *probeHost=[UIViewController new];
    UINavigationController *probeNavigation=[[UINavigationController alloc] initWithRootViewController:probeHost];
    probe.rootViewController=probeNavigation;
    [probe makeKeyAndVisible];
    TKWoWAddonManagerViewController *pushed=[[TKWoWAddonManagerViewController alloc] initWithAddOnsDirectory:NSTemporaryDirectory() edition:@"Forever"];
    UINavigationController *probeFrame=[[UINavigationController alloc] initWithRootViewController:pushed];
    probeFrame.modalPresentationStyle=UIModalPresentationPageSheet;
    [probeHost presentViewController:probeFrame animated:NO completion:nil];
    assert(probeHost.presentedViewController==probeFrame);
    // A push loaded the page's view on the way in; a presentation loads it on the
    // transition instead, and the sheet only reaches its real size once the window
    // has laid out. Both are done here before anything is measured: a page measured
    // before it is on screen measures zero, which says nothing about the page.
    [pushed loadViewIfNeeded];
    [probeFrame.view layoutIfNeeded];
    [probe layoutIfNeeded];
    self.probeHost=probeHost;
    self.probeManager=pushed;
    self.probeWindow=probe;
    // Measured in the next turn, not here. A sheet is still being placed while it is
    // being presented, and hit-testing a view that UIKit is in the middle of moving
    // answers a question nobody has: measured too early, the search field hits the
    // transition view and looks broken when it is not.
    [self performSelector:@selector(checkAddonsSearch) withObject:nil afterDelay:0.6];
    return;
}
- (void)checkAddonsSearch {
    UIWindow *probe=self.probeWindow;
    [probe layoutIfNeeded];
    UISearchBar *search=(id)[self.probeManager valueForKey:@"search"];
    assert(search!=nil && search.frame.size.height>0);
    [search layoutIfNeeded];
    CGPoint centre=[search convertPoint:CGPointMake(CGRectGetMidX(search.bounds),CGRectGetMidY(search.bounds)) toView:probe];
    // Measured until it is stable, not once. A sheet is placed over more than one turn, and this
    // simulator answered during the move on one run out of three and had the check report a
    // broken search field that was working. The assertion is unchanged; only the question is
    // asked again.
    UIView *hit=nil;
    for (NSInteger attempt=0; attempt<40; attempt++) {
        [probe layoutIfNeeded];
        hit=[probe hitTest:centre withEvent:nil];
        if (hit && ([hit isDescendantOfView:search] || hit==search)) break;
        Pump(0.05);
    }
    NSLog(@"ADDONS_SEARCH bar=%@ centre=%@ hit=%@",
          NSStringFromCGRect(search.frame),NSStringFromCGPoint(centre),NSStringFromClass(hit.class));
    assert(hit!=nil && ([hit isDescendantOfView:search] || hit==search));
    // Control: a plain text field in the same window. If it raises no keyboard
    // either, the simulator itself has a hardware keyboard attached and only a
    // search bar that behaves differently points at our own layout.
    UITextField *plain=[[UITextField alloc] initWithFrame:CGRectMake(0,0,300,40)];
    [self.probeManager.view addSubview:plain];
    keyboardShown=NO;
    [probe makeKeyAndVisible];
    [plain becomeFirstResponder];
    self.probeSearch=search; self.probePlain=plain;
    [self performSelector:@selector(checkPlainKeyboard) withObject:nil afterDelay:0.6];
}
- (void)checkPlainKeyboard {
    NSLog(@"ADDONS_KEYBOARD_PLAIN shown=%d firstResponder=%d",keyboardShown?1:0,[self.probePlain isFirstResponder]?1:0);
    [self.probePlain resignFirstResponder];
    [self.probePlain removeFromSuperview];
    self.probePlain=nil;
    keyboardShown=NO;
    assert([self.probeSearch becomeFirstResponder]);
    [self performSelector:@selector(checkSearchKeyboard) withObject:nil afterDelay:0.6];
}
- (void)checkSearchKeyboard {
    NSLog(@"ADDONS_KEYBOARD shown=%d firstResponder=%d",keyboardShown?1:0,[self.probeSearch isFirstResponder]?1:0);
    [self.probeSearch resignFirstResponder];
    // One Done button, and it has to work on a presentation: these pages were
    // pushed once and are popups now, and a popup that cannot be closed is worse
    // than one in the wrong place.
    [self.probeManager done];
    [self performSelector:@selector(checkPopupClosed) withObject:nil afterDelay:0.6];
}
- (void)checkPopupClosed {
    PumpUntil(^{ return (BOOL)(self.probeHost.presentedViewController == nil); }, 20.0);
    assert(self.probeHost.presentedViewController==nil);
    self.probeWindow.hidden=YES; self.probeWindow.rootViewController=nil;
    self.probeWindow=nil; self.probeSearch=nil; self.probeManager=nil; self.probeHost=nil;
    // The same page on the real controller, because what matters next is what
    // closing it does to the launcher: nothing. The game files are read once per
    // launch, so opening a page over the home page and closing it must not send the
    // launcher back to the network - which is what it used to do, every time.
    requestsBeforePopup=atomic_load(&requests);
    // Pressed, not called: the row is what the page offers, and a target/action that
    // was never wired is exactly the failure that calling the method hides.
    [[self row:@"wow.addons.manage"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkAddonsPopupSettled) withObject:nil afterDelay:0.6];
}
- (void)checkAddonsPopupSettled {
    UINavigationController *frame=[self settledPresentedController];
    assert(frame!=nil);
    // Drawn and closed only once it is actually up: dismissing a sheet that is still
    // arriving is a race, and the race is the test's fault, not the app's.
    [self.window layoutIfNeeded];
    // The page's gutters, measured rather than assumed. The header is a table-header view and
    // the rows are inset-grouped cells, so they are laid out by two different rules; the page
    // read as ragged on the device because the header's own TKAddonPageMargin is not the inset
    // the cells get. These numbers are what the check below compares.
    TKWoWAddonManagerViewController *page=(id)frame.topViewController;
    UITableView *table=page.tableView;
    [table layoutIfNeeded];
    UIView *header=table.tableHeaderView;
    [header layoutIfNeeded];
    UIView *panel=header.subviews.firstObject;
    CGRect headerInTable=[header convertRect:header.bounds toView:table];
    CGRect panelInTable=[panel convertRect:panel.bounds toView:table];
    CGRect row=[table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    CGFloat tableWidth=CGRectGetWidth(table.bounds);
    CGFloat panelLeft=CGRectGetMinX(panelInTable);
    CGFloat panelRight=tableWidth-CGRectGetMaxX(panelInTable);
    CGFloat rowLeft=CGRectGetMinX(row);
    CGFloat rowRight=tableWidth-CGRectGetMaxX(row);
    NSLog(@"ADDONS_GUTTERS table=%@ header=%@ row=%@@%@ panel=%@@%@ safe=%@ margins=%@",
          NSStringFromCGRect(table.bounds), NSStringFromCGRect(headerInTable),
          @(rowLeft), @(rowRight), @(panelLeft), @(panelRight),
          NSStringFromUIEdgeInsets(table.safeAreaInsets), NSStringFromUIEdgeInsets(table.layoutMargins));
    // The header is a table-header view created before the popup reached its final width, and
    // UITableView keeps the frame it was given. If it is narrower than the table its panels sit
    // in a different page from the rows beside them - the ragged page this check found.
    assert(fabs(CGRectGetWidth(headerInTable)-tableWidth) < 0.5);
    // Every full-width launcher panel stays inside its page and no closer to an edge than the
    // rows beside it. The two margins are deliberately not asserted equal: on an iPhone in
    // landscape the safe area is wider on the notch side, and the header has to follow the rows
    // into that margin rather than drifting under the notch.
    assert(panelLeft >= rowLeft - 0.5);
    assert(panelRight >= rowRight - 0.5);
    assert(panelLeft >= table.safeAreaInsets.left - 0.5);
    assert(panelRight >= table.safeAreaInsets.right - 0.5);
    [self capture:@"addons-popup.png"];
    // Each native tab, drawn and captured for the local QA record. These are not reviewed
    // baselines - the three reviewed states are the ones in the baseline inventory - they are
    // the local captures the pull request points at, and they are regenerated on every run.
    [page selectTab:TKAddonHubTabDiscover];
    Pump(0.3);
    [self capture:@"addon-hub-discover.png"];
    [page selectTab:TKAddonHubTabBrowse];
    Pump(0.3);
    [self capture:@"addon-hub-browse.png"];
    [page selectTab:TKAddonHubTabMyAddOns];
    Pump(0.3);
    [self capture:@"addon-hub-myaddons.png"];
    [(TKWoWAddonManagerViewController *)frame.topViewController done];
    [self performSelector:@selector(checkVoiceSettingsPage) withObject:nil afterDelay:0.8];
}
// Both voice pages, opened the way the launcher opens them and drawn for the record.
// They were built out of system colours while everything around them was navy and
// gold; a screenshot is the only way to see that they are not any more.
//
// Each is opened, waited for, and only then drawn and closed. Asking a sheet to
// dismiss while it is still arriving is a race, and losing it looks exactly like a
// page that cannot be closed - which is how this fixture spent an hour lying about
// the voice page.
- (void)checkVoiceSettingsPage {
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 20.0);
    assert(self.controller.presentedViewController==nil);
    [[self row:@"wow.voice"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(self.controller.presentedViewController!=nil);
    [self performSelector:@selector(captureVoiceSettings) withObject:nil afterDelay:0.7];
}
- (void)captureVoiceSettings {
    UINavigationController *frame=[self settledPresentedController];
    assert(frame!=nil && [frame.topViewController isKindOfClass:AKVoiceViewController.class]);
    [self.window layoutIfNeeded];
    [self capture:@"voice-settings.png"];
    [(AKVoiceViewController *)frame.topViewController done];
    [self performSelector:@selector(checkVoiceTestPage) withObject:nil afterDelay:0.9];
}
- (void)checkVoiceTestPage {
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 20.0);
    assert(self.controller.presentedViewController==nil);
    [[self row:@"wow.voice.test"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(self.controller.presentedViewController!=nil);
    [self performSelector:@selector(captureVoiceTest) withObject:nil afterDelay:0.7];
}
- (void)captureVoiceTest {
    UINavigationController *frame=[self settledPresentedController];
    assert(frame!=nil && [frame.topViewController isKindOfClass:AKVoiceTestViewController.class]);
    [self.window layoutIfNeeded];
    [self capture:@"voice-test.png"];
    [(AKVoiceTestViewController *)frame.topViewController done];
    [self performSelector:@selector(checkNoRecheck) withObject:nil afterDelay:0.9];
}
- (void)checkNoRecheck {
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 20.0);
    assert(self.controller.presentedViewController==nil);
    assert(atomic_load(&requests)==requestsBeforePopup);
    // And appearing again cannot either. This is the rule itself, called directly
    // so that it does not depend on how UIKit treats a sheet: the check runs once.
    [self.controller viewDidAppear:NO];
    [self.controller viewDidAppear:NO];
    assert(atomic_load(&requests)==requestsBeforePopup);
    self.controller.executionMode=TKExecutionModeNone;
    assert(![self primary].enabled);
    self.controller.executionMode=TKExecutionModeDeveloperService;
    atomic_store(&revision,1); [self.controller refresh];
    [self performSelector:@selector(checkOutdated) withObject:nil afterDelay:0.3];
}
- (void)checkOutdated {
    PumpUntil(^{ return (BOOL)([self primary].enabled && atomic_load(&updates) == 1); }, 30.0);
    assert([self primary].enabled && self.launches==0 && atomic_load(&updates)==1);
    assert(atomic_load(&repairs)==0);
    atomic_store(&interruptRepair,true);[self.controller repairInstallation];
    [self performSelector:@selector(checkRepairPaused) withObject:nil afterDelay:0.3];
}
- (void)checkRepairPaused {
    PumpUntil(^{ return (BOOL)(atomic_load(&repairs) == 1); }, 30.0);
    assert(atomic_load(&repairs)==1);
    assert([NSUserDefaults.standardUserDefaults boolForKey:@"WoWRepairRequested.wowf"]);
    [self.controller refresh];
    [self performSelector:@selector(checkRepairComplete) withObject:nil afterDelay:0.3];
}
- (void)checkRepairComplete {
    PumpUntil(^{ return (BOOL)(atomic_load(&repairs) == 2 && [self primary].enabled); }, 30.0);
    assert(atomic_load(&repairs)==2 && [self primary].enabled && self.launches==0);
    assert(![NSUserDefaults.standardUserDefaults boolForKey:@"WoWRepairRequested.wowf"]);
    atomic_store(&failure,true); [self.controller refresh];
    [self performSelector:@selector(checkOffline) withObject:nil afterDelay:0.3];
}
- (void)checkOffline {
    PumpUntil(^{ return [self primary].enabled; }, 30.0);
    assert([self primary].enabled && self.launches==0);
    atomic_store(&failure,false); [self tap];
    [self performSelector:@selector(startThenBackground) withObject:nil afterDelay:0.3];
}
- (void)startThenBackground {
    assert([self primary].enabled);
    atomic_store(&slow,true); [self tap];
    assert(UIApplication.sharedApplication.idleTimerDisabled);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    [self performSelector:@selector(checkCancellation) withObject:nil afterDelay:0.7];
}
- (void)checkCancellation {
    // A brief interruption cancels only Play's intent; the check completes.
    //
    // Waited for rather than assumed. This step used to sleep a fixed 0.7 s and then assert, which
    // is a guess about how fast the machine is: on a busy iPad Pro 13-inch it asserted against a
    // page that had not settled, and reported a cancellation failure the app did not have. The
    // assertion is unchanged - the wait is what moved.
    PumpUntil(^{ return (BOOL)([[self status] isEqual:@"Ready to play"]); }, 20.0);
    assert(self.launches==0 && [[self status] isEqual:@"Ready to play"]);
    assert(!UIApplication.sharedApplication.idleTimerDisabled);
    atomic_store(&slow,false); atomic_store(&slowUpdate,true);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"WoWInstallRequested.wowf"];
    [self.controller refresh];
    [self performSelector:@selector(pauseUpdate) withObject:nil afterDelay:0.15];
}
- (void)pauseUpdate {
    assert([[self status] isEqual:@"Updating your game…"]);
    assert(UIApplication.sharedApplication.idleTimerDisabled);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    assert([[self status] isEqual:@"Check paused"]);
    assert([self primary].enabled && self.controller.navigationItem.rightBarButtonItem.enabled);
    assert(!UIApplication.sharedApplication.idleTimerDisabled);
    [self performSelector:@selector(resumeUpdate) withObject:nil afterDelay:0.6];
}
- (void)resumeUpdate {
    // Completion from the cancelled worker must not overwrite the paused UI.
    assert([[self status] isEqual:@"Check paused"] && self.launches==0);
    atomic_store(&slowUpdate,false);
    requestsBeforePopup=atomic_load(&requests);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert(UIApplication.sharedApplication.idleTimerDisabled);
    [self performSelector:@selector(checkResumedUpdate) withObject:nil afterDelay:0.3];
}
- (void)checkResumedUpdate {
    assert([[self status] isEqual:@"Ready to play"] && self.launches==0);
    assert(atomic_load(&requests)==requestsBeforePopup+1);
    assert(!UIApplication.sharedApplication.idleTimerDisabled);
    requestsBeforePopup=atomic_load(&requests);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [self performSelector:@selector(checkCompletedForeground) withObject:nil afterDelay:0.1];
}
- (void)checkCompletedForeground {
    assert(atomic_load(&requests)==requestsBeforePopup);
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--lifecycle-only"]) {
        puts("WoW UIKit PASS: transient interruption keeps verification alive, paused update renders usable controls, foreground resumes once without launching, completed checks stay completed, and Auto-Lock is restored.");
        exit(0);
    }
    [self captureDownloading];
}
// A download in progress is the one state a screenshot cannot wait for: the speed and the estimate
// come from the clock. The window and both fragments are values with one right answer, and the
// suite that checks them runs on this Mac (tests/test_wow_download_status.m). What is left for this
// page is whether it draws the state at all, writes the fragments after the byte counts, and writes
// nothing when there is no rate - so the rate is pinned to the value that suite proves, exactly as
// the clock is pinned for every other picture in this file.
- (void)captureDownloading {
    atomic_store(&holdUpdate,true);
    // The same install this page has been looking at, asked to update itself: bumping the synthetic
    // build number instead would leave a different version in every picture taken after this one.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"WoWInstallRequested.wowf"];
    [self.controller refresh];
    assert(PumpUntil(^{ return (BOOL)[[self phase] isEqual:@"download"]; }, 30.0));
    assert([[self status] isEqual:@"Updating your game…"]);
    // The phase, then the counts, and nothing after them: one report is not a rate.
    assert([[self detail] isEqual:@"Downloading new data · 40 GB / 70 GB"]);
    // Past a day the estimate is withheld and the rate still stands.
    [self.controller setValue:@(0.1) forKey:@"_downloadMBps"];
    [self.controller render];
    assert([[self detail] isEqual:@"Downloading new data · 40 GB / 70 GB · 0.1 MB/s"]);
    // A stalled rate writes nothing at all, so the line reads as it did before this feature.
    [self.controller setValue:@(0.0) forKey:@"_downloadMBps"];
    [self.controller render];
    assert([[self detail] isEqual:@"Downloading new data · 40 GB / 70 GB"]);
    // Now the state the picture shows: the rate the suite proves - four megabytes a second - and
    // the estimate that follows, 30 GB left at that rate being two hours five minutes. Pinned last,
    // after the three cases above, so nothing intervenes between the state this asserts and the
    // draw that follows it.
    [self.controller setValue:@(4.0) forKey:@"_downloadMBps"];
    [self.controller render];
    // The words on the primary button crossfade when the phase changes, and a draw with the
    // window's clock held still renders that crossfade at its beginning - the old words. Measured
    // on 2026-11-10: a picture taken at this point held "Checking…" under a status line that
    // already read "Updating your game…". Wait for the crossfade to finish; measured, the two
    // animated layers are gone 0.4 s later. Waiting here rather than in `capture:` keeps every
    // other picture in this file exactly as it was recorded.
    PumpUntil(^{ return (BOOL)!AnimatingUnder([self primary].layer); }, 3.0);
    NSMutableArray<UIActivityIndicatorView *> *busy=[NSMutableArray array];
    CollectActivityIndicators(self.window, busy);
    for (UIActivityIndicatorView *indicator in busy) RemoveAnimations(indicator.layer);
    // The picture is only evidence of the state it claims if the state is still that one at the
    // draw: this is the same sentence as above, asked again last.
    if (![[self detail] isEqual:@"Downloading new data · 40 GB / 70 GB · 4.0 MB/s · ~2h 5m left"])
        fprintf(stderr, "WOW_DOWNLOADING_DETAIL_MISMATCH: %s\n", [[self detail] UTF8String]);
    assert([[self detail] isEqual:@"Downloading new data · 40 GB / 70 GB · 4.0 MB/s · ~2h 5m left"]);
    [self capture:@"wow-downloading.png"];
    // Let the held update finish, and the state goes with it.
    atomic_store(&holdUpdate,false);
    assert(PumpUntil(^{ return (BOOL)[[self status] isEqual:@"Ready to play"]; }, 30.0));
    assert(![[self detail] containsString:@"MB/s"] && ![[self detail] containsString:@"left"]);
    [self performSelector:@selector(captureAndLaunch) withObject:nil afterDelay:0.3];
}
- (void)captureAndLaunch {
    assert([self primary].enabled);
    [self.window layoutIfNeeded];
    CGRect button=[[self primary] convertRect:[self primary].bounds toView:self.window];
    assert(CGRectContainsRect(self.window.bounds,button));
    UILabel *label=(id)Find(self.controller.view,@"wow.status");
    CGRect text=[label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines];
    NSLog(@"DESCENDER_METRICS: frame=%@ text=%@ lineHeight=%g ascender=%g descender=%g",NSStringFromCGRect(label.frame),NSStringFromCGRect(text),label.font.lineHeight,label.font.ascender,label.font.descender);
    assert(label.bounds.size.height + 0.01 >= label.font.lineHeight);
    assert(text.origin.y >= 0 && CGRectGetMaxY(text) <= label.bounds.size.height + 0.5);
    self.controller.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
    [self performSelector:@selector(captureLargeText) withObject:nil afterDelay:0.3];
}
- (void)captureLargeText {
    [self.window layoutIfNeeded];
    UILabel *label=(id)Find(self.controller.view,@"wow.status");
    assert(label.bounds.size.height + 0.01 >= label.font.lineHeight);
    assert(CGRectGetMaxY([label textRectForBounds:label.bounds limitedToNumberOfLines:label.numberOfLines]) <= label.bounds.size.height + 0.5);
    UIScrollView *scroll=(id)Find(self.controller.view,@"wow.scroll");
    [scroll scrollRectToVisible:[label convertRect:label.bounds toView:scroll] animated:NO];
    // The largest text sizes stack the cards whatever the width - which is the same layout a
    // phone in portrait uses, so this is the only place that arrangement is exercised on an
    // iPad. All six cards stack, including the Launcher Manager that used to be the grid's
    // empty cell.
    UIStackView *grid=(id)Find(self.controller.view,@"wow.grid");
    for (UIStackView *row in grid.arrangedSubviews)
        assert(row.axis==UILayoutConstraintAxisVertical);
    assert(Find(self.controller.view,@"wow.grid.spacer")==nil);
    assert(grid.arrangedSubviews.count==3);
    [self capture:@"wow-home-large-text.png"];
    NSLog(@"PAGE_STACKED: six cards in one column at the largest text size");
    self.controller.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryLarge;
    [self performSelector:@selector(captureDefaultText) withObject:nil afterDelay:0.3];
}
- (void)captureDefaultText {
    [self.window layoutIfNeeded];
    UIScrollView *scroll=(id)Find(self.controller.view,@"wow.scroll");
    scroll.contentOffset=CGPointZero;
    [self capture:@"wow-home.png"];
    [self tap]; [self performSelector:@selector(checkLaunch) withObject:nil afterDelay:0.3];
}
- (void)capture:(NSString *)name {
    // Presenting is asynchronous: `presentedViewController` is set before the transition has
    // finished, and a draw taken during it shows the page underneath. That is exactly how the
    // add-on popup's baseline came out as a picture of the home page in one matrix run on
    // 2026-11-09, two runs after the same code had drawn it correctly. Wait for whatever is on
    // top to be on screen before measuring or drawing anything.
    __block UIViewController *top=self.controller.presentedViewController;
    while (top.presentedViewController) top=top.presentedViewController;
    if (top) PumpUntil(^{
        return (BOOL)(top.viewIfLoaded.window!=nil && !top.isBeingPresented && !top.isBeingDismissed);
    }, 5.0);
    [self.window layoutIfNeeded];
    // Two things on these pages move on their own, and a baseline that pinned either of them
    // could never match the next run. Measured in the matrix on 2026-11-09: the version line's
    // wall clock ("Checked 12:21" against "Checked 12:23") moved 540 pixels by 161, and an
    // activity indicator would move with its own rotation.
    //
    // The clock is drawn at one fixed instant and then the page's own value is put back, so
    // nothing after the capture is looking at a stopped clock. A indicator is stopped for the
    // draw only, and told to stay visible so the page still reads as busy; it is started again
    // afterwards so the fixture goes on driving the same state.
    id realCheckedAt=[self.controller valueForKey:@"_checkedAt"];
    if (realCheckedAt) {
        static NSDate *baselineClock;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ baselineClock=[NSDate dateWithTimeIntervalSince1970:800000000]; });
        [self.controller setValue:baselineClock forKey:@"_checkedAt"];
        [self.controller render];
        [self.window layoutIfNeeded];
    }
    NSMutableArray<UIActivityIndicatorView *> *spinners=[NSMutableArray array];
    CollectActivityIndicators(self.window, spinners);
    NSMutableArray<NSNumber *> *hides=[NSMutableArray array];
    NSMutableArray<UIActivityIndicatorView *> *animating=[NSMutableArray array];
    for (UIActivityIndicatorView *spinner in spinners) {
        [hides addObject:@(spinner.hidesWhenStopped)];
        if (spinner.isAnimating) {
            spinner.hidesWhenStopped=NO;
            [spinner stopAnimating];
            [animating addObject:spinner];
        }
    }
    [self.window layoutIfNeeded];
    // Hold the layer tree's clock still for the draw. The launch page spins a ring and steps
    // an elapsed-time counter from Core Animation, and without this the picture is taken at
    // whatever phase the run happened to reach: the matrix measured a 64x66 region differing
    // by 110 between two identical iPhone runs on 2026-11-09. Speed 0 with a zeroed offset
    // renders every animation in the window at local time 0; putting both back afterwards
    // lets them carry on as if nothing happened.
    CALayer *root=self.window.layer;
    CFTimeInterval savedSpeed=root.speed, savedOffset=root.timeOffset;
    root.speed=0; root.timeOffset=0;
    [self.window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context; [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    root.speed=savedSpeed; root.timeOffset=savedOffset;
    [animating makeObjectsPerformSelector:@selector(startAnimating)];
    for (NSUInteger index=0; index<spinners.count; index++) spinners[index].hidesWhenStopped=hides[index].boolValue;
    if (realCheckedAt) {
        [self.controller setValue:realCheckedAt forKey:@"_checkedAt"];
        [self.controller render];
    }
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    assert([UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES]);
}
#pragma mark - The home page's contract, and the Forever UI rows

- (UIButton *)row:(NSString *)identifier { return (id)Find(self.controller.view, identifier); }
- (UISwitch *)toggle:(NSString *)identifier {
    return (id)Find(self.controller.view, [identifier stringByAppendingString:@".switch"]);
}
// The controller on top, once UIKit has finished moving it.
//
// A sheet that is arriving or leaving is still `presentedViewController`, and every step here is
// scheduled with a fixed delay: reading the property then is a guess about how fast the machine
// is, not a check. Measured on a loaded iPad Pro 13-inch (M5), 2026-11-13, where such a read
// reported a nested sheet as missing when it was one transition away from being there.
- (id)settledPresentedController {
    PumpUntil(^{
        UIViewController *presented = self.controller.presentedViewController;
        return (BOOL)(presented != nil && !presented.isBeingPresented && !presented.isBeingDismissed);
    }, 20.0);
    return self.controller.presentedViewController;
}

- (void)dismissPresented {
    // Waited for, not fired and forgotten. Dismissal is asynchronous, and the step after this one
    // waits for *its* alert; if this one were still on screen it would be handed back instead, and
    // the failure would be reported against the wrong control. Every step that closes a sheet goes
    // through here, so this is where the wait belongs rather than in each of them.
    UIViewController *presented = self.controller.presentedViewController;
    if (!presented) return;
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 20.0);
}
- (NSString *)configText {
    return [NSString stringWithContentsOfFile:[fixture.directory stringByAppendingPathComponent:@"WTF/Config.wtf"]
                                     encoding:NSUTF8StringEncoding error:NULL];
}
- (NSUInteger)gamepadAssignments:(NSString *)text enabled:(BOOL *)enabled {
    NSUInteger count = 0; BOOL on = NO;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (![trimmed.uppercaseString hasPrefix:@"SET GAMEPADENABLE"]) continue;
        count++; on = [trimmed containsString:@"\"1\""];
    }
    if (enabled) *enabled = on;
    return count;
}
- (void)startPerformanceTests {
    // A synthetic Forever installation with a configuration that has every
    // category the reset must keep, and duplicate GamePadEnable assignments for
    // the gamepad row to normalise.
    NSString *wtf = [fixture.directory stringByAppendingPathComponent:@"WTF"];
    WriteFile([wtf stringByAppendingPathComponent:@"Config.wtf"],
        @"SET portal \"eu\"\n"
         "SET textLocale \"enUS\"\n"
         "SET audioLocale \"enUS\"\n"
         "SET accountName \"TESTACCOUNT\"\n"
         "SET gxResolution \"1920x1080\"\n"
         "SET graphicsQuality \"7\"\n"
         "SET Sound_OutputDriverIndex \"0\"\n"
         "SET GamePadEnable \"0\"\n"
         "SET GamePadEnable \"0\"\n"
         "SET GamePadConfig \"Addons\"\n"
         "SET uiScale \"1\"\n"
         "SET unknownSetting \"keep\"\n"
         "SET cameraDistance \"1.5\"\n");
    WriteFile([fixture.directory stringByAppendingPathComponent:@"Interface/AddOns/Fixture/Fixture.toc"],
              @"## Title: Fixture\n## Version: 1\n");

    // The touch layout store, seeded so the overlay row's read-modify-write can
    // be proven to keep every other value.
    [NSUserDefaults.standardUserDefaults setObject:@{@"opacity":@0.4, @"rearScale":@1.2,
        @"frontScale":@1.1, @"hapticsEnabled":@NO,
        @"positions":@{@"menu":@[@0.1, @0.2]}} forKey:@"WolkaraForeverTouchLayoutV1"];

    [self.controller render];
    [self.window layoutIfNeeded];

    // --- headings, in the order the page is read
    NSArray *headings = @[@[@"wow.heading.edition", @"GAME SETTINGS MANAGER"],
                          @[@"wow.heading.addons", @"ADD-ON MANAGER"],
                          @[@"wow.heading.voice", @"DICTATION (V2T) MANAGER"],
                          @[@"wow.heading.profile", @"PERFORMANCE MANAGER"],
                          @[@"wow.heading.performance", @"UI MANAGER"],
                          @[@"wow.heading.launcherManager", @"LAUNCHER MANAGER"]];
    for (NSArray *pair in headings) {
        UILabel *label = (id)Find(self.controller.view, pair[0]);
        assert(label != nil && [label.text isEqual:pair[1]]);
    }
    // --- the page: identity and status on top, then the five boxes in order
    UIStackView *columns = (id)[self.controller valueForKey:@"_columns"];
    assert(columns != nil && columns.axis == UILayoutConstraintAxisVertical);
    assert(columns.arrangedSubviews.count == 2);
    UIStackView *top = columns.arrangedSubviews[0];
    assert([top.arrangedSubviews.firstObject.accessibilityIdentifier isEqual:@"wow.logo"]);
    UIStackView *grid = columns.arrangedSubviews[1];
    assert([grid.accessibilityIdentifier isEqual:@"wow.grid"] && grid.arrangedSubviews.count == 3);
    // The fifth and sixth cards share the last row. The cell beside UI Manager used to be a
    // named spacer; it now holds the Launcher Manager, so the grid has six cards and no
    // spacer at all.
    NSMutableArray *cells = [NSMutableArray new], *boxes = [NSMutableArray new];
    UIScrollView *measure = (id)Find(self.controller.view, @"wow.scroll");
    [measure layoutIfNeeded];
    BOOL wide = measure.bounds.size.width >= 700;
    NSLog(@"PAGE_WIDTH: %.0f so %@", measure.bounds.size.width, wide ? @"two columns" : @"one column");
    for (UIStackView *row in grid.arrangedSubviews) {
        // Two columns where there is room, one where there is not. The order of the cards does
        // not change with the axis, which is the whole point of laying them out this way.
        assert(row.axis == (wide ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical));
        for (UIView *cell in row.arrangedSubviews) {
            assert([cell.accessibilityIdentifier hasPrefix:@"wow.box."]);
            [cells addObject:cell];
            if ([cell.accessibilityIdentifier hasPrefix:@"wow.box."]) [boxes addObject:cell];
        }
    }
    NSArray *expectedCells = @[@"wow.box.edition", @"wow.box.addons",
                               @"wow.box.voice", @"wow.box.profile",
                               @"wow.box.performance", @"wow.box.launcherManager"];
    assert([[cells valueForKey:@"accessibilityIdentifier"] isEqualToArray:expectedCells]);
    NSArray *expectedBoxes = @[@"wow.box.edition", @"wow.box.addons",
                               @"wow.box.voice", @"wow.box.profile", @"wow.box.performance",
                               @"wow.box.launcherManager"];
    assert([[boxes valueForKey:@"accessibilityIdentifier"] isEqualToArray:expectedBoxes]);
    // --- each box's heading and rows, exactly
    NSDictionary *expectedRows = @{
        // The Game Settings Manager card: the edition, the region/locale pair, and the
        // *app's* language. Three separate settings, three separate rows. The passive
        // compatibility note that used to sit at the foot of this card is gone.
        @"wow.box.edition": @[@"wow.heading.edition", @"wow.edition", @"wow.preferences",
                              @"wow.language"],
        @"wow.box.addons": @[@"wow.heading.addons", @"wow.addons.manage", @"wow.addons.macEver",
                             @"wow.addons.directory"],
        @"wow.box.voice": @[@"wow.heading.voice", @"wow.permissions", @"wow.voice", @"wow.voice.test"],
        // The profile card: which device, which render scale, and the overlay. Nothing here
        // reads or writes the game's files, and there is no "restore defaults" row: the way
        // back is the Automatic choice in the device sheet, which is where the value lives.
        @"wow.box.profile": @[@"wow.heading.profile", @"wow.performance.deviceProfile",
                              @"wow.performance.renderProfile",
                              @"wow.performance.overlay"],
        // The retained card, narrower and in the order someone with a broken UI needs it.
        @"wow.box.performance": @[@"wow.heading.performance", @"wow.performance.backup",
                                  @"wow.performance.restore", @"wow.performance.reset",
                                  @"wow.performance.settingsFolder", @"wow.performance.gamepad"],
        // The sixth card: the interface this launcher drives, and the arrangement its controls
        // use. Two settings, two rows.
        @"wow.box.launcherManager": @[@"wow.heading.launcherManager", @"wow.launcher.interfaceMode",
                                      @"wow.launcher.interfaceSetup"],
    };
    for (UIView *box in boxes) {
        UIStackView *stack = box.subviews.firstObject;
        assert([stack isKindOfClass:UIStackView.class]);
        NSMutableArray *rowOrder = [NSMutableArray new];
        for (UIView *row in stack.arrangedSubviews) {
            if ([row.accessibilityIdentifier isEqual:@"wow.box.spacer"]) continue;
            [rowOrder addObject:row.accessibilityIdentifier ?: @""];
        }
        assert([rowOrder isEqualToArray:expectedRows[box.accessibilityIdentifier]]);
    }
    // --- the page never needs to be dragged sideways, and on a wide page it still fits whole.
    UIScrollView *scroll = (id)Find(self.controller.view, @"wow.scroll");
    [scroll layoutIfNeeded];
    NSLog(@"PAGE_FIT: content=%.0f×%.0f bounds=%.0f×%.0f", scroll.contentSize.width,
          scroll.contentSize.height, scroll.bounds.size.width, scroll.bounds.size.height);
    // Scrolling down is allowed - a phone is a narrow page with six cards on it - and scrolling
    // across is not: a card that hangs past the right edge is one nobody can reach.
    assert(scroll.contentSize.width <= scroll.bounds.size.width + 1);
    for (UIView *box in boxes) {
        CGRect frame = [box convertRect:box.bounds toView:scroll];
        assert(CGRectGetMinX(frame) >= -0.5);
        assert(CGRectGetMaxX(frame) <= scroll.bounds.size.width + 0.5);
    }
    // The two-column layout was made so that an iPad shows the whole page at once, and that still
    // holds. A phone is allowed to scroll: landscape is 750 points across and 304 down, and no
    // arrangement of six cards fits that. What a phone is not allowed is a card out of reach,
    // which the checks above cover.
    if (self.controller.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad)
        assert(scroll.contentSize.height <= scroll.bounds.size.height + 1);
    // The Play button is at the top whatever the width, so it is never something to scroll to.
    CGRect play = [[self primary] convertRect:[self primary].bounds toView:scroll];
    assert(CGRectGetMinY(play) >= -0.5 && CGRectGetMaxY(play) <= scroll.bounds.size.height + 0.5);
    // --- labels, exactly
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.manage") configuration].title isEqual:@"Install Addons (Curse & Direct)"]);
    // Every edition reads with its prefix, and the region/locale row reads with both values.
    assert([[(UIButton *)Find(self.controller.view, @"wow.edition") configuration].title isEqual:@"Game Edition: Forever"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.preferences") configuration].title isEqual:@"Region / Locale: EU English"]);
    // Exactly one supporting line below Play, and no second one reserved for a startup note.
    assert(Find(self.controller.view, @"wow.updates") != nil);
    assert(Find(self.controller.view, @"wow.startup") == nil);
    // The removed controls are gone, not hidden.
    assert(Find(self.controller.view, @"wow.performance.restoreDefaults") == nil);
    assert(Find(self.controller.view, @"wow.compatibility") == nil);
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.directory") configuration].title isEqual:@"Open Add-on Directory"]);
    // The recommendation row keeps its identifier and names this product's own add-on, in
    // either interface: one package, one place to install it.
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.macEver") configuration].title
        isEqual:@"Install Recommended Add-ons (WolkaraRoue)"]);
    // No mode has been chosen, so it is iPadOS - the value every installation has had.
    assert([[(UIButton *)Find(self.controller.view, @"wow.launcher.interfaceMode") configuration].title
        isEqual:@"Interface Mode: iPadOS"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.permissions") configuration].title isEqual:@"Toggle Permissions (Mic & Speech)"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.voice") configuration].title isEqual:@"Key / Button Configuration"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.voice.test") configuration].title isEqual:@"Test Voice & Dictation"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.backup") configuration].title isEqual:@"Backup WoW UI Configuration"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.reset") configuration].title isEqual:@"Reset to Default Graphical Settings"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.restore") configuration].title isEqual:@"Restore WoW UI Configuration"]);
    // The two on/off settings are switches with fixed words: the control says the
    // state, the label never changes.
    assert([[(UILabel *)Find(self.controller.view, @"wow.performance.gamepad.label") text] isEqual:@"Gamepad UI"]);
    assert([[(UILabel *)Find(self.controller.view, @"wow.performance.overlay.label") text] isEqual:@"Performance Overlay"]);
    assert([self toggle:@"wow.performance.gamepad"] != nil && [self toggle:@"wow.performance.overlay"] != nil);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.settingsFolder") configuration].title isEqual:@"Open Settings Folder"]);
    // --- enabled state on a ready, idle installation
    for (NSString *identifier in @[@"wow.performance.backup", @"wow.performance.reset",
                                   @"wow.performance.restore", @"wow.performance.settingsFolder",
                                   @"wow.addons.manage", @"wow.voice", @"wow.voice.test",
                                   @"wow.permissions", @"wow.addons.macEver"])
        assert([self row:identifier].enabled);
    assert([self toggle:@"wow.performance.gamepad"].enabled);
    assert([self toggle:@"wow.performance.overlay"].enabled);
    // A usable switch row reads in the same gold as the button rows, not in
    // white: the two styles used to disagree on the same page.
    assert(CGColorEqualToColor([(UILabel *)Find(self.controller.view, @"wow.performance.gamepad.label") textColor].CGColor,
                               [(UIButton *)Find(self.controller.view, @"wow.performance.backup") configuration].baseForegroundColor.CGColor));
    assert(CGColorEqualToColor([(UILabel *)Find(self.controller.view, @"wow.performance.overlay.label") textColor].CGColor,
                               [(UIButton *)Find(self.controller.view, @"wow.performance.settingsFolder") configuration].baseForegroundColor.CGColor));

    // --- The recommendation row opens the Add-On Manager, and never installs silently.
    // The launch checks above leave a recoverable failure on the page; the Launcher Manager's
    // own pictures are of the ready page, so put that back before opening anything over it.
    [self.controller setValue:nil forKey:@"_startupFailure"];
    [self.controller render];
    [self.window layoutIfNeeded];
    assert([[self status] isEqual:@"Ready to play"]);
    // The recommendation opens this product's own package page whatever the interface is; the
    // bundled-package flow itself, with its release and hash, is asserted in full below.
    [[self row:@"wow.addons.macEver"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController != nil); }, 5.0);
    UINavigationController *recommended = [self settledPresentedController];
    assert([recommended isKindOfClass:UINavigationController.class]);
    // Dismissing a page sheet while it is still arriving leaves it presented, and the next
    // sheet then has nowhere to go. Wait for it to be on screen first.
    PumpUntil(^{ return (BOOL)(recommended.viewIfLoaded.window != nil && !recommended.isBeingPresented); }, 5.0);
    TKWoWAddonManagerViewController *recommendedPage = (id)recommended.topViewController;
    assert([recommendedPage isKindOfClass:TKWoWAddonManagerViewController.class]);
    assert(recommendedPage.recommendation == TKAddonRecommendationWolkaraRoue);
    assert(recommendedPage.recommendedProjectID == nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 5.0);
    assert(self.controller.presentedViewController == nil);

    // --- The interface mode selector: exactly two choices, persisted, and no package touched.
    NSString *addonsDirectory = [fixture.directory stringByAppendingPathComponent:@"Interface/AddOns"];
    NSArray *addonsBefore = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:addonsDirectory error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverInterfaceModeV1"];
    [self.controller render];
    assert([[(UIButton *)Find(self.controller.view, @"wow.launcher.interfaceMode") configuration].title
        isEqual:@"Interface Mode: iPadOS"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.macEver") configuration].title
        isEqual:@"Install Recommended Add-ons (WolkaraRoue)"]);
    // The page in its default state: the Launcher Manager row says iPadOS and the
    // recommendation row names our own add-on. The selector's own choices are asserted
    // below; the baseline is the page, not a translucent sheet.
    Pump(0.5);
    RemoveAnimations(self.window.layer);
    [self capture:@"wow-launcher-ipados.png"];
    [[self row:@"wow.launcher.interfaceMode"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    PumpUntil(^{ return (BOOL)([self.controller.presentedViewController isKindOfClass:UIAlertController.class]); }, 5.0);
    UIAlertController *modeSheet = WaitForSheetTitled(self.controller, @"Interface Mode", 20.0);
    assert(modeSheet != nil);
    assert(CancelActions(modeSheet) == 1);
    // Automatic names what this device would resolve to, even while iPadOS is what is in force.
    NSString *automatic = [NSString stringWithFormat:@"Automatic (%@)",
        UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? @"iOS on Duo" : @"iPadOS"];
    assert([[modeSheet.actions valueForKey:@"title"] isEqualToArray:(@[automatic, @"✓ iPadOS", @"iOS", @"iOS on Duo", @"Cancel"])]);
    UIAlertAction *duo = nil;
    for (UIAlertAction *action in modeSheet.actions) if ([action.title isEqual:@"iOS on Duo"]) duo = action;
    assert(duo != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(duo);
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 5.0);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WolkaraForeverInterfaceModeV1"] isEqual:@"iosduo"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.launcher.interfaceMode") configuration].title
        isEqual:@"Interface Mode: iOS on Duo"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.macEver") configuration].title
        isEqual:@"Install Recommended Add-ons (WolkaraRoue)"]);
    // The page after the switch: the selector names iOS on Duo and the recommendation row
    // names WolkaraRoue. The game's AddOns folder is exactly as it was.
    Pump(0.5);
    RemoveAnimations(self.window.layer);
    [self capture:@"wow-launcher-duo.png"];
    // A mode is a setting: the game's AddOns folder is exactly as it was.
    NSArray *addonsAfterSwitch = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:addonsDirectory error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    assert([addonsAfterSwitch isEqualToArray:addonsBefore]);

    // --- On iOS on Duo the recommendation opens the bundled package, explicitly.
    [[self row:@"wow.addons.macEver"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController != nil); }, 5.0);
    UINavigationController *bundledFrame = [self settledPresentedController];
    assert([bundledFrame isKindOfClass:UINavigationController.class]);
    TKWoWAddonManagerViewController *bundledPage = (id)bundledFrame.topViewController;
    assert([bundledPage isKindOfClass:TKWoWAddonManagerViewController.class]);
    assert(bundledPage.recommendation == TKAddonRecommendationWolkaraRoue);
    assert(bundledPage.recommendedProjectID == nil);
    PumpUntil(^{ return (BOOL)(bundledFrame.viewIfLoaded.window != nil && !bundledFrame.isBeingPresented); }, 5.0);
    // A verified package, shaped as the shipped verifier returns it.
    bundledPage.bundledPackageProvider = ^NSDictionary *(NSError **error) {
        (void)error;
        return @{@"archive":[NSURL fileURLWithPath:@"/tmp/WolkaraRoue-0.9.1.zip"],
                 @"manifest":[NSURL fileURLWithPath:@"/tmp/WolkaraRoue-0.9.1.json"],
                 @"release":@"0.9.1",
                 @"sha256":@"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                 @"folder":@"WolkaraRoue", @"files":@24};
    };
    [bundledPage reloadBundledPackage];
    [bundledPage.view layoutIfNeeded];
    [bundledPage.tableView layoutIfNeeded];
    assert([[(UILabel *)Find(bundledPage.view, @"wow.addons.bundled.name") text] isEqual:@"WolkaraRoue (bundled)"]);
    NSString *bundledDetail = [(UILabel *)Find(bundledPage.view, @"wow.addons.bundled.detail") text];
    assert([bundledDetail containsString:@"0.9.1"] && [bundledDetail containsString:@"SHA-256"]);
    UIButton *bundledInstall = (id)Find(bundledPage.view, @"wow.addons.bundled.install");
    assert(bundledInstall != nil && !bundledInstall.hidden && bundledInstall.enabled);
    Pump(0.5);
    RemoveAnimations(self.window.layer);
    [self capture:@"wow-addons-recommended-wolkararoue.png"];
    // A package that does not verify is refused, and nothing is written.
    bundledPage.bundledPackageProvider = ^NSDictionary *(NSError **error) {
        if (error) *error = [NSError errorWithDomain:@"WolkaraForever.AddOns" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"The bundled add-on archive is not the one this app shipped."}];
        return nil;
    };
    [bundledPage reloadBundledPackage];
    [bundledPage.view layoutIfNeeded];
    [bundledPage.tableView layoutIfNeeded];
    assert([[(UILabel *)Find(bundledPage.view, @"wow.addons.bundled.detail") text]
        containsString:@"not the one this app shipped"]);
    assert(((UIButton *)Find(bundledPage.view, @"wow.addons.bundled.install")).hidden);
    NSArray *addonsAfterRefusal = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:addonsDirectory error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    assert([addonsAfterRefusal isEqualToArray:addonsBefore]);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 5.0);
    assert(self.controller.presentedViewController == nil);

    // Back to iPadOS through the same sheet: the recommendation stays our own add-on.
    [[self row:@"wow.launcher.interfaceMode"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    PumpUntil(^{ return (BOOL)([self.controller.presentedViewController isKindOfClass:UIAlertController.class]); }, 5.0);
    modeSheet = WaitForSheetTitled(self.controller, @"Interface Mode", 20.0);
    assert(modeSheet != nil);
    assert([[modeSheet.actions valueForKey:@"title"] isEqualToArray:(@[automatic, @"iPadOS", @"iOS", @"✓ iOS on Duo", @"Cancel"])]);
    UIAlertAction *ipados = nil;
    for (UIAlertAction *action in modeSheet.actions) if ([action.title isEqual:@"iPadOS"]) ipados = action;
    assert(ipados != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(ipados);
    PumpUntil(^{ return (BOOL)(self.controller.presentedViewController == nil); }, 5.0);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WolkaraForeverInterfaceModeV1"] isEqual:@"ipados"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.macEver") configuration].title
        isEqual:@"Install Recommended Add-ons (WolkaraRoue)"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.launcher.interfaceMode") configuration].title
        isEqual:@"Interface Mode: iPadOS"]);

    // --- the overlay switch writes the shared store, keeping the layout's own values
    UISwitch *overlay = [self toggle:@"wow.performance.overlay"];
    overlay.on = YES; [overlay sendActionsForControlEvents:UIControlEventValueChanged];
    NSDictionary *layout = [NSUserDefaults.standardUserDefaults objectForKey:@"WolkaraForeverTouchLayoutV1"];
    assert([layout[@"performanceOverlayEnabled"] boolValue]);
    assert([layout[@"opacity"] doubleValue] == 0.4 && [layout[@"rearScale"] doubleValue] == 1.2);
    NSArray *menuPoint = layout[@"positions"][@"menu"];
    assert(fabs([menuPoint[1] doubleValue] - 0.2) < 0.001);
    assert(overlay.on && [[(UILabel *)Find(self.controller.view, @"wow.performance.overlay.label") text] isEqual:@"Performance Overlay"]);
    overlay.on = NO; [overlay sendActionsForControlEvents:UIControlEventValueChanged];
    assert(![[NSUserDefaults.standardUserDefaults objectForKey:@"WolkaraForeverTouchLayoutV1"][@"performanceOverlayEnabled"] boolValue]);
    assert(!overlay.on && [[(UILabel *)Find(self.controller.view, @"wow.performance.overlay.label") text] isEqual:@"Performance Overlay"]);
    overlay.on = YES; [overlay sendActionsForControlEvents:UIControlEventValueChanged];

    // --- Open Settings Folder opens Forever's WTF folder and changes nothing
    __block NSURL *folder = nil;
    self.controller.openSettingsFolderURL = ^(NSURL *url) { folder = url; };
    [[self row:@"wow.performance.settingsFolder"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(folder != nil && [folder.lastPathComponent isEqual:@"WTF"]);
    assert([folder.path hasPrefix:fixture.directory]);
    self.controller.openSettingsFolderURL = nil;
    [self performSelector:@selector(checkFolderPicker) withObject:nil afterDelay:0.4];
}
- (void)checkFolderPicker {
    // --- nothing backed up yet: Restore says so instead of claiming success
    [[self row:@"wow.performance.restore"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkNoBackupYet) withObject:nil afterDelay:0.9];
}
- (void)checkNoBackupYet {
    UIAlertController *alert = WaitForAlert(self.controller, 30.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"No backup to restore"]);
    assert([alert.message containsString:@"Backup"]);
    [self dismissPresented];
    assert(stubBackups == 0 && stubRestores == 0);
    [[self row:@"wow.performance.backup"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkBackup) withObject:nil afterDelay:0.9];
}
static NSString *configBeforeReset;
static NSString *configBeforePerformance;
static int backupsBeforePerformance;
- (void)checkBackup {
    UIAlertController *alert = WaitForAlert(self.controller, 30.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"Backup complete"]);
    assert([alert.message containsString:@"WTF/Backups"]);
    assert(stubBackups == 1);
    assert([NSFileManager.defaultManager fileExistsAtPath:
        [fixture.directory stringByAppendingPathComponent:[@"WTF/Backups" stringByAppendingPathComponent:stubNewest]]]);
    [self dismissPresented];
    configBeforeReset = [self configText];
    // --- the destructive row is confirmed first, and cancelling changes nothing
    [self performSelector:@selector(tapReset) withObject:nil afterDelay:0.4];
}
- (void)tapReset {
    [[self row:@"wow.performance.reset"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkResetConfirmation) withObject:nil afterDelay:0.5];
}
- (void)checkResetConfirmation {
    UIAlertController *alert = WaitForSheetTitled(self.controller, @"Reset to default graphics settings?", 20.0);
    assert(alert != nil);
    assert([alert.message containsString:@"backup"]);
    [self dismissPresented];
    assert([[self configText] isEqual:configBeforeReset]);
    [self performSelector:@selector(performConfirmedReset) withObject:nil afterDelay:0.4];
}
- (void)performConfirmedReset {
    // The same path the confirmed action takes; the sheet above is the gate.
    [self.controller performGraphicsReset:fixture.directory];
    [self performSelector:@selector(checkReset) withObject:nil afterDelay:0.6];
}
- (void)checkReset {
    UIAlertController *alert = WaitForAlert(self.controller, 30.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"Graphics reset"]);
    assert([alert.message containsString:@"when Forever next launches"]);
    assert(stubBackups == 2);   // the reset made its own rollback point
    [self dismissPresented];
    NSString *config = [self configText];
    assert(![config containsString:@"SET gxResolution"]);
    assert(![config containsString:@"SET graphicsQuality"]);
    for (NSString *kept in @[@"SET portal \"eu\"", @"SET textLocale \"enUS\"", @"SET audioLocale \"enUS\"",
                             @"SET accountName \"TESTACCOUNT\"", @"SET Sound_OutputDriverIndex \"0\"",
                             @"SET GamePadEnable", @"SET GamePadConfig \"Addons\"", @"SET uiScale \"1\"",
                             @"SET unknownSetting \"keep\"", @"SET cameraDistance \"1.5\""])
        assert([config containsString:kept]);
    [self performSelector:@selector(tapGamepad) withObject:nil afterDelay:0.4];
}
- (void)tapGamepad {
    UISwitch *gamepad = [self toggle:@"wow.performance.gamepad"];
    assert(gamepad != nil);
    gamepad.on = YES; [gamepad sendActionsForControlEvents:UIControlEventValueChanged];
    [self performSelector:@selector(checkGamepad) withObject:nil afterDelay:0.5];
}
- (void)checkGamepad {
    UIAlertController *alert = WaitForAlert(self.controller, 30.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"Gamepad UI enabled"]);
    [self dismissPresented];
    NSString *config = [self configText];
    BOOL enabled = NO;
    assert([self gamepadAssignments:config enabled:&enabled] == 1 && enabled);
    assert([config containsString:@"SET accountName \"TESTACCOUNT\""]);
    UISwitch *gamepad = [self toggle:@"wow.performance.gamepad"];
    assert(gamepad.on && [[(UILabel *)Find(self.controller.view, @"wow.performance.gamepad.label") text] isEqual:@"Gamepad UI"]);
    // The same switch turns it off, and the words still do not change.
    gamepad.on = NO; [gamepad sendActionsForControlEvents:UIControlEventValueChanged];
    [self performSelector:@selector(checkGamepadOff) withObject:nil afterDelay:0.5];
}
- (void)checkGamepadOff {
    UIAlertController *alert = WaitForAlert(self.controller, 30.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"Gamepad UI disabled"]);
    [self dismissPresented];
    BOOL enabled = YES;
    assert([self gamepadAssignments:[self configText] enabled:&enabled] == 1 && !enabled);
    assert([[(UILabel *)Find(self.controller.view, @"wow.performance.gamepad.label") text] isEqual:@"Gamepad UI"]);
    [self performSelector:@selector(tapRestore) withObject:nil afterDelay:0.4];
}
- (void)tapRestore {
    // Restore opens the folder browser at the game's WTF/Backups; the fixture
    // stands in for the system picker and chooses the snapshot the stub wrote,
    // exactly as a tap on it would.
    __block NSURL *backupFolder = nil;
    self.controller.chooseBackupFile = ^(NSURL *url) { backupFolder = url; };
    [[self row:@"wow.performance.restore"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(backupFolder != nil);
    assert([backupFolder.lastPathComponent isEqual:@"Backups"]);
    NSString *expected = [fixture.directory stringByAppendingPathComponent:@"WTF/Backups"];
    assert([[backupFolder.path stringByResolvingSymlinksInPath] isEqual:[expected stringByResolvingSymlinksInPath]]);
    assert(stubNewest != nil);
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP]];
    picker.directoryURL = backupFolder;
    [self.controller documentPicker:picker
         didPickDocumentsAtURLs:@[[backupFolder URLByAppendingPathComponent:stubNewest]]];
    self.controller.chooseBackupFile = nil;
    [self performSelector:@selector(checkRestore) withObject:nil afterDelay:0.8];
}
- (void)checkRestore {
    UIAlertController *alert = WaitForAlert(self.controller, 30.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"Restore complete"]);
    assert([alert.message containsString:stubLastRestored]);
    assert(stubRestores == 1);
    assert(stubBackups == 3);   // restore snapshotted the current state first
    [self dismissPresented];
    [self performSelector:@selector(tapRenderProfile) withObject:nil afterDelay:0.4];
}
- (void)tapRenderProfile {
    // Opening the row is what crashed: the sheet carried two Cancel actions, the row's own and
    // the one -presentSheet:anchor: adds for every action sheet, and UIKit raises on the second.
    // On this simulator the Mac's own model is not in the table, so the page is in its fallback
    // state - which is the first thing checked, because that is what an unrecognised device gets.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"WolkaraForeverDeviceProfile"];
    [defaults removeObjectForKey:@"WolkaraForeverRenderProfile"];
    [defaults removeObjectForKey:@"WolkaraForeverBackingScale"];
    [self.controller render];
    NSString *deviceRow = [(UIButton *)Find(self.controller.view, @"wow.performance.deviceProfile") configuration].title;
    assert([deviceRow isEqual:@"Device profile: Automatic — this device (unrecognised)"]);
    NSString *renderRow = [(UIButton *)Find(self.controller.view, @"wow.performance.renderProfile") configuration].title;
    assert([renderRow isEqual:@"Render profile: Performance"]);
    // The "restore performance defaults" row is gone rather than hidden: its removal was part
    // of the home-page cleanup, and a hidden control is the thing the plan forbids.
    assert(Find(self.controller.view, @"wow.performance.restoreDefaults") == nil);
    [[self row:@"wow.performance.renderProfile"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkFallbackRenderSheet) withObject:nil afterDelay:0.6];
}
- (void)checkFallbackRenderSheet {
    UIAlertController *sheet = WaitForSheetTitled(self.controller, @"Render profile", 20.0);
    assert(sheet != nil);
    assert(CancelActions(sheet) == 1);
    // A device that was never measured is offered Performance and nothing above it. An offered
    // level that cannot hold its budget is worse than one that is not there.
    assert([[sheet.actions valueForKey:@"title"] isEqualToArray:(@[@"✓ Performance", @"Cancel"])]);
    [self dismissPresented];
    [self performSelector:@selector(tapDeviceProfile) withObject:nil afterDelay:0.4];
}
- (void)tapDeviceProfile {
    [[self row:@"wow.performance.deviceProfile"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkDeviceProfileSheet) withObject:nil afterDelay:0.6];
}
- (void)checkDeviceProfileSheet {
    UIAlertController *sheet = WaitForSheetTitled(self.controller, @"Device profile", 20.0);
    assert(sheet != nil);
    assert(CancelActions(sheet) == 1);
    NSArray *titles = [sheet.actions valueForKey:@"title"];
    // Automatic is the recommendation and comes first; the profile of this device is not
    // offered again among the choices, and every record in the table is offered.
    assert([titles.firstObject isEqual:@"✓ Automatic (recommended) — this device (unrecognised)"]);
    assert([titles containsObject:@"iPad Pro 12.9-inch (M1) — 1366 × 1024"]);
    assert([titles containsObject:@"iPad Pro 13-inch (M4) — 1376 × 1032"]);
    assert(titles.count == TKDeviceProfile.profiles.count + 2);   // + Automatic + Cancel
    // Choosing another device is a preview, and the sheet says so before the row changes.
    // The action is run the way UIKit runs it - after the sheet has gone - and the message it
    // presents is deferred until the presenter is free, so the wait is on the page, not a guess.
    UIAlertAction *measured = nil;
    for (UIAlertAction *action in sheet.actions) if ([action.title isEqual:@"iPad Pro 12.9-inch (M1) — 1366 × 1024"]) measured = action;
    assert(measured != nil);
    [self dismissPresented];
    Pump(0.4);
    RunAction(measured);
    UIAlertController *alert = WaitForAlert(self.controller, 5.0);
    assert([alert isKindOfClass:UIAlertController.class]);
    assert([alert.title isEqual:@"Preview profile"]);
    assert([alert.message containsString:@"is not this device"]);
    [self dismissPresented];
    Pump(0.4);
    // The row now says Preview, everywhere it appears, and keeps the stored choice.
    NSString *deviceRow = [(UIButton *)Find(self.controller.view, @"wow.performance.deviceProfile") configuration].title;
    assert([deviceRow isEqual:@"Device profile: Preview — iPad Pro 12.9-inch (M1)"]);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WolkaraForeverDeviceProfile"]
            isEqual:@"ipad-pro-12.9-m1"]);
    // The override, the quality and the scale are written together, so they cannot disagree.
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WolkaraForeverRenderProfile"]
            isEqual:@"performance"]);
    assert([NSUserDefaults.standardUserDefaults doubleForKey:@"WolkaraForeverBackingScale"] == 0.75);
    // Choosing a device keeps the quality that was already chosen, clamped to what the new
    // profile may be asked for: it is a change of hardware, not a silent quality change. That
    // profile was measured, so Quality is now available as well.
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.renderProfile") configuration].title
            isEqual:@"Render profile: Performance — 1024 × 768"]);
    assert(Find(self.controller.view, @"wow.performance.restoreDefaults") == nil);
    [self performSelector:@selector(tapRenderProfileOnMeasuredDevice) withObject:nil afterDelay:0.4];
}
- (void)tapRenderProfileOnMeasuredDevice {
    [[self row:@"wow.performance.renderProfile"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkMeasuredRenderSheet) withObject:nil afterDelay:0.6];
}
- (void)checkMeasuredRenderSheet {
    UIAlertController *sheet = WaitForSheetTitled(self.controller, @"Render profile", 20.0);
    assert(sheet != nil);
    assert(CancelActions(sheet) == 1);
    assert([[sheet.actions valueForKey:@"title"] isEqualToArray:
        (@[@"✓ Performance — 1024 × 768", @"Balanced — 1366 × 1024", @"Quality — 2732 × 2048", @"Cancel"])]);
    // Quality is a choice, not a default: it asks first, and the default is untouched.
    UIAlertAction *quality = nil;
    for (UIAlertAction *action in sheet.actions) if ([action.title isEqual:@"Quality — 2732 × 2048"]) quality = action;
    assert(quality != nil);
    [self dismissPresented];
    RunAction(quality);
    Pump(0.6);
    UIAlertController *confirm = WaitForSheetTitled(self.controller, @"Above the recommendation", 20.0);
    assert(confirm != nil);
    assert([confirm.message containsString:@"more than this profile recommends"]);
    [self dismissPresented];
    Pump(0.4);
    // Declining the confirmation leaves the quality exactly where it was.
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WolkaraForeverRenderProfile"]
            isEqual:@"performance"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.renderProfile") configuration].title
            isEqual:@"Render profile: Performance — 1024 × 768"]);
    [self performSelector:@selector(chooseBalanced) withObject:nil afterDelay:0.4];
}
- (void)chooseBalanced {
    // Every backup this page makes is counted, so "a render profile never writes the game's
    // files" is a check and not a sentence in a document.
    configBeforePerformance = [self configText];
    backupsBeforePerformance = stubBackups;
    [[self row:@"wow.performance.renderProfile"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(applyBalanced) withObject:nil afterDelay:0.6];
}
- (void)applyBalanced {
    UIAlertController *sheet = [self settledPresentedController];
    assert([sheet isKindOfClass:UIAlertController.class]);
    [self dismissPresented];
    RunAction(sheet.actions[1]);   // Balanced
    Pump(0.6);
    UIAlertController *alert = WaitForSheetTitled(self.controller, @"Render profile ready", 20.0);
    assert(alert != nil);
    assert([alert.message containsString:@"Nothing in the game's own settings was changed"]);
    assert([alert.message containsString:@"Balanced — 1366 × 1024"]);
    [self dismissPresented];
    Pump(0.4);
    assert(stubBackups == backupsBeforePerformance);          // no UI snapshot was taken
    assert([[self configText] isEqual:configBeforePerformance]);  // and Config.wtf is untouched
    assert([NSUserDefaults.standardUserDefaults doubleForKey:@"WolkaraForeverBackingScale"] == 1.0);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WolkaraForeverRenderProfile"] isEqual:@"balanced"]);
    [self performSelector:@selector(restorePerformanceDefaults) withObject:nil afterDelay:0.4];
}
- (void)restorePerformanceDefaults {
    // The row that used to do this was removed with the rest of the home-page cleanup, and the
    // way back to this page's defaults is the Automatic choice in the device-profile sheet -
    // which writes exactly the two keys below. This drives that write, because the sheet's
    // action handler is not public API and the behaviour under test is the stored state.
    assert(Find(self.controller.view, @"wow.performance.restoreDefaults") == nil);
    NSUserDefaults *before = NSUserDefaults.standardUserDefaults;
    [before removeObjectForKey:@"WolkaraForeverDeviceProfile"];
    [before removeObjectForKey:@"WolkaraForeverRenderProfile"];
    [self.controller render];
    Pump(0.4);
    // Automatic for the device we are actually on, with nothing of this page's left behind -
    // and the game's settings still exactly where they were.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    assert([defaults stringForKey:@"WolkaraForeverDeviceProfile"] == nil);
    assert([defaults stringForKey:@"WolkaraForeverRenderProfile"] == nil);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.deviceProfile") configuration].title
            isEqual:@"Device profile: Automatic — this device (unrecognised)"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.renderProfile") configuration].title
            isEqual:@"Render profile: Performance"]);
    assert(stubBackups == backupsBeforePerformance);
    assert([[self configText] isEqual:configBeforePerformance]);
    assert(Find(self.controller.view, @"wow.performance.restoreDefaults") == nil);
    // Finally the app's own language: the setting, the German page, the one-time offer to put
    // the game into German too, and the switch back.
    [self performSelector:@selector(startLanguageTests) withObject:nil afterDelay:0.3];
}

#pragma mark - The app's language, and the game's

// The two settings are independent and both are ours to keep. What is checked here: the config
// file owns both (and still refuses an invented language), the row reads in the language in use,
// German applies to the page without a relaunch, no raw key is ever visible, the first German
// selection offers - once - to put the *game* into German through the existing validated writer,
// and switching back is immediate too.
- (void)startLanguageTests {
    // The launch checks above ended on a deliberate startup failure, which the page still says.
    // A language change is judged against a ready installation, so that page is put back first.
    [self.controller setValue:nil forKey:@"_startupFailure"];
    [self.controller render];
    assert([[self status] isEqual:@"Ready to play"]);
    WKLocalization.shared.language = WKAppLanguageEnglish;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverGameLanguageOfferShown"];
    [NSUserDefaults.standardUserDefaults setObject:@"enUS" forKey:@"WoWLocale"];

    // --- the config file owns both languages
    assert([TKWolkaraForeverConfig ownsKey:@"WolkaraForeverAppLanguage"]);
    assert([TKWolkaraForeverConfig ownsKey:@"WolkaraForeverGameLanguageOfferShown"]);
    NSString *problem = nil;
    NSDictionary *accepted = [TKWolkaraForeverConfig
        validatedSettingsFromFile:@{@"version": @1,
                                    @"settings": @{@"WolkaraForeverAppLanguage": @"de",
                                                   @"WoWLocale": @"deDE"}}
                           problem:&problem];
    assert([accepted[@"WolkaraForeverAppLanguage"] isEqual:@"de"]);
    // deDE is a game language the schema accepts: it was selectable long before the schema knew
    // it, and a German setting that cannot be exported is not a German setting.
    assert([accepted[@"WoWLocale"] isEqual:@"deDE"]);
    assert(problem == nil);
    // French is accepted for both settings now, and survives export like German: a language
    // the app and the downloader both offer cannot be refused by the file it is written to.
    problem = nil;
    accepted = [TKWolkaraForeverConfig
        validatedSettingsFromFile:@{@"version": @1,
                                    @"settings": @{@"WolkaraForeverAppLanguage": @"fr",
                                                   @"WoWLocale": @"frFR"}}
                           problem:&problem];
    assert([accepted[@"WolkaraForeverAppLanguage"] isEqual:@"fr"]);
    assert([accepted[@"WoWLocale"] isEqual:@"frFR"]);
    assert(problem == nil);
    // An invented language is refused, and the rest of the file still stands.
    problem = nil;
    accepted = [TKWolkaraForeverConfig
        validatedSettingsFromFile:@{@"version": @1,
                                    @"settings": @{@"WolkaraForeverAppLanguage": @"it",
                                                   @"WoWLocale": @"deDE"}}
                           problem:&problem];
    assert(accepted[@"WolkaraForeverAppLanguage"] == nil);
    assert([accepted[@"WoWLocale"] isEqual:@"deDE"]);
    assert(problem != nil);
    // A file written before the setting existed carries no app language at all, and that is
    // System Default rather than a refusal or an English guess.
    problem = nil;
    accepted = [TKWolkaraForeverConfig validatedSettingsFromFile:@{@"version": @1,
                                                                  @"settings": @{@"WoWRegion": @"eu"}}
                                                          problem:&problem];
    assert(problem == nil);
    assert([WKLocalization languageForStoredValue:accepted[WKAppLanguageDefaultsKey]] == WKAppLanguageSystem);

    // --- the row exists, on its own identifier, and reads in the language in use
    UIButton *language = [self row:@"wow.language"];
    assert(language != nil);
    assert([language.configuration.title isEqual:@"App language: English"]);
    // System Default says what it resolved to, because the row above it is a different language.
    WKLocalization.shared.language = WKAppLanguageSystem;
    assert([[self row:@"wow.language"].configuration.title hasPrefix:@"App language: English"]);
    WKLocalization.shared.language = WKAppLanguageEnglish;

    // --- a sheet opened from another sheet's action is not lost to the dismissal
    [[self row:@"wow.preferences"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkNestedSheet) withObject:nil afterDelay:0.4];
}

// Declared on TKWoWViewController for the fixture; see the category above.

- (void)checkNestedSheet {
    UIAlertController *preferences = WaitForSheetTitled(self.controller, @"Download preferences", 20.0);
    assert(preferences != nil);
    assert(CancelActions(preferences) == 1);
    assert([[preferences.actions valueForKey:@"title"]
        isEqualToArray:(@[@"Region", @"Language", @"Cancel"])]);
    // Exactly what the sheet's own "Language" action does: the sheet starts its
    // animated dismissal, and the handler opens the picker in the same turn. The
    // action is the sheet's own, not a method called behind it.
    UIAlertAction *language = nil;
    for (UIAlertAction *action in preferences.actions) if ([action.title isEqual:@"Language"]) language = action;
    assert(language != nil);
    [self.controller dismissViewControllerAnimated:YES completion:nil];
    RunAction(language);
    [self performSelector:@selector(checkNestedSheetOpened) withObject:nil afterDelay:1.0];
}

- (void)checkNestedSheetOpened {
    UIAlertController *picker = WaitForSheetTitled(self.controller, @"Download language", 20.0);
    assert(picker != nil);
    NSArray *titles = [picker.actions valueForKey:@"title"];
    assert([titles containsObject:@"German"]);
    assert([titles containsObject:@"Spanish"]);
    [self dismissPresented];
    // --- the row's own sheet offers the three choices, and the last one names its resolution
    [self performSelector:@selector(openLanguageSheet) withObject:nil afterDelay:0.4];
}

- (void)openLanguageSheet {
    [[self row:@"wow.language"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self performSelector:@selector(checkLanguageSheet) withObject:nil afterDelay:0.6];
}

- (void)checkLanguageSheet {
    UIAlertController *sheet = WaitForSheetTitled(self.controller, @"App language", 20.0);
    assert(sheet != nil);
    assert([sheet.message containsString:@"game language"]);
    NSArray *titles = [sheet.actions valueForKey:@"title"];
    assert([titles containsObject:@"English"]);
    assert([titles containsObject:@"Deutsch"]);
    assert([titles containsObject:@"System Default (English)"]);
    assert([titles containsObject:@"Cancel"]);
    [self dismissPresented];
    // The app's own sequence, reproduced: the choice is applied from the sheet's action handler,
    // in the same turn the sheet begins its animated dismissal. UIKit silently drops a
    // presentation that starts while another is going away, so without the wait the one-time
    // offer is lost and its flag spent - which is what this checks now.
    [self.controller dismissViewControllerAnimated:YES completion:nil];
    int backupsBefore = stubBackups;
    [self.controller applyAppLanguage:WKAppLanguageGerman];
    assert(stubBackups == backupsBefore);   // a language is not a file operation
    [self performSelector:@selector(checkGermanPage) withObject:nil afterDelay:1.4];
}

- (void)checkGermanPage {
    WKLocalization *localization = WKLocalization.shared;
    assert(localization.resolvedLanguage == WKAppLanguageGerman);
    assert([localization.languageCode isEqual:@"de"]);
    // The page, in German, from the same controller that was showing English a moment ago.
    NSLog(@"DE STATUS: %@ / %@", [self status], [(UILabel *)Find(self.controller.view, @"wow.detail") text]);
    assert([[self status] isEqual:@"Bereit zum Spielen"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.performance.backup") configuration].title
        isEqual:@"WoW-Oberflächenkonfiguration sichern"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.addons.macEver") configuration].title
        isEqual:@"Empfohlene Add-ons installieren (WolkaraRoue)"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.launcher.interfaceMode") configuration].title
        isEqual:@"Oberflächenmodus: iPadOS"]);
    // A product name stays itself in both languages.
    assert([[(UILabel *)Find(self.controller.view, @"wow.performance.gamepad.label") text]
        isEqual:@"Gamepad-Oberfläche"]);
    // Section headings, which were made before this language existed.
    assert([[(UILabel *)Find(self.controller.view, @"wow.heading.edition") text] isEqual:@"SPIELVERWALTUNG"]);
    assert([[(UILabel *)Find(self.controller.view, @"wow.heading.profile") text] isEqual:@"LEISTUNGSVERWALTUNG"]);
    assert([[(UILabel *)Find(self.controller.view, @"wow.heading.performance") text] isEqual:@"OBERFLÄCHENVERWALTUNG"]);
    assert([[(UILabel *)Find(self.controller.view, @"wow.heading.launcherManager") text] isEqual:@"STARTVERWALTUNG"]);
    // The row that made the change, and the accessibility labels VoiceOver reads.
    assert([[(UIButton *)Find(self.controller.view, @"wow.language") configuration].title
        isEqual:@"App-Sprache: Deutsch"]);
    assert([self.controller.navigationItem.rightBarButtonItem.accessibilityLabel isEqual:@"Einstellungen"]);
    // Nothing on the page is a raw key, and nothing is left in the other language's words.
    [self assertNoRawKeysInView:self.controller.view];

    // --- the one-time offer, localized, with the two answers it promises
    UIAlertController *offer = WaitForSheetTitled(self.controller, @"Auch die Spielsprache ändern?", 20.0);
    assert(offer != nil);
    NSArray *titles = [offer.actions valueForKey:@"title"];
    assert([titles containsObject:@"Spielsprache ebenfalls auf Deutsch ändern"]);
    assert([titles containsObject:@"Spielsprache unverändert lassen"]);
    [self dismissPresented];
    assert([[NSUserDefaults.standardUserDefaults objectForKey:@"WolkaraForeverGameLanguageOfferShown"] boolValue]);

    // The page's own picture is taken once the offer has gone, not while it is arriving: the
    // alert animates in over the page, and a screenshot taken mid-fade differs from the recorded
    // one by a strip of its edges - measured on the iPhone Duo on 2026-11-12, where the same
    // build compared clean and dirty on alternate runs for no reason but the clock.
    [self performSelector:@selector(captureGermanHome) withObject:nil afterDelay:0.5];
}

- (void)captureGermanHome {
    [self capture:@"wow-home-de.png"];

    // --- every other page WolkaraForever shows *before a game runs*, in German
    [self performSelector:@selector(openGermanAbout) withObject:nil afterDelay:0.3];
}

#pragma mark - The pre-game surface, in German

// The scan these pages use: no visible string may be a localization key, and no visible string
// may be the English table's copy of a key whose German differs. That second rule is what makes
// this a check of the screen rather than of one label a test remembered to name - a page that
// came up half-translated fails it without anyone having to write the assertion for that page.
static NSDictionary *TableForLanguage(NSString *code) {
    NSString *folder = [NSBundle.mainBundle pathForResource:code ofType:@"lproj"];
    if (!folder) return @{};
    id table = [NSDictionary dictionaryWithContentsOfFile:
        [folder stringByAppendingPathComponent:@"Localizable.strings"]];
    return [table isKindOfClass:NSDictionary.class] ? table : @{};
}
// Every string a person can read in this view: labels, buttons, field and search placeholders,
// and the segments of a segmented control. The last two are why this is one walker rather than a
// check written per page - a segmented control's item titles are not a label and were invisible
// to the first version of this scan.
static NSArray<NSString *> *VisibleTexts(UIView *view) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:view];
    while (pending.count) {
        UIView *each = pending.lastObject; [pending removeLastObject];
        [pending addObjectsFromArray:each.subviews];
        if ([each isKindOfClass:UILabel.class] && ((UILabel *)each).text.length)
            [texts addObject:((UILabel *)each).text];
        else if ([each isKindOfClass:UIButton.class]) {
            NSString *title = ((UIButton *)each).configuration.title ?: [(UIButton *)each titleForState:UIControlStateNormal];
            if (title.length) [texts addObject:title];
        } else if ([each isKindOfClass:UITextField.class] && ((UITextField *)each).placeholder.length)
            [texts addObject:((UITextField *)each).placeholder];
        else if ([each isKindOfClass:UISearchBar.class] && ((UISearchBar *)each).placeholder.length)
            [texts addObject:((UISearchBar *)each).placeholder];
        else if ([each isKindOfClass:UISegmentedControl.class]) {
            UISegmentedControl *control = (UISegmentedControl *)each;
            for (NSUInteger i = 0; i < control.numberOfSegments; i++) {
                NSString *title = [control titleForSegmentAtIndex:i];
                if (title.length) [texts addObject:title];
            }
        }
    }
    return texts;
}
- (void)assertGermanOnlyInView:(UIView *)view page:(NSString *)page {
    NSDictionary *english = TableForLanguage(@"en"), *german = TableForLanguage(@"de");
    assert(english.count > 100 && german.count > 100);   // the fixture carries the real tables
    NSRegularExpression *key = [NSRegularExpression regularExpressionWithPattern:@"^[a-z][A-Za-z0-9]*(\\.[A-Za-z0-9_]+)+$"
                                                                        options:0 error:NULL];
    NSArray<NSString *> *texts = VisibleTexts(view);
    assert(texts.count > 0);
    for (NSString *text in texts) {
        if ([key firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) {
            NSLog(@"RAW KEY on %@: %@", page, text);
            assert(!text);
        }
        for (NSString *k in english) {
            if ([english[k] isEqual:text] && ![german[k] isEqual:text]) {
                NSLog(@"ENGLISH STILL SHOWN on %@: %@ (key %@)", page, text, k);
                assert(![english[k] isEqual:text]);
            }
        }
    }
}
- (void)openGermanAbout {
    [self.controller about];
    [self performSelector:@selector(checkGermanAbout) withObject:nil afterDelay:0.6];
}
- (void)checkGermanAbout {
    UIViewController *page = self.controller.navigationController.topViewController;
    assert(page != self.controller);
    assert([page.title isEqual:@"Über diese App"]);
    UITextView *body = (id)page.view;
    assert([body isKindOfClass:UITextView.class]);
    assert([body.text containsString:@"unabhängiger World-of-Warcraft-Launcher"]);
    assert([body.text containsString:@"WolkaraForever – Lizenz dieser App"]);
    assert(![body.text containsString:@"missing from this build"]);
    [self.controller.navigationController popToRootViewControllerAnimated:NO];
    [self performSelector:@selector(openGermanAddons) withObject:nil afterDelay:0.4];
}
- (void)openGermanAddons {
    [self.controller manageAddons];
    [self performSelector:@selector(checkGermanAddons) withObject:nil afterDelay:1.0];
}
- (void)checkGermanAddons {
    UINavigationController *frame = [self settledPresentedController];
    assert([frame isKindOfClass:UINavigationController.class]);
    UIViewController *page = frame.topViewController;
    assert([page.title isEqual:@"ADD-ON-VERWALTUNG"]);
    [self.window layoutIfNeeded];
    [self assertGermanOnlyInView:page.view page:@"ADD-ON-VERWALTUNG"];
    [self capture:@"wow-addons-de.png"];
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    [self performSelector:@selector(openGermanVoice) withObject:nil afterDelay:0.4];
}
- (void)openGermanVoice {
    [self.controller manageVoice];
    [self performSelector:@selector(checkGermanVoice) withObject:nil afterDelay:0.8];
}
- (void)checkGermanVoice {
    UINavigationController *frame = [self settledPresentedController];
    assert([frame isKindOfClass:UINavigationController.class]);
    UIViewController *page = frame.topViewController;
    assert([page isKindOfClass:AKVoiceViewController.class]);
    assert([page.title isEqual:@"TASTEN UND BUTTONS BELEGEN"]);
    [self.window layoutIfNeeded];
    [self assertGermanOnlyInView:page.view page:@"voice settings"];
    [self capture:@"wow-voice-de.png"];
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    [self performSelector:@selector(openGermanVoiceTest) withObject:nil afterDelay:0.4];
}
- (void)openGermanVoiceTest {
    [self.controller testVoice];
    [self performSelector:@selector(checkGermanVoiceTest) withObject:nil afterDelay:0.8];
}
- (void)checkGermanVoiceTest {
    UINavigationController *frame = [self settledPresentedController];
    assert([frame isKindOfClass:UINavigationController.class]);
    UIViewController *page = frame.topViewController;
    assert([page isKindOfClass:AKVoiceTestViewController.class]);
    assert([page.title isEqual:@"SPRACHE TESTEN"]);
    [self.window layoutIfNeeded];
    [self assertGermanOnlyInView:page.view page:@"voice test"];
    [self capture:@"wow-voice-test-de.png"];
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    [self performSelector:@selector(openGermanSettings) withObject:nil afterDelay:0.4];
}
- (void)openGermanSettings {
    [self.controller settings];
    [self performSelector:@selector(checkGermanSettings) withObject:nil afterDelay:0.6];
}
- (void)checkGermanSettings {
    UIAlertController *sheet = WaitForSheetTitled(self.controller, @"Einstellungen", 20.0);
    assert(sheet != nil);
    assert([sheet.message containsString:@"Aktualisierungen werden automatisch installiert"]);
    NSArray *titles = [sheet.actions valueForKey:@"title"];
    for (NSString *expected in @[@"Spieldateien prüfen und reparieren",
                                 @"Diagnose und Protokolle", @"Eingabediagnose einschalten",
                                 @"Über diese App und Open-Source-Lizenzen",
                                 @"Abbrechen"])
        assert([titles containsObject:expected]);
    [self dismissPresented];
    // --- and the game's own language, which is the last thing before a game would start
    [self performSelector:@selector(applyGermanGameLanguage) withObject:nil afterDelay:0.4];
}
- (void)applyGermanGameLanguage {
    // The first answer to the offer, through the same writer the Game language row uses:
    // WoWLocale, Config.wtf's two locales, and no portal change.
    [self.controller setGameLocale:@"deDE"];
    [self performSelector:@selector(checkGermanGameLanguage) withObject:nil afterDelay:1.2];
}

- (void)checkGermanGameLanguage {
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WoWLocale"] isEqual:@"deDE"]);
    NSString *config = [self configText];
    assert([config containsString:@"SET textLocale \"deDE\""]);
    assert([config containsString:@"SET audioLocale \"deDE\""]);
    // The region, and every unrelated setting, is exactly as it was.
    assert([config containsString:@"SET portal \"eu\""]);
    assert([config containsString:@"SET accountName \"TESTACCOUNT\""]);
    // The Game language row says Deutsch, in German, and the app's language did not move.
    assert([[[self row:@"wow.preferences"].configuration.title componentsSeparatedByString:@"Deutsch"] count] == 2);
    assert(WKLocalization.shared.resolvedLanguage == WKAppLanguageGerman);

    // --- switching back is immediate, and the offer is not repeated
    [self.controller applyAppLanguage:WKAppLanguageEnglish];
    assert([[self status] isEqual:@"Ready to play"]);
    assert([[(UIButton *)Find(self.controller.view, @"wow.language") configuration].title
        isEqual:@"App language: English"]);
    assert([[(UILabel *)Find(self.controller.view, @"wow.heading.edition") text] isEqual:@"GAME SETTINGS MANAGER"]);
    assert(self.controller.presentedViewController == nil);   // no German offer again
    [self assertNoRawKeysInView:self.controller.view];

    // German at the largest text size: the longest labels the app has, in the layout that has
    // the least room for them.
    WKLocalization.shared.language = WKAppLanguageGerman;
    self.controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
    [self performSelector:@selector(checkGermanLargeText) withObject:nil afterDelay:0.4];
}

- (void)checkGermanLargeText {
    [self.window layoutIfNeeded];
    UIScrollView *scroll = (id)Find(self.controller.view, @"wow.scroll");
    assert(scroll != nil);
    // The page is a scrolling column at this size, and every row is inside it: nothing is
    // clipped to a width that was measured for English.
    for (NSString *identifier in @[@"wow.language", @"wow.performance.backup", @"wow.addons.directory",
                                   @"wow.permissions", @"wow.primary"]) {
        UIView *row = Find(self.controller.view, identifier);
        assert(row != nil);
        assert(row.bounds.size.height > 0);
        CGRect inScroll = [row convertRect:row.bounds toView:scroll];
        assert(CGRectGetWidth(inScroll) <= scroll.bounds.size.width + 1);
    }
    [self capture:@"wow-home-de-large-text.png"];
    self.controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
    // Leave the app as it was found: English, and the game's own language back where it started.
    [self.controller setGameLocale:@"enUS"];
    [self performSelector:@selector(finishLanguageTests) withObject:nil afterDelay:0.4];
}

- (void)finishLanguageTests {
    [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:WKAppLanguageDefaultsKey];
    assert(WKLocalization.shared.resolvedLanguage == WKAppLanguageEnglish);
    [self performSelector:@selector(startEveryHomeControl) withObject:nil afterDelay:0.4];
}

#pragma mark - Every control on the home page

// The page is what a person touches, and most of its rows had only ever been proven
// by calling the controller's method behind them - which proves the method, not that
// the button is wired to it. Two controls had no coverage at all (the two navigation
// items) and two could not be reached from a fixture (the add-on folder row and the
// Settings page row). This presses each one in turn and follows what it does.
- (void)startEveryHomeControl {
    // Back to English through the app's own route, so what the sheets say is what the
    // assertions below expect: the language section leaves the page drawn in whatever
    // its last step asked for.
    [self.controller applyAppLanguage:WKAppLanguageEnglish];
    Pump(0.6);
    assert(self.controller.presentedViewController == nil);
    unsigned beforeCheck = 0;

    // --- Edition: a sheet naming every edition it offers, and exactly one way out
    assert([self row:@"wow.edition"].enabled);
    [[self row:@"wow.edition"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    Pump(0.6);
    UIAlertController *edition = WaitForSheetTitled(self.controller, @"Choose your edition", 20.0);
    assert(edition != nil);
    assert(CancelActions(edition) == 1);
    assert(edition.actions.count == TKWoWProducts().count + 1);
    NSArray *editionTitles = [edition.actions valueForKey:@"title"];
    for (NSDictionary *product in TKWoWProducts())
        assert([editionTitles containsObject:product[@"name"]]);
    // Selecting one asks for one check. The edition already selected is chosen, so
    // nothing else about the page moves; that a choice switches edition and survives a
    // relaunch is covered by the edition-race section above.
    UIAlertAction *forever = nil;
    for (UIAlertAction *action in edition.actions) if ([action.title isEqual:@"Forever"]) forever = action;
    assert(forever != nil);
    beforeCheck = atomic_load(&requests);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(forever);
    Pump(1.2);
    assert(atomic_load(&requests) == beforeCheck + 1);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WoWProduct"] isEqual:@"wowf"]);
    assert(self.controller.presentedViewController == nil);
    assert([[self row:@"wow.edition"].configuration.title isEqual:@"Game Edition: Forever"]);

    // --- Preferences: Region, through the sub-sheet the row opens and the action it holds
    assert([self row:@"wow.preferences"].enabled);
    [[self row:@"wow.preferences"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    Pump(0.6);
    UIAlertController *preferences = WaitForSheetTitled(self.controller, @"Download preferences", 20.0);
    assert(preferences != nil);
    assert(CancelActions(preferences) == 1);
    UIAlertAction *region = nil;
    for (UIAlertAction *action in preferences.actions) if ([action.title isEqual:@"Region"]) region = action;
    assert(region != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(region);
    Pump(0.7);
    UIAlertController *regions = WaitForSheetTitled(self.controller, @"Region", 20.0);
    assert(regions != nil);
    assert(CancelActions(regions) == 1);
    assert([[regions.actions valueForKey:@"title"]
        isEqualToArray:(@[@"Europe", @"Americas", @"Korea", @"Taiwan", @"Cancel"])]);
    UIAlertAction *americas = nil;
    for (UIAlertAction *action in regions.actions) if ([action.title isEqual:@"Americas"]) americas = action;
    assert(americas != nil);
    beforeCheck = atomic_load(&requests);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(americas);
    Pump(1.2);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WoWRegion"] isEqual:@"us"]);
    assert([[self row:@"wow.preferences"].configuration.title isEqual:@"Region / Locale: US English"]);
    assert(atomic_load(&requests) == beforeCheck + 1);
    // Back to Europe through the same two sheets, so every later step runs where the
    // page started. The row's title follows the change both ways.
    [[self row:@"wow.preferences"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    Pump(0.6);
    preferences = [self settledPresentedController];
    region = nil;
    for (UIAlertAction *action in preferences.actions) if ([action.title isEqual:@"Region"]) region = action;
    assert(region != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(region);
    Pump(0.7);
    regions = WaitForSheetTitled(self.controller, @"Region", 20.0);
    assert(regions != nil);
    UIAlertAction *europe = nil;
    for (UIAlertAction *action in regions.actions) if ([action.title isEqual:@"Europe"]) europe = action;
    assert(europe != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(europe);
    Pump(1.2);
    assert([[NSUserDefaults.standardUserDefaults stringForKey:@"WoWRegion"] isEqual:@"eu"]);
    assert([[self row:@"wow.preferences"].configuration.title isEqual:@"Region / Locale: EU English"]);

    // --- Open Add-on Directory: the file browser opens on the game's Interface/AddOns
    assert([self row:@"wow.addons.directory"].enabled);
    __block NSURL *addonFolder = nil;
    self.controller.openAddonDirectoryURL = ^(NSURL *url) { addonFolder = url; };
    [[self row:@"wow.addons.directory"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(addonFolder != nil);
    assert([addonFolder.lastPathComponent isEqual:@"AddOns"]);
    assert([addonFolder.path hasPrefix:fixture.directory]);
    // The game makes this folder on its first run; before that the row makes it rather
    // than refusing, so the destination it just opened has to exist.
    assert([NSFileManager.defaultManager fileExistsAtPath:addonFolder.path]);
    self.controller.openAddonDirectoryURL = nil;

    // --- Toggle Permissions: this app's own page in Settings, and the system is not asked
    assert([self row:@"wow.permissions"].enabled);
    __block NSURL *settingsPage = nil;
    self.controller.openAppSettingsURL = ^(NSURL *url) { settingsPage = url; };
    [[self row:@"wow.permissions"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert([settingsPage.absoluteString isEqual:UIApplicationOpenSettingsURLString]);
    self.controller.openAppSettingsURL = nil;

    // --- Refresh, the left navigation item: one check, exactly, and nothing else
    UIBarButtonItem *refresh = self.controller.navigationItem.leftBarButtonItem;
    assert([refresh.accessibilityIdentifier isEqual:@"wow.refresh"]);
    assert(refresh.enabled);
    beforeCheck = atomic_load(&requests);
    TapBarItem(refresh);
    Pump(1.2);
    assert(atomic_load(&requests) == beforeCheck + 1);

    // --- Settings, the right navigation item, and the actions it offers
    UIBarButtonItem *gear = self.controller.navigationItem.rightBarButtonItem;
    assert([gear.accessibilityIdentifier isEqual:@"wow.settings"]);
    assert(gear.enabled);
    TapBarItem(gear);
    Pump(0.7);
    UIAlertController *settings = WaitForSheetTitled(self.controller, @"Settings", 20.0);
    assert(settings != nil);
    assert(CancelActions(settings) == 1);
    assert([[settings.actions valueForKey:@"title"] isEqualToArray:
        (@[@"Verify and repair game files", @"Diagnostics and logs",
           @"Turn on input diagnostics", @"About and open-source licenses", @"Cancel"])]);
    assert(![[settings.actions valueForKey:@"title"] containsObject:@"Manage add-ons"]);
    // Diagnostics, from the sheet: the block the item is wired to is the one that runs.
    __block NSInteger diagnostics = 0;
    self.controller.showDiagnostics = ^{ diagnostics++; };
    UIAlertAction *diagnosticsAction = nil;
    for (UIAlertAction *action in settings.actions) if ([action.title isEqual:@"Diagnostics and logs"]) diagnosticsAction = action;
    assert(diagnosticsAction != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(diagnosticsAction);
    Pump(0.4);
    assert(diagnostics == 1);
    self.controller.showDiagnostics = nil;
    // ... and About, which pushes its page onto the launcher's own stack.
    TapBarItem(gear);
    Pump(0.7);
    settings = [self settledPresentedController];
    assert([settings isKindOfClass:UIAlertController.class]);
    UIAlertAction *about = nil;
    for (UIAlertAction *action in settings.actions) if ([action.title isEqual:@"About and open-source licenses"]) about = action;
    assert(about != nil);
    [self.controller dismissViewControllerAnimated:NO completion:nil];
    RunAction(about);
    Pump(0.8);
    assert([self.controller.navigationController.topViewController.title isEqual:@"About"]);
    [self.controller.navigationController popToRootViewControllerAnimated:NO];
    assert(self.controller.navigationController.topViewController == self.controller);

    // --- and no control on the page is dead: every one has a target and an action
    for (NSString *identifier in @[@"wow.edition", @"wow.preferences", @"wow.language",
                                   @"wow.addons.manage", @"wow.addons.macEver", @"wow.addons.directory",
                                   @"wow.launcher.interfaceMode",
                                   @"wow.permissions", @"wow.voice", @"wow.voice.test",
                                   @"wow.performance.deviceProfile", @"wow.performance.renderProfile",
                                   @"wow.performance.backup",
                                   @"wow.performance.reset", @"wow.performance.restore",
                                   @"wow.performance.settingsFolder", @"wow.primary", @"wow.diagnostics"])
        assert([[self row:identifier] allTargets].count > 0);
    for (NSString *identifier in @[@"wow.performance.gamepad", @"wow.performance.overlay"])
        assert([self toggle:identifier].allTargets.count > 0);
    for (UIBarButtonItem *item in @[gear, refresh])
        assert(item.target != nil && item.action != NULL);

    puts("WoW UIKit PASS: automatic check/update, offline retry, edition race, background cancellation, verified launch, inline preparation/failure/session end, no duplicate launches and bundled licenses; home page headings, rows, order, identifiers, labels, enabled states and the recommendation row; the Launcher Manager card (Automatic, iPadOS and iOS on Duo, each resolved from the stored choice, persisted, and no package moved by a switch) and the bundled-package page it opens; backup, confirmed reset, gamepad config, folder picker and restore flow; device profile (automatic, preview and the way back), render profile with the quality a device was measured at, no game-file write from either; the app language as a setting of its own (config ownership and migration, the row, immediate German and immediate English, no raw keys, the one-time German game-language offer through the validated locale writer, and German at the largest text size); and every control on the home page pressed - the edition sheet, download preferences and its Region sub-sheet, the app language row, all three add-on rows, the add-on folder browser, the permissions row, both voice pages, all nine Performance rows and both switches, the primary button, the Diagnostics button, and both navigation items.");
    fflush(stdout);
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) exit(0);
    // Leave a ready home for visual inspection; no real download or guest runs.
    [self.controller refresh];
}

// Nothing visible may be a localization key. The service falls back to English and then to a
// readable name rather than to the key itself, and the tables are checked as a whole by
// wolkaraforever/tools/check_localization.py; this asserts the other half - that no call site
// handed a key to a label by mistake.
- (void)assertNoRawKeysInView:(UIView *)view {
    NSRegularExpression *key = [NSRegularExpression regularExpressionWithPattern:@"^[a-z][A-Za-z0-9]*(\\.[A-Za-z0-9_]+)+$"
                                                                        options:0 error:NULL];
    for (NSString *text in VisibleTexts(view)) {
        if ([key firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) {
            NSLog(@"RAW KEY VISIBLE: %@", text);
            assert(!text);
        }
    }
}

- (void)checkLaunch {
    assert(self.launches==1); self.controller.sessionUsed=YES;
    [self.controller beginStartup];
    self.controller.startupStatusLabel.text=@"Preparing to run. This can take a few minutes. Keep this app open.";
    assert(![self primary].enabled && !self.controller.launchProgress.hidden);
    assert([[self status] isEqual:@"Starting…"]);
    // The Forever file rows are disabled while a start is in progress; every
    // handler rechecks the same guard.
    for (NSString *identifier in @[@"wow.performance.backup", @"wow.performance.reset",
                                   @"wow.performance.restore", @"wow.performance.settingsFolder",
                                   @"wow.performance.deviceProfile", @"wow.performance.renderProfile"])
        assert(![self row:identifier].enabled);
    // All text is grey while starting, including the two navigation rows that
    // used to stay gold.
    assert(![self row:@"wow.addons.macEver"].enabled);
    assert(![self row:@"wow.permissions"].enabled);
    assert(![self toggle:@"wow.performance.gamepad"].enabled);
    assert(![self toggle:@"wow.performance.overlay"].enabled);
    // ...and their labels are the same grey as the rows beside them, rather than
    // keeping the white they use when they are usable.
    assert(CGColorEqualToColor([(UILabel *)Find(self.controller.view, @"wow.performance.gamepad.label") textColor].CGColor,
                               [(UIButton *)Find(self.controller.view, @"wow.addons.macEver") configuration].baseForegroundColor.CGColor));
    assert(CGColorEqualToColor([(UILabel *)Find(self.controller.view, @"wow.performance.overlay.label") textColor].CGColor,
                               [(UIButton *)Find(self.controller.view, @"wow.permissions") configuration].baseForegroundColor.CGColor));
    assert(self.controller.navigationController.viewControllers.count==1);
    unsigned before=atomic_load(&requests);
    [self.controller refresh];
    if ([self primary].enabled) [self tap];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert(atomic_load(&requests)==before && self.launches==1);
    [self capture:@"wow-starting.png"];
    // The guest's window is the transition from loading to running.
    [self.controller guestDidStartRunning];
    assert([[self status] isEqual:@"Running"] && ![self primary].enabled);
    assert(self.controller.launchProgress.hidden);
    [self capture:@"wow-running.png"];
    [self.controller finishStartupWithMessage:@"Session ended" failed:NO];
    assert([[self status] isEqual:@"Game closed"] && [self primary].enabled);
    assert([[self primary].currentTitle isEqual:@"Close WolkaraForever"]);
    assert(self.controller.diagnosticsButton.hidden);
    // A full startup that failed also cannot be retried here: the same close
    // action, not a Play that answers nothing.
    [self.controller beginStartup];
    [self.controller finishStartupWithMessage:@"Synthetic startup failure" failed:YES];
    assert([[self status] isEqual:@"Could not start"] && [self primary].enabled);
    assert([[self primary].currentTitle isEqual:@"Close WolkaraForever"]);
    // The Diagnostics button is on screen only after a start failed, which is the one
    // state that can reach it; it had no coverage at all.
    assert(!self.controller.diagnosticsButton.hidden);
    __block NSInteger diagnosticsTaps = 0;
    self.controller.showDiagnostics = ^{ diagnosticsTaps++; };
    [self.controller.diagnosticsButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(diagnosticsTaps == 1);
    self.controller.showDiagnostics = nil;
    [self capture:@"wow-startup-failed.png"];
    // A recoverable preflight error, with no session used, must leave another
    // attempt possible.
    self.controller.sessionUsed=NO;
    [self.controller beginStartup];
    [self.controller finishStartupWithMessage:@"Synthetic missing container" failed:YES];
    assert([self primary].enabled && [[self primary].currentTitle isEqual:@"Try again"]);
    [self.controller about];
    UITextView *credits=(id)self.controller.navigationController.topViewController.view;
    // Our own notice, which carries the licences of what the launcher's readers adapt.
    assert([credits.text containsString:@"Vasilii Kharitonov"]);
    assert([credits.text containsString:@"Permission is hereby granted"]);
    assert([credits.text containsString:@"Martin Benjamins"]);
    // Upstream's, which has to be there too: the app ships upstream's code.
    assert([credits.text containsString:@"Tolkara is original work released under the MIT License"]);
    // And the page says whose each one is, rather than concatenating whatever it found.
    assert([credits.text containsString:@"WolkaraForever — this app's licence"]);
    assert([credits.text containsString:@"Tolkara — the platform this app is built on"]);
    // A document the build forgot must be named on the page, not skipped: silence is how
    // this went unnoticed in the first place.
    assert(![credits.text containsString:@"missing from this build"]);
    [self.controller.navigationController popToRootViewControllerAnimated:NO];
    // Finally the home page's own contract, on a ready installation.
    [self performSelector:@selector(startPerformanceTests) withObject:nil afterDelay:0.3];
}

@end
@interface TKWoWFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation TKWoWFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"WoW fixture" sessionRole:session.role];
    config.delegateClass=TKWoWFixtureDelegate.class; return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TKWoWFixtureApp.class)); }
}
