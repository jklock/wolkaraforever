#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// One acquisition, carried into the browser.
//
// The identity comes from the action the player pressed - a native project row, or a package's
// own "needs browser confirmation" action - never from the page the browser happens to be on
// when a ZIP arrives. That is what stops a download from being attached to the wrong project,
// and it is why the release identity travels with the handoff rather than being re-derived.
@interface TKAddonBrowserHandoff : NSObject
// The CurseForge project this handoff is for. Required: the browser refuses to open without one.
@property(nonatomic, copy) NSNumber *projectID;
// The release the native row named, when it named one.
@property(nonatomic, copy, nullable) NSNumber *fileID;
@property(nonatomic, copy, nullable) NSString *projectName;
// The project's own slug, from the API's `links.websiteUrl`. Without one there is no page this
// app can claim is *that* project's page, so the handoff refuses rather than opening a search.
@property(nonatomic, copy, nullable) NSString *projectSlug;
@property(nonatomic, copy, nullable) NSString *releaseName;

// The page to open: the project's own file list, so the player chooses the release.
- (nullable NSURL *)projectURL;
@end

// The in-app CurseForge page.
//
// It is acquisition, not catalog: it renders normal site pages, may keep the site's own login in
// WebKit's persistent store, and never exposes or copies a cookie, a header or a token. It is
// never the Add-ons home screen, and it refuses to open an archive from any host it was not told
// to trust. Safari is never opened.
@interface TKWoWAddonBrowserViewController : UIViewController
- (instancetype)initWithHandoff:(TKAddonBrowserHandoff *)handoff;
// Called once, on the main queue, when a trusted archive has finished downloading. The URL is a
// temporary file the caller owns: it is the only copy, and the caller must install or delete it.
@property(nonatomic, copy, nullable) void (^onDownload)(NSURL *archive);
// Called when the player leaves, or when the browser refuses a download. `reason` is a
// localization key, never a URL.
@property(nonatomic, copy, nullable) void (^onCancel)(NSString *reasonKey);

// Whether the app trusts this URL to deliver an add-on archive: HTTPS, and a host that is
// CurseForge's or its CDN's. Exposed so a fixture can assert the boundary without a network.
+ (BOOL)isTrustedArchiveURL:(nullable NSURL *)url;
// The hosts a download may come from, as a comma-free set for a log line that stays one field.
+ (NSArray<NSString *> *)trustedHosts;
@end

NS_ASSUME_NONNULL_END
