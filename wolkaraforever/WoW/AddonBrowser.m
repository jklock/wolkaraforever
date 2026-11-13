#import "AddonBrowser.h"
#import "AddonHubLog.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"
#import <WebKit/WebKit.h>

@implementation TKAddonBrowserHandoff

- (NSURL *)projectURL {
    NSString *slug = [self.projectSlug isKindOfClass:NSString.class] ? self.projectSlug : nil;
    // A slug is the only thing that identifies one project's page. A numeric id is not a URL
    // CurseForge resolves, and a search for the name would be a different page that merely looks
    // similar - which is exactly the mistake the plan forbids.
    if (!slug.length) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"];
    if ([slug rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return nil;
    // The file list, because the player is here to pick the release they will install.
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.curseforge.com/wow/addons/%@/files", slug]];
}

@end

@interface TKWoWAddonBrowserViewController () <WKNavigationDelegate, WKDownloadDelegate>
@end

@implementation TKWoWAddonBrowserViewController {
    WKWebView *_webView;
    UIActivityIndicatorView *_spinner;
    UILabel *_statusLabel;
    TKAddonBrowserHandoff *_handoff;
    // Set once the player has been told the page could not be opened, so the sheet does not
    // report the same refusal twice.
    BOOL _refused;
    BOOL _delivered;
    // Where the archive is being written. WKDownload does not hand its destination back, so the
    // delegate remembers the one directory it created.
    NSURL *_downloadDestination;
}

+ (NSArray<NSString *> *)trustedHosts {
    return @[@"curseforge.com", @".curseforge.com", @".forgecdn.net", @"mediafilez.forgecdn.net"];
}

+ (BOOL)isTrustedArchiveURL:(NSURL *)url {
    if (![url isKindOfClass:NSURL.class]) return NO;
    if (![url.scheme.lowercaseString isEqual:@"https"]) return NO;
    NSString *host = url.host.lowercaseString;
    if (!host.length) return NO;
    if ([host isEqual:@"curseforge.com"]) return YES;
    if ([host hasSuffix:@".curseforge.com"]) return YES;
    if ([host hasSuffix:@".forgecdn.net"]) return YES;
    return NO;
}

- (instancetype)initWithHandoff:(TKAddonBrowserHandoff *)handoff {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _handoff = handoff;
    self.title = WKLocalized(@"addons.browser.title");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = WKInk();
    // The bar belongs to the navigation controller, so it needs the same treatment: this sheet
    // was arriving with a white bar and near-black title over a navy page.
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = WKPanel();
    appearance.titleTextAttributes = @{ NSForegroundColorAttributeName: [UIColor colorWithWhite:0.96 alpha:1] };
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.tintColor = WKGold();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:WKLocalized(@"common.done") style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem.tintColor = WKGold();
    self.navigationItem.leftBarButtonItem.accessibilityIdentifier = @"wow.addons.browser.close";

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    // The site's own session, in WebKit's persistent store, exactly as a normal web view would
    // have. The app never reads it: no cookie store is touched, nothing is exported, and the
    // download that comes back is a file, not a credential.
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _webView.translatesAutoresizingMaskIntoConstraints = NO;
    _webView.navigationDelegate = self;
    _webView.backgroundColor = WKInk();
    _webView.scrollView.backgroundColor = WKInk();
    _webView.accessibilityIdentifier = @"wow.addons.browser.web";
    [self.view addSubview:_webView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.color = WKGold();
    _spinner.accessibilityIdentifier = @"wow.addons.browser.spinner";
    [_spinner startAnimating];
    [self.view addSubview:_spinner];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    _statusLabel.numberOfLines = 2;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = WKLocalized(@"addons.browser.loading");
    _statusLabel.accessibilityIdentifier = @"wow.addons.browser.status";
    [self.view addSubview:_statusLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_webView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_webView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_webView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_webView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [_spinner.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [_statusLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:10],
    ]];

    NSURL *page = [_handoff projectURL];
    if (!page) {
        // No page this app can honestly call *that* project's page. Say so instead of opening a
        // search that would let the player install something else under this identity.
        [self refuse:@"addons.browser.noPage"];
        return;
    }
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"opened",
        TKAddonHubKeyIdentifier: _handoff.projectSlug, TKAddonHubKeyAction: @"browser" });
    [_webView loadRequest:[NSURLRequest requestWithURL:page]];
}

- (void)close {
    if (_delivered) return;
    if (self.onCancel) self.onCancel(@"addons.browser.cancelled");
}

- (void)refuse:(NSString *)reasonKey {
    if (_refused) return;
    _refused = YES;
    [_spinner stopAnimating];
    _statusLabel.text = WKLocalized(reasonKey);
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"refused",
        TKAddonHubKeyReason: @"missing-project-page" });
    if (self.onCancel) self.onCancel(reasonKey);
}

#pragma mark - Navigation

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView; (void)navigation;
    [_spinner stopAnimating];
    _statusLabel.hidden = YES;
    _statusLabel.text = nil;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView; (void)navigation; (void)error;
    [_spinner stopAnimating];
    _statusLabel.hidden = NO;
    _statusLabel.text = WKLocalized(@"addons.browser.offline");
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    NSURL *url = navigationAction.request.URL;
    // The player clicked a download link, or the page asked for one directly. Only an archive on
    // a trusted host becomes a file; a link to anywhere else is a navigation, not an install.
    BOOL looksLikeArchive = [[url.path lowercaseString] hasSuffix:@".zip"] || navigationAction.shouldPerformDownload;
    if (looksLikeArchive) {
        if ([TKWoWAddonBrowserViewController isTrustedArchiveURL:url]) {
            decisionHandler(WKNavigationActionPolicyDownload);
            return;
        }
        TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"rejected",
            TKAddonHubKeyReason: @"untrusted-host" });
        if (self.onCancel) self.onCancel(@"addons.browser.untrusted");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    (void)webView;
    if (!navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyDownload);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

#pragma mark - Download

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response
suggestedFilename:(NSString *)suggestedFilename
completionHandler:(void (^)(NSURL *_Nullable))completionHandler {
    NSURL *origin = response.URL;
    if (![TKWoWAddonBrowserViewController isTrustedArchiveURL:origin]) {
        TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"rejected",
            TKAddonHubKeyReason: @"untrusted-archive" });
        if (self.onCancel) self.onCancel(@"addons.browser.untrusted");
        completionHandler(nil);
        return;
    }
    NSString *name = suggestedFilename;
    if (![name.lowercaseString hasSuffix:@".zip"] || name.length > 200) name = @"addon.zip";
    // A fresh directory per download, so the file the installer receives is the only thing in it
    // and cannot be swapped for something else between the check and the import.
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"addon-hub-download-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
                              attributes:nil error:NULL];
    NSURL *destination = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
    _downloadDestination = destination;
    _statusLabel.hidden = NO;
    _statusLabel.text = WKLocalized(@"addons.browser.downloading");
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"downloading",
        TKAddonHubKeyIdentifier: _handoff.projectSlug, TKAddonHubKeyAction: @"browser" });
    completionHandler(destination);
}

- (void)downloadDidFinish:(WKDownload *)download {
    (void)download;
    [_spinner stopAnimating];
    NSURL *destination = _downloadDestination;
    if (!destination) {
        TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"failed",
            TKAddonHubKeyReason: @"no-file" });
        if (self.onCancel) self.onCancel(@"addons.browser.failed");
        return;
    }
    _delivered = YES;
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"downloaded",
        TKAddonHubKeyIdentifier: _handoff.projectSlug, TKAddonHubKeyAction: @"browser" });
    if (self.onDownload) self.onDownload(destination);
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error
    resumeData:(NSData *)resumeData {
    (void)download; (void)error; (void)resumeData;
    [_spinner stopAnimating];
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"failed",
        TKAddonHubKeyReason: @"download-error" });
    if (self.onCancel) self.onCancel(@"addons.browser.failed");
}

@end
