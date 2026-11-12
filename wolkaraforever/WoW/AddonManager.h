#import <UIKit/UIKit.h>
#import "AddonStore.h"

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

@interface TKWoWAddonManagerViewController : UITableViewController
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition;
// Starts on Browse rather than Installed, for the development preview and for
// a future direct link from the home page.
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition browse:(BOOL)browse;
// The page the home page's recommendation row opens. It is additive: `None` is the page this
// class has always built, byte for byte.
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition
                         recommendation:(TKAddonRecommendation)recommendation;
@property(nonatomic, readonly) TKAddonRecommendation recommendation;
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

NS_ASSUME_NONNULL_END
