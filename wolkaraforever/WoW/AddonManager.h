#import <UIKit/UIKit.h>
#import "AddonStore.h"
#import "AddonUpdateResolver.h"

NS_ASSUME_NONNULL_BEGIN

// A data-only description of one user-supplied add-on folder. The launcher
// never interprets or modifies the add-on's Lua or game files.
@interface TKWoWAddon : NSObject
@property(nonatomic, readonly, copy) NSString *folder;
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy, nullable) NSString *version;
@property(nonatomic, readonly) NSUInteger fileCount;
@end

// Lists direct child folders of Interface/AddOns. Invalid or unreadable
// folders are skipped so a damaged add-on cannot prevent the manager opening.
NSArray<TKWoWAddon *> *TKWoWAddonsAtDirectory(NSString *directory);

// What a browser row's own action is doing. Part of the row's public contract, because a
// caller (and the fixture) has to be able to say "this project is already installed" without
// guessing from the title.
typedef NS_ENUM(NSInteger, TKAddonInstallState) {
    TKAddonInstallStateIdle = 0,
    TKAddonInstallStateBusy,
    TKAddonInstallStateInstalled,
    TKAddonInstallStateUnavailable,
    TKAddonInstallStateFailed,
    // The project does not hand its archive to the API, so the row's action opens that exact
    // project in the in-app browser. It is not a failure and must not read like one.
    TKAddonInstallStateBrowser,
};

// Whether the CurseForge list has room for all seven columns at this width.
//
// The columns are fixed widths - 480 points of them, plus spacing, artwork and
// the project's name - and the browser ships them all on a wide page. Deciding
// this from the horizontal size class was wrong: an iPad form sheet stays
// *regular* however narrow it is, so a portrait sheet drew a row wider than the
// list. Measured in the fixture on 2026-10-22: the page is 540 points wide in
// portrait and the full column set asks for 586 before the name has any room.
BOOL TKAddonRowsAreCompact(CGFloat width);

// Which recommendation the launcher asked this page to show. It is part of the page's public
// contract because the home page's recommendation row chooses it, and a fixture has to be able
// to say which page it got without reading a private field.
typedef NS_ENUM(NSInteger, TKAddonRecommendation) {
    TKAddonRecommendationNone = 0,
    // iPadOS: the Add-On Manager opens on Browse, filtered to CurseForge project 1733200
    // (Mac-Ever), with the existing explicit key and install flow.
    TKAddonRecommendationMacEver,
    // iOS on Duo: the Add-On Manager opens on Installed with the bundled, verified
    // WolkaraRoue package and its own explicit local Install action.
    TKAddonRecommendationWolkaraRoue,
};

// The three native tabs. My Add-ons is the page's default and the only one that manages
// packages; Discover and Browse are the two ways to acquire another one.
typedef NS_ENUM(NSInteger, TKAddonHubTab) {
    TKAddonHubTabMyAddOns = 0,
    TKAddonHubTabDiscover,
    TKAddonHubTabBrowse,
};

@interface TKWoWAddonManagerViewController : UITableViewController
// What the installed row is showing about one package's update. Chosen by TKAddonUpdateResolve,
// never by the row; every case here has a sentence in the string tables.
typedef NS_ENUM(NSInteger, TKAddonUpdateState) {
    TKAddonUpdateStateNotUpdatable = 0,
    TKAddonUpdateStateUnknown,
    TKAddonUpdateStateUpToDate,
    TKAddonUpdateStateAvailable,
    TKAddonUpdateStateBusy,
    TKAddonUpdateStateFailed,
    TKAddonUpdateStateBrowser,
    TKAddonUpdateStateUnlinked,
    TKAddonUpdateStateUnavailable,
    TKAddonUpdateStateTerminal,
    // Linked package whose provider has not been queried in this page yet.
    TKAddonUpdateStateNotChecked,
};
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition;
// Starts on Browse rather than Installed, for the development preview and for
// a future direct link from the home page.
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition browse:(BOOL)browse;
// The page the home page's recommendation row opens. It is additive: `None` is the page this
// class has always built, byte for byte.
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition
                         recommendation:(TKAddonRecommendation)recommendation;
@property(nonatomic, readonly) TKAddonRecommendation recommendation;
// Which tab is showing. `MyAddOns` is where the page opens; `Browse` is what
// -initWithAddOnsDirectory:edition:browse:YES asks for.
@property(nonatomic, readonly) TKAddonHubTab tab;
- (void)selectTab:(TKAddonHubTab)tab;
// The installed records My Add-ons currently draws, after the search text, the filter and the
// sort have been applied. A control that changes none of those changes nothing here either.
@property(nonatomic, readonly, copy) NSArray<TKAddonRecord *> *visibleRecords;
// What the resolver says about one record. The row, the bulk run and the fixture all ask this
// instead of each keeping their own opinion.
- (TKAddonUpdateResult)updateResultForRecord:(TKAddonRecord *)record;
// That answer in the row's own vocabulary.
- (TKAddonUpdateState)stateForRecord:(TKAddonRecord *)record;
// The snapshot Update all would run: every record with a newer file, in the order the page would
// take them. A browser-confirmation record is in this list, not dropped from it.
- (NSArray<TKAddonRecord *> *)allUpdatableRecords;
- (NSArray<TKAddonRecord *> *)selectedUpdatableRecords;
// The CurseForge project the Mac-Ever recommendation is filtered to (1733200), or nil.
@property(nonatomic, readonly, copy, nullable) NSNumber *recommendedProjectID;
// The bundled WolkaraRoue package, once resolved: `archive` (NSURL), `manifest` (NSURL),
// `release` (NSString) and `sha256` (NSString). A malformed, missing or unexpected package
// resolves to nil plus an error, and the page refuses rather than installing anything.
@property(nonatomic, readonly, copy, nullable) NSDictionary *bundledPackage;
// Where that answer comes from. The app uses the shipped verifier; a fixture may supply the
// same shape so the page can be exercised without the Swift archive library linked in.
@property(nonatomic, copy, nullable) NSDictionary *(^bundledPackageProvider)(NSError **error);
// Resolve the bundled package again (after a language change, or when a fixture changes its
// provider). Safe to call before the view is loaded.
- (void)reloadBundledPackage;

// The actions a managed package offers: disable/restore, pin/unpin, remove, cancel. Exposed so
// the device self-test can assert that removal is reachable without a second pair of hands on
// the iPad; the page presents this same sheet when a row is tapped.
- (UIAlertController *)manageSheetForRecord:(TKAddonRecord *)record;
@end

// The whole add-on folder, as one ZIP and back again.
//
// These are the home page's two add-on file operations and they are the whole of that feature: a
// backup is made because someone pressed Backup Add-ons, and a restore happens because someone
// picked a backup and confirmed. Nothing here runs while a page is open, nothing compares
// versions, and nothing reaches the network.
//
// The archive side is Swift (`TKAddonBackupArchive`, built on the ZIP library the app already
// ships), reached by name exactly as the Forever UI archive is, so a host test that does not
// link Swift still sees the functions and gets a named failure instead of a crash.
FOUNDATION_EXPORT NSString * _Nullable TKAddonBackupCreate(NSString *addOnsDirectory, NSError **error);
FOUNDATION_EXPORT NSArray<NSString *> *TKAddonBackupNames(NSString *addOnsDirectory, NSError **error);
FOUNDATION_EXPORT BOOL TKAddonBackupRestore(NSString *name, NSString *addOnsDirectory, NSError **error);

NS_ASSUME_NONNULL_END
