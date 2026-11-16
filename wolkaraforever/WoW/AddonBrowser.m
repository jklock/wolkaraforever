#import "AddonBrowser.h"
#import "AddonHubLog.h"
#import "../App/WolkaraForeverLog.h"
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
    // Open the project's own rendered page. Its visible Download control is the normal
    // no-key browser route; it selects the release and hands the archive to WebKit.
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.curseforge.com/wow/addons/%@", slug]];
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
    BOOL _retriedEmptyPage;
    // WKDownload's delegate is weak. Keep the in-flight object for the complete handoff rather
    // than depending on a transient navigation callback to keep it alive.
    WKDownload *_activeDownload;
    // Where the archive is being written. WKDownload does not hand its destination back, so the
    // delegate remembers the one directory it created.
    NSURL *_downloadDestination;
}

// The browser trace is structural: every callback records its stage and a safe description of
// the request, never a full URL, query, cookie, page title, or response body.
- (NSString *)webRoute:(NSURL *)url {
    NSString *path = url.path.lowercaseString ?: @"";
    if ([path hasSuffix:@".zip"]) return @"archive";
    if ([path containsString:@"/download/"]) return @"download";
    if ([path containsString:@"/files/"]) return @"files";
    if ([path containsString:@"/wow/addons/"]) return @"project";
    return path.length ? @"other" : @"none";
}

- (NSString *)webMIME:(NSString *)MIMEType {
    NSString *mime = MIMEType.lowercaseString ?: @"";
    if ([mime containsString:@"zip"]) return @"zip";
    if ([mime isEqual:@"text/html"] || [mime isEqual:@"application/xhtml+xml"]) return @"html";
    if ([mime hasPrefix:@"image/"]) return @"image";
    if ([mime hasPrefix:@"text/"]) return @"text";
    return mime.length ? @"other" : @"none";
}

- (NSString *)webErrorReason:(NSError *)error {
    if (!error) return @"none";
    if ([error.domain isEqual:NSURLErrorDomain]) return @"url";
    if ([error.domain containsString:@"WebKit"]) return @"webkit";
    return @"other";
}

- (void)logWebAction:(NSString *)action URL:(NSURL *)url response:(NSURLResponse *)response error:(NSError *)error {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ?
        ((NSHTTPURLResponse *)response).statusCode : -1;
    NSMutableDictionary *fields = [@{ TKAddonHubKeyAction: action,
        TKAddonHubKeyHost: url.host.lowercaseString ?: @"none",
        TKAddonHubKeyRoute: [self webRoute:url],
        TKAddonHubKeyMIME: [self webMIME:response.MIMEType],
        TKAddonHubKeyReason: [self webErrorReason:error] } mutableCopy];
    if (status >= 0) fields[TKAddonHubKeyStatus] = @(status);
    if (error) fields[TKAddonHubKeyCode] = @(error.code);
    TKAddonHubLog(TKAddonHubEventWeb, fields);
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

// The browser route deliberately does not ask CurseForge's API for a file identity. The
// rendered Download control already names it, and retaining that identity makes a browser
// install participate in the same later update comparison as an API install.
+ (nullable NSNumber *)fileIDFromCurseForgeURL:(NSURL *)url {
    if (![url isKindOfClass:NSURL.class]) return nil;
    NSString *host = url.host.lowercaseString;
    if (![host isEqual:@"curseforge.com"] && ![host hasSuffix:@".curseforge.com"]) return nil;
    NSArray<NSString *> *parts = url.pathComponents;
    for (NSUInteger index = 0; index + 1 < parts.count; index++) {
        NSString *part = parts[index].lowercaseString;
        if (![part isEqual:@"files"] && ![part isEqual:@"download"]) continue;
        NSString *candidate = parts[index + 1];
        if (!candidate.length || [candidate rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound)
            continue;
        unsigned long long value = candidate.longLongValue;
        if (value > 0 && value <= (unsigned long long)NSIntegerMax) return @(value);
    }
    return nil;
}

- (void)recordSelectedFileFromURL:(NSURL *)url {
    NSNumber *fileID = [TKWoWAddonBrowserViewController fileIDFromCurseForgeURL:url];
    if (fileID) _handoff.fileID = fileID;
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
    // CurseForge's file controls are served on its desktop page. Request that explicitly: a
    // mobile response can complete navigation with an empty document, leaving the player at a
    // page that cannot expose its Download action.
    configuration.defaultWebpagePreferences.preferredContentMode = WKContentModeDesktop;
    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    // CurseForge serves its normal player download controls to Mobile Safari. WKWebView's
    // default application identifier is enough to put its bot gate on the otherwise identical
    // page in the simulator, so identify this user-facing browser as the Safari web view it is.
    _webView.customUserAgent = @"Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
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
    [self logWebAction:@"request" URL:page response:nil error:nil];
    [_webView loadRequest:[NSURLRequest requestWithURL:page]];
}

- (void)close {
    if (_delivered) return;
    [self logWebAction:@"close" URL:_webView.URL response:nil error:nil];
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

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self logWebAction:@"start" URL:webView.URL response:nil error:nil];
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self logWebAction:@"redirect" URL:webView.URL response:nil error:nil];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self logWebAction:@"commit" URL:webView.URL response:nil error:nil];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self logWebAction:@"finish" URL:webView.URL response:nil error:nil];
    [_spinner stopAnimating];
    _statusLabel.hidden = YES;
    _statusLabel.text = nil;
    // iOS Simulator WebKit can report a completed cold navigation with an empty document. Retry
    // once only; repeating indefinitely would turn a server error into a hung browser.
    if (!_retriedEmptyPage) {
        __weak typeof(self) weakSelf = self;
        [_webView evaluateJavaScript:@"(document.title || '') + '|' + (document.documentElement ? document.documentElement.outerHTML.length : 0)"
                   completionHandler:^(id value, NSError *error) {
            typeof(self) self = weakSelf;
            if (!self || error) return;
            NSString *document = [value isKindOfClass:NSString.class] ? [(NSString *)value lowercaseString] : @"";
            // A successful navigation to a bot-verification page is not a completed add-on
            // download. Leave that page visible, but say plainly that nothing was installed.
            // Without this the browser looked finished while its Download action could never
            // reach WKDownload.
            if ([document containsString:@"just a moment"] || [document containsString:@"attention required"] ||
                [document containsString:@"cloudflare"]) {
                WKLog("addons", @"browser download blocked by site verification");
                self->_statusLabel.hidden = NO;
                self->_statusLabel.text = WKLocalized(@"addons.browser.failed");
                return;
            }
            NSInteger separator = [document rangeOfString:@"|"].location;
            NSInteger bytes = separator == NSNotFound ? 0 : [[document substringFromIndex:separator + 1] integerValue];
            if (bytes >= 100) return;
            self->_retriedEmptyPage = YES;
            WKLog("addons", @"browser received an empty document; retrying once");
            [self->_webView reload];
        }];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    [self logWebAction:@"provisional-fail" URL:webView.URL response:nil error:error];
    // CurseForge's rendered Download control first opens its five-second handoff page, then
    // WebKit cancels that page as it changes the navigation into WKDownload. -999 is that
    // expected handoff, not an offline failure; treating it as one is the false error shown
    // over the site's "Downloading…" page.
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    WKLog("addons", @"browser navigation failed domain=%@ code=%ld", error.domain ?: @"?", (long)error.code);
    [_spinner stopAnimating];
    _statusLabel.hidden = NO;
    _statusLabel.text = WKLocalized(@"addons.browser.offline");
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self logWebAction:@"process-terminated" URL:webView.URL response:nil error:nil];
    WKLog("addons", @"browser web-content process terminated");
    [_spinner stopAnimating];
    _statusLabel.hidden = NO;
    _statusLabel.text = WKLocalized(@"addons.browser.failed");
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self logWebAction:@"navigation-fail" URL:webView.URL response:nil error:error];
    [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    NSURL *url = navigationAction.request.URL;
    [self logWebAction:@"action-policy" URL:url response:nil error:nil];
    // This is metadata from the rendered Download control the player pressed. The archive
    // itself still arrives only through WebKit's download callback.
    [self recordSelectedFileFromURL:url];
    // The player clicked a download link, or the page asked for one directly. Only an archive on
    // a trusted host becomes a file; a link to anywhere else is a navigation, not an install.
    BOOL looksLikeArchive = [[url.path lowercaseString] hasSuffix:@".zip"] || navigationAction.shouldPerformDownload;
    if (looksLikeArchive) {
        if ([TKWoWAddonBrowserViewController isTrustedArchiveURL:url]) {
            [self logWebAction:@"action-download-allowed" URL:url response:nil error:nil];
            decisionHandler(WKNavigationActionPolicyDownload);
            return;
        }
        TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"rejected",
            TKAddonHubKeyReason: @"untrusted-host" });
        if (self.onCancel) self.onCancel(@"addons.browser.untrusted");
        [self logWebAction:@"action-rejected" URL:url response:nil error:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    [self logWebAction:@"action-allowed" URL:url response:nil error:nil];
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    (void)webView;
    NSURLResponse *response = navigationResponse.response;
    [self logWebAction:@"response-policy" URL:response.URL response:response error:nil];
    [self recordSelectedFileFromURL:response.URL];
    if (!navigationResponse.canShowMIMEType) {
        [self logWebAction:@"response-download-allowed" URL:response.URL response:response error:nil];
        decisionHandler(WKNavigationResponsePolicyDownload);
        return;
    }
    [self logWebAction:@"response-allowed" URL:response.URL response:response error:nil];
    decisionHandler(WKNavigationResponsePolicyAllow);
}

// WebKit creates the download after the policy callback. It has no delegate until this handoff,
// so omitting either callback leaves a browser download with nowhere to save and no install path.
- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction
didBecomeDownload:(WKDownload *)download {
    (void)webView; (void)navigationAction;
    [self logWebAction:@"action-download" URL:download.originalRequest.URL response:nil error:nil];
    _activeDownload = download;
    download.delegate = self;
}

- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)navigationResponse
didBecomeDownload:(WKDownload *)download {
    (void)webView; (void)navigationResponse;
    [self logWebAction:@"response-download" URL:download.originalRequest.URL
             response:navigationResponse.response error:nil];
    _activeDownload = download;
    download.delegate = self;
}

#pragma mark - Download

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response
suggestedFilename:(NSString *)suggestedFilename
completionHandler:(void (^)(NSURL *_Nullable))completionHandler {
    NSURL *origin = response.URL;
    [self logWebAction:@"destination" URL:origin response:response error:nil];
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
    [self logWebAction:@"download-finished" URL:download.originalRequest.URL response:nil error:nil];
    if (download != _activeDownload) return;
    _activeDownload = nil;
    [_spinner stopAnimating];
    NSURL *destination = _downloadDestination;
    if (_delivered || !destination || ![[NSFileManager defaultManager] fileExistsAtPath:destination.path]) {
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
    [self logWebAction:@"download-failed" URL:download.originalRequest.URL response:nil error:error];
    if (download != _activeDownload) return;
    _activeDownload = nil;
    (void)resumeData;
    [_spinner stopAnimating];
    WKLog("addons", @"browser download failed domain=%@ code=%ld", error.domain ?: @"?", (long)error.code);
    TKAddonHubLog(TKAddonHubEventHandoff, @{ TKAddonHubKeyOutcome: @"failed",
        TKAddonHubKeyReason: @"download-error" });
    if (self.onCancel) self.onCancel(@"addons.browser.failed");
}

@end
