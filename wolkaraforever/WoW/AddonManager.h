#import <UIKit/UIKit.h>

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

// Whether the CurseForge list has room for all seven columns at this width.
//
// The columns are fixed widths - 480 points of them, plus spacing, artwork and
// the project's name - and the browser ships them all on a wide page. Deciding
// this from the horizontal size class was wrong: an iPad form sheet stays
// *regular* however narrow it is, so a portrait sheet drew a row wider than the
// list. Measured in the fixture on 2026-10-22: the page is 540 points wide in
// portrait and the full column set asks for 586 before the name has any room.
BOOL TKAddonRowsAreCompact(CGFloat width);

@interface TKWoWAddonManagerViewController : UITableViewController
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition;
// Starts on Browse rather than Installed, for the development preview and for
// a future direct link from the home page.
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition browse:(BOOL)browse;
@end

NS_ASSUME_NONNULL_END
