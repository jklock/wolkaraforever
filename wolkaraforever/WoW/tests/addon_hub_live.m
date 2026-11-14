// The Add-on Hub's live run. See addon_hub_live.h for what it is and why it exists.
#import "addon_hub_live.h"
#import "../launcher/WoW/AddonManager.h"
#import "../launcher/WoW/AddonStore.h"
#import "../launcher/WoW/AddonCredentialStore.h"
#import "../launcher/WoW/AddonBrowser.h"
#import "../launcher/WoW/AddonUpdateResolver.h"
#import "../launcher/WoW/AddonHubLog.h"
#import "../launcher/WoW/CurseForgeClient.h"
#import "../launcher/WoW/ForeverUI.h"
#import "../launcher/App/WolkaraForeverLog.h"
#import "../launcher/App/WKLocalization.h"
#import <objc/message.h>
#import <WebKit/WebKit.h>

// The page's own enter points. A fixture drives the controls a person presses; these are the
// selectors behind them, declared here because they are private to the page.
@interface TKWoWAddonManagerViewController (LiveProbe)
- (void)installMod:(NSDictionary *)entry;
- (void)checkForUpdates;
- (void)browse;
- (void)fetchDiscover;
- (void)startRowActionForRecord:(TKAddonRecord *)record;
- (void)presentHandoff:(TKAddonBrowserHandoff *)handoff forRecord:(nullable TKAddonRecord *)record;
- (void)cancelBulkUpdate;
- (void)runBulkUpdate:(NSArray<TKAddonRecord *> *)records;
- (void)reloadAddons;
@end

static NSInteger livePassed, liveFailed, liveSkipped;

static void LiveReport(NSString *state, NSString *what) {
    printf("LIVE %-7s %s\n", state.UTF8String, what.UTF8String);
    fflush(stdout);
}

static void LiveCheck(BOOL condition, NSString *what) {
    if (condition) { livePassed += 1; LiveReport(@"PASS", what); }
    else { liveFailed += 1; LiveReport(@"FAIL", what); }
}

static void LiveSkip(NSString *what) {
    liveSkipped += 1;
    LiveReport(@"NOT RUN", what);
}

static NSString *LiveDocuments(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static BOOL LiveMakeDirectory(NSString *path) {
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES
                                                    attributes:nil error:NULL];
}

static BOOL LiveWrite(NSString *path, NSString *text) {
    LiveMakeDirectory(path.stringByDeletingLastPathComponent);
    return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

// Wait for something the production code does on its own queue. A fixture that sleeps instead is
// asserting against a page that has not drawn yet; this polls the state it is waiting for.
static BOOL LiveWait(double seconds, BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (deadline.timeIntervalSinceNow > 0) {
        if (ready()) return YES;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return ready();
}

static void LivePump(double seconds) { LiveWait(seconds, ^BOOL { return NO; }); }

// The key, in memory only: never written to the container, never in the manifest, never logged.
static NSString *liveKey;
static NSString *LiveStoredKey(id self, SEL _cmd, NSError **error) {
    (void)self; (void)_cmd; (void)error;
    return liveKey.length ? liveKey : nil;
}

// The installation a player's own folder is. Every directory the client, the launcher and an
// add-on manager touch exists; only the game's code is a placeholder, because this run reads the
// installation's shape, not its data.
static NSString *LiveBuildInstallation(NSString *documents) {
    NSString *root = [documents stringByAppendingPathComponent:@"World of Warcraft"];
    NSString *working = [root stringByAppendingPathComponent:@"_forever_"];
    LiveMakeDirectory([documents stringByAppendingPathComponent:@"World of Warcraft.app/Contents/MacOS"]);
    // A regular file, not a link and not empty: discovery hashes the executable it records.
    LiveWrite([documents stringByAppendingPathComponent:@"World of Warcraft.app/Contents/MacOS/World of Warcraft"],
              @"This is a placeholder standing in for the client during a simulator run.\n");
    for (NSString *name in @[@"Interface/AddOns", @"Interface/AddOns/WolkaraRoue", @"WTF/Account/0/SavedVariables",
                             @"Data", @"Logs", @"Cache", @"Screenshots", @"Errors", @"Updates"]) {
        LiveMakeDirectory([working stringByAppendingPathComponent:name]);
    }
    LiveWrite([working stringByAppendingPathComponent:@".flavor.info"], @"ProductCode=WoWF\n");
    LiveWrite([working stringByAppendingPathComponent:@"WTF/Config.wtf"], @"SET locale \"enUS\"\n");
    LiveWrite([working stringByAppendingPathComponent:@"Interface/AddOns/WolkaraRoue/WolkaraRoue.toc"],
              @"## Title: WolkaraRoue\n## Version: 1.0.4\n## Author: WolkaraForever\n## Interface: 16001\n");
    LiveWrite([working stringByAppendingPathComponent:@"Interface/AddOns/WolkaraRoue/Core.lua"], @"-- lua\n");
    return working;
}

// One project from a live search, and the file this build would install for it.
static NSDictionary *LiveFirstProject(NSArray *projects, NSUInteger maximumBytes) {
    for (NSDictionary *project in projects) {
        if (![project isKindOfClass:NSDictionary.class]) continue;
        TKCurseForgeFileCandidate *candidate = TKCurseForgeChooseFile(project[@"latestFiles"], @"1.60.1");
        if (!candidate.file) continue;
        NSNumber *size = [candidate.file[@"fileLength"] isKindOfClass:NSNumber.class] ? candidate.file[@"fileLength"] : nil;
        if (size && size.unsignedLongLongValue > maximumBytes) continue;
        return project;
    }
    return nil;
}

static NSString *LiveSlug(NSDictionary *project) {
    if ([project[@"slug"] isKindOfClass:NSString.class] && [project[@"slug"] length]) return project[@"slug"];
    NSString *website = [project[@"links"] isKindOfClass:NSDictionary.class] ? project[@"links"][@"websiteUrl"] : nil;
    if (![website isKindOfClass:NSString.class]) return nil;
    return [NSURL URLWithString:website].lastPathComponent;
}

BOOL TKAddonHubLiveRequested(void) {
    return [NSProcessInfo.processInfo.arguments containsObject:@"--live-addons"];
}

BOOL TKAddonHubLiveRun(UIWindow *window, void (^capture)(NSString *name)) {
    @autoreleasepool {
        livePassed = liveFailed = liveSkipped = 0;
        NSString *documents = LiveDocuments();
        liveKey = [NSProcessInfo.processInfo.environment[@"WK_LIVE_API_KEY"]
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

        // 1. The installation, with no game code in it.
        NSString *working = LiveBuildInstallation(documents);
        NSString *addons = [working stringByAppendingPathComponent:@"Interface/AddOns"];
        LiveCheck([NSFileManager.defaultManager fileExistsAtPath:addons],
                  @"the fabricated installation has Interface/AddOns");
        for (NSString *required in @[@"WTF/Config.wtf", @"Data", @"Logs", @"Cache", @"Screenshots", @"Errors", @".flavor.info"])
            LiveCheck([NSFileManager.defaultManager fileExistsAtPath:[working stringByAppendingPathComponent:required]],
                      [NSString stringWithFormat:@"and the installation has %@", required]);

        // 2. The production page, opened on that installation's own AddOns directory - the path
        //    `manageAddons` resolves and the path `workingDirectoryForApp:` produces.
        if (liveKey.length) {
            Method method = class_getInstanceMethod(TKAddonCredentialStore.class, @selector(curseForgeKey:));
            if (method) method_setImplementation(method, (IMP)LiveStoredKey);
        }
        UIViewController *host = [UIViewController new];
        host.view.backgroundColor = UIColor.blackColor;
        window.rootViewController = host;
        [window makeKeyAndVisible];
        TKWoWAddonManagerViewController *page = [[TKWoWAddonManagerViewController alloc]
            initWithAddOnsDirectory:addons edition:@"Forever"];
        [page loadViewIfNeeded];
        UINavigationController *frame = [[UINavigationController alloc] initWithRootViewController:page];
        frame.modalPresentationStyle = UIModalPresentationFullScreen;
        [host presentViewController:frame animated:NO completion:nil];
        LiveCheck(LiveWait(8.0, ^BOOL { return page.viewIfLoaded.window != nil; }),
                  @"the Add-on Hub is on screen over the fabricated installation");
        LiveCheck(page.tab == TKAddonHubTabMyAddOns, @"and it opens on My Add-ons");
        TKAddonStore *store = [page valueForKey:@"_store"];
        LiveCheck([store isKindOfClass:TKAddonStore.class], @"the page owns a store for the installation's AddOns");
        LiveCheck(store.manifestFormat == 3, @"the manifest is format 3");
        capture(@"live-hub-myaddons");

        // 4. Everything a player's own folder already has is in the list, and it is not ours.
        TKAddonRecord *bundled = nil;
        for (TKAddonRecord *record in store.records) if ([record.identifier isEqual:@"WolkaraRoue"]) bundled = record;
        LiveCheck(bundled != nil, @"the folder already in Interface/AddOns is listed");
        LiveCheck(bundled && !bundled.managed, @"and is not claimed by the store");
        LiveCheck([bundled.provenance isEqual:TKAddonProvenanceUnmanaged], @"and is recorded as found on device");
        LiveCheck([page updateResultForRecord:bundled] == TKAddonUpdateResultUnlinked,
                  @"and says it has no linked project instead of guessing");

        // 5. Files import: the store transaction the document picker's delegate calls.
        NSString *zipPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"LiveAddon.zip"];
        BOOL importable = [NSFileManager.defaultManager fileExistsAtPath:zipPath];
        LiveCheck(importable, @"a real archive is staged for the Files import");
        if (importable) {
            NSUInteger before = store.records.count;
            NSError *importError = nil;
            BOOL imported = [store importZIPAtURL:[NSURL fileURLWithPath:zipPath] provider:nil
                                       provenance:TKAddonProvenanceFiles error:&importError];
            LiveCheck(imported, [NSString stringWithFormat:@"the Files import installs the archive%@",
                                 imported ? @"" : [@" - " stringByAppendingString:importError.localizedDescription ?: @"no reason"]]);
            [page performSelector:@selector(reloadAddons)];
            LiveCheck(store.records.count == before + 1, @"and adds one package");
            TKAddonRecord *item = nil;
            for (TKAddonRecord *record in store.records)
                if (record.identifier && ![record.identifier isEqual:@"WolkaraRoue"]) item = record;
            LiveCheck(item.managed, @"which the store now owns");
            LiveCheck([item.provenance isEqual:TKAddonProvenanceFiles], @"and records as a Files import");
            LiveCheck(item.digest.length == 64, @"with the archive's own digest");
            LiveCheck(item.installedAt.length > 0, @"and the time it was installed");
        }

        // 6. A folder that appears on disk is discovered on the next read.
        LiveWrite([addons stringByAppendingPathComponent:@"HandMade/HandMade.toc"],
                  @"## Title: Hand Made\n## Version: 0.1\n## Author: Nobody\n## Interface: 16001\n");
        [page performSelector:@selector(reloadAddons)];
        TKAddonRecord *handMade = nil;
        for (TKAddonRecord *record in store.records) if ([record.identifier isEqual:@"HandMade"]) handMade = record;
        LiveCheck(handMade != nil, @"a folder written on disk is discovered");
        LiveCheck(handMade && [handMade.provenance isEqual:TKAddonProvenanceUnmanaged], @"as found on device");
        LiveCheck(handMade && [page updateResultForRecord:handMade] == TKAddonUpdateResultUnlinked, @"and unlinked");

        // 7. The API half. Without a key the page must say so rather than fail.
        NSDictionary *installProject = nil, *browserProject = nil;
        if (!liveKey.length) {
            LiveSkip(@"live CurseForge search, Discover, API install and update - set WK_LIVE_API_KEY");
        } else {
            TKCurseForgeClient *client = [[TKCurseForgeClient alloc] initWithAPIKey:liveKey];
            __block NSDictionary *search = nil;
            __block NSError *searchError = nil;
            [client browseModsWithQuery:@"details" sortField:TKCurseForgeDefaultSortField() sortOrder:@"desc"
                             categoryID:nil gameVersion:@"1.60.1" classID:nil index:0
                             completion:^(id value, NSError *error) {
                searchError = error;
                search = [value isKindOfClass:NSDictionary.class] ? value : nil;
            }];
            LiveWait(30.0, ^BOOL { return search != nil || searchError != nil; });
            LiveCheck(searchError == nil && search != nil, @"the live API answers a search with the stored key");
            NSArray *projects = [search[@"data"] isKindOfClass:NSArray.class] ? search[@"data"] : @[];
            LiveCheck(projects.count > 0, @"and returns projects for it");

            // Browse, drawn for real.
            [page performSelector:@selector(browse)];
            LiveWait(30.0, ^BOOL { return ((NSArray *)[page valueForKey:@"_results"]).count > 0; });
            NSArray *results = [page valueForKey:@"_results"];
            LiveCheck(results.count > 0, @"Browse draws the live results");
            capture(@"live-hub-browse");

            // Discover, drawn for real: three lists, fetched together.
            [page selectTab:TKAddonHubTabDiscover];
            [page fetchDiscover];
            LiveWait(45.0, ^BOOL { return ((NSArray *)[page valueForKey:@"_discoverSections"]).count > 0; });
            LiveCheck(((NSArray *)[page valueForKey:@"_discoverSections"]).count > 0, @"Discover draws live sections");
            capture(@"live-hub-discover");
            [page selectTab:TKAddonHubTabMyAddOns];

            installProject = LiveFirstProject(projects, 24u * 1024 * 1024);
            LiveCheck(installProject != nil, @"a project with an installable file was found");
            browserProject = installProject;
            for (NSDictionary *project in projects) {
                if (project == installProject) continue;
                TKCurseForgeFileCandidate *candidate = TKCurseForgeChooseFile(project[@"latestFiles"], @"1.60.1");
                NSString *url = [candidate.file[@"downloadUrl"] isKindOfClass:NSString.class] ? candidate.file[@"downloadUrl"] : nil;
                if (url.length && LiveSlug(project).length) { browserProject = project; break; }
            }

            // API install: a real download from the CDN, through the store's transaction.
            if (installProject) {
                NSUInteger before = store.records.count;
                NSNumber *projectID = installProject[@"id"];
                [page installMod:installProject];
                LiveWait(30.0, ^BOOL {
                    for (TKAddonRecord *record in store.records)
                        if ([record.provider[TKAddonProviderProjectID] isEqual:projectID]) return YES;
                    return NO;
                });
                TKAddonRecord *installed = nil;
                for (TKAddonRecord *record in store.records)
                    if ([record.provider[TKAddonProviderProjectID] isEqual:projectID]) installed = record;
                LiveCheck(installed != nil, @"an API install lands in the list");
                LiveCheck(installed && [installed.provenance isEqual:TKAddonProvenanceAPI], @"recorded as an API install");
                LiveCheck(installed && installed.digest.length == 64, @"with the downloaded archive's digest");
                LiveCheck(installed && installed.provider[TKAddonProviderFileID] != nil, @"and the release identity");
                capture(@"live-hub-myaddons-installed");

                // Its update state, from the live API, for real.
                [page checkForUpdates];
                LiveWait(60.0, ^BOOL {
                    TKAddonUpdateResult result = installed ? [page updateResultForRecord:installed] : TKAddonUpdateResultChecking;
                    return result != TKAddonUpdateResultChecking;
                });
                LiveCheck(installed && [page updateResultForRecord:installed] == TKAddonUpdateResultUpToDate,
                          @"the freshly installed package reads Up to date against the live API");
                (void)before;
            }

            // Link the on-disk folder to a real project, then update it for real.
            if (installProject && handMade) {
                NSDictionary *provider = @{ TKAddonProviderKind: @"curseforge",
                                            TKAddonProviderProjectID: installProject[@"id"],
                                            TKAddonProviderProjectSlug: LiveSlug(installProject) ?: @"",
                                            TKAddonProviderProjectName: installProject[@"name"] ?: @"" };
                NSError *linkError = nil;
                LiveCheck([store linkRecord:handMade provider:provider provenance:TKAddonProvenanceUnmanaged error:&linkError],
                          @"Link project records the project for the on-disk folder");
                [page performSelector:@selector(reloadAddons)];
                TKAddonRecord *relinked = nil;
                for (TKAddonRecord *record in store.records) if ([record.identifier isEqual:@"HandMade"]) relinked = record;
                LiveCheck(relinked && relinked.linked, @"and the row is linked afterwards");
                [page checkForUpdates];
                LiveWait(60.0, ^BOOL {
                    return [page updateResultForRecord:relinked] != TKAddonUpdateResultChecking;
                });
                LiveCheck([page updateResultForRecord:relinked] == TKAddonUpdateResultUpdateAvailable,
                          @"a linked folder with no recorded release shows a real update");
                capture(@"live-hub-update-available");
            }

            // The in-app browser: a real page, then a real download through WKDownload.
            NSString *slug = browserProject ? LiveSlug(browserProject) : nil;
            TKAddonBrowserHandoff *handoff = [TKAddonBrowserHandoff new];
            handoff.projectID = browserProject[@"id"] ?: @0;
            handoff.projectSlug = slug;
            handoff.projectName = browserProject[@"name"];
            TKCurseForgeFileCandidate *browserCandidate = browserProject ? TKCurseForgeChooseFile(browserProject[@"latestFiles"], @"1.60.1") : nil;
            NSString *archiveURL = [browserCandidate.file[@"downloadUrl"] isKindOfClass:NSString.class]
                ? browserCandidate.file[@"downloadUrl"] : nil;
            LiveCheck(handoff.projectURL != nil, @"the handoff names a real project page");
            if (handoff.projectURL) {
                [page presentHandoff:handoff forRecord:nil];
                __block WKWebView *web = nil;
                LiveWait(8.0, ^BOOL {
                    UIViewController *top = page.presentedViewController;
                    if (![top isKindOfClass:UINavigationController.class]) return NO;
                    UIViewController *browser = ((UINavigationController *)top).topViewController;
                    if (![browser isKindOfClass:TKWoWAddonBrowserViewController.class]) return NO;
                    web = [browser valueForKey:@"_webView"];
                    return web != nil && !web.isLoading && web.title.length > 0;
                });
                LiveCheck(web != nil && web.title.length > 0, @"the in-app browser loads the real project page");
                capture(@"live-hub-browser");
                if (web && archiveURL.length) {
                    NSUInteger before = store.records.count;
                    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:archiveURL]]];
                    LiveWait(180.0, ^BOOL {
                        if (store.records.count > before) return YES;
                        for (TKAddonRecord *record in store.records)
                            if ([record.provenance isEqual:TKAddonProvenanceBrowser]) return YES;
                        return NO;
                    });
                    LiveCheck(store.records.count > before,
                              @"a real archive downloaded in the in-app browser is installed");
                    BOOL browserProvenance = NO;
                    for (TKAddonRecord *record in store.records)
                        if ([record.provenance isEqual:TKAddonProvenanceBrowser]) browserProvenance = YES;
                    LiveCheck(browserProvenance, @"and recorded as an in-app browser install");
                } else {
                    LiveSkip(@"the in-app browser download - that project hands no archive URL to the API");
                }
                // The host boundary, live: an archive from anywhere else is refused, not installed.
                if (web) {
                    NSUInteger before = store.records.count;
                    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/evil.zip"]]];
                    LivePump(3.0);
                    LiveCheck(store.records.count == before, @"an archive from an untrusted host installs nothing");
                }
            }
        }

        // 7b. The in-app browser, live, with no key: a real public project page in WebKit, and a
        //     real archive request from a host this app does not trust.
        {
            TKAddonBrowserHandoff *handoff = [TKAddonBrowserHandoff new];
            handoff.projectID = @61284;
            handoff.projectSlug = @"details-damage-meter";
            handoff.projectName = @"Details! Damage Meter";
            LiveCheck(handoff.projectURL != nil, @"a public project page is addressable");
            [page presentHandoff:handoff forRecord:nil];
            __block WKWebView *web = nil;
            LiveWait(45.0, ^BOOL {
                UIViewController *top = page.presentedViewController;
                if (![top isKindOfClass:UINavigationController.class]) return NO;
                UIViewController *browser = ((UINavigationController *)top).topViewController;
                if (![browser isKindOfClass:TKWoWAddonBrowserViewController.class]) return NO;
                web = [browser valueForKey:@"_webView"];
                return web != nil && web.URL != nil && !web.isLoading;
            });
            LiveCheck(web != nil && [web.URL.host hasSuffix:@"curseforge.com"],
                      @"the in-app browser navigates the real CurseForge project page");
            // What the site served is recorded, not graded: a site is free to answer a WebKit
            // client however it likes, and a run that called that a pass or a failure of ours
            // would be claiming something about CurseForge instead of about this app.
            if (web) {
                __block NSString *probe = nil;
                [web evaluateJavaScript:@"document.title + '|' + document.documentElement.outerHTML.length"
                      completionHandler:^(id value, NSError *error) {
                    probe = error ? [NSString stringWithFormat:@"error %@", @(error.code)] : [value description];
                }];
                LiveWait(6.0, ^BOOL { return probe != nil; });
                LiveReport(@"INFO", [NSString stringWithFormat:@"site answered: %@ (host %@, title %@)",
                                     probe ?: @"(no answer)", web.URL.host ?: @"(none)",
                                     web.title.length ? web.title : @"(none)"]);
                // The document arrives before it is painted; the capture waits for the paint so
                // the picture is the page rather than the ink behind it.
                LivePump(3.0);
                capture(@"live-hub-browser");
            }
            // Whether the simulator's WebKit can render anything at all, so a blank page can be
            // told apart from a site that refuses this client.
            if (web) {
                // A web view renders in another process, so an in-process capture cannot show its
                // page. The run says it has one ready and waits for the shell to photograph the
                // screen with simctl, which is the frame a person would see.
                NSString *ready = [documents stringByAppendingPathComponent:@"browser-ready"];
                NSString *taken = [documents stringByAppendingPathComponent:@"browser-shot-taken"];
                [NSFileManager.defaultManager removeItemAtPath:taken error:NULL];
                // The site paints after its document arrives, and the sheet finishes animating
                // under it; a frame taken at the wrong moment is the launch colour, not the page.
                LivePump(6.0);
                [@"" writeToFile:ready atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                LiveWait(20.0, ^BOOL { return [NSFileManager.defaultManager fileExistsAtPath:taken]; });
                [NSFileManager.defaultManager removeItemAtPath:ready error:NULL];
                LiveCheck(YES, @"the live page was on screen for the device screenshot");
                __block BOOL reached = NO;
                [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/"]]];
                LiveWait(30.0, ^BOOL {
                    reached = !web.isLoading && [web.URL.host hasSuffix:@"example.com"] && web.title.length > 0;
                    return reached;
                });
                // Reported, not graded: this only exists to tell a simulator-level rendering
                // failure apart from a site that answers oddly, and neither is this app's to pass
                // or fail. The CurseForge navigation above is the check that matters.
                LiveReport(@"INFO", [NSString stringWithFormat:@"plain page: %@ (title %@)",
                                     reached ? @"rendered" : @"did not render",
                                     web.title.length ? web.title : @"(none)"]);
            }
            if (web) {
                NSUInteger before = store.records.count;
                [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/evil.zip"]]];
                LivePump(4.0);
                LiveCheck(store.records.count == before, @"an archive from an untrusted host installs nothing");
            }
            // Whatever the browser left up comes down, so the rest of the run has a clean page.
            UIViewController *top = page.presentedViewController;
            if (top) [top dismissViewControllerAnimated:NO completion:nil];
            UIViewController *alert = page.presentedViewController;
            if (alert) [alert dismissViewControllerAnimated:NO completion:nil];
            LivePump(0.5);
        }

        // 8. Update All: started and cancelled by the player.
        if (handMade && [page updateResultForRecord:handMade] == TKAddonUpdateResultUpdateAvailable) {
            [page runBulkUpdate:@[handMade]];
            LivePump(0.4);
            BOOL wasUpdating = [[page valueForKey:@"bulkUpdating"] boolValue];
            [page cancelBulkUpdate];
            LiveCheck(wasUpdating || ![[page valueForKey:@"bulkUpdating"] boolValue],
                      @"Update All starts and can be cancelled");
        } else {
            LiveSkip(@"Update All cancellation - nothing was eligible to update");
        }

        // 9. Relaunch: a second page over the same directory reads the same words back.
        NSString *persistedBefore = handMade ? handMade.lastUpdateState : nil;
        TKWoWAddonManagerViewController *second = [[TKWoWAddonManagerViewController alloc]
            initWithAddOnsDirectory:addons edition:@"Forever"];
        [second loadViewIfNeeded];
        TKAddonRecord *reread = nil;
        for (TKAddonRecord *record in ((TKAddonStore *)[second valueForKey:@"_store"]).records)
            if ([record.identifier isEqual:@"HandMade"]) reread = record;
        LiveCheck(reread != nil, @"the package is still there on the next launch");
        LiveCheck(persistedBefore == nil || [reread.lastUpdateState isEqual:persistedBefore],
                  @"and its last update word came back with it");
        LiveCheck(((TKAddonStore *)[second valueForKey:@"_store"]).manifestFormat == 3,
                  @"and the manifest is still format 3");

        // 10. Backup and restore, through the launcher's own archive, which carries Interface/.
        NSError *uiError = nil;
        NSString *snapshot = [TKForeverUI createUIBackupInWorkingDirectory:working edition:TKForeverUIEdition error:&uiError];
        LiveCheck(snapshot.length > 0, @"the launcher backs the installation up");
        if (snapshot.length) {
            NSString *victim = [addons stringByAppendingPathComponent:@"HandMade"];
            [NSFileManager.defaultManager removeItemAtPath:victim error:NULL];
            LiveCheck(![NSFileManager.defaultManager fileExistsAtPath:victim], @"an add-on folder is removed by hand");
            NSError *restoreError = nil;
            LiveCheck([TKForeverUI restoreUIBackupNamed:snapshot inWorkingDirectory:working
                                                edition:TKForeverUIEdition error:&restoreError],
                      @"the snapshot restores");
            LiveCheck([NSFileManager.defaultManager fileExistsAtPath:[victim stringByAppendingPathComponent:@"HandMade.toc"]],
                      @"and the add-on folder is back");
            TKWoWAddonManagerViewController *third = [[TKWoWAddonManagerViewController alloc]
                initWithAddOnsDirectory:addons edition:@"Forever"];
            [third loadViewIfNeeded];
            TKAddonStore *reopened = [third valueForKey:@"_store"];
            LiveCheck(reopened.records.count > 1, @"and the store reads its packages again");
            LiveCheck(reopened.manifestFormat == 3, @"with its manifest intact");
        }

        // 11. The boundary: the key is not in the log and no addon-hub line carries a URL.
        NSString *log = [NSString stringWithContentsOfFile:WKLogPath() encoding:NSUTF8StringEncoding error:NULL] ?: @"";
        if (liveKey.length)
            LiveCheck([log rangeOfString:liveKey].location == NSNotFound, @"the API key never reaches the log");
        NSInteger hubLines = 0, dirtyLines = 0;
        for (NSString *line in [log componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            if ([line rangeOfString:@"[addon-hub]"].location == NSNotFound) continue;
            hubLines += 1;
            if ([line rangeOfString:@"http"].location != NSNotFound) dirtyLines += 1;
        }
        LiveCheck(hubLines > 0, @"the log carries addon-hub events");
        LiveCheck(dirtyLines == 0, @"and not one of them contains a URL");

        printf("ADDON HUB LIVE %s: %ld passed, %ld failed, %ld not run (%s)\n",
               liveFailed == 0 ? "PASS" : "FAIL", (long)livePassed, (long)liveFailed, (long)liveSkipped,
               liveKey.length ? "API key supplied" : "no API key");
        return liveFailed == 0;
    }
}
