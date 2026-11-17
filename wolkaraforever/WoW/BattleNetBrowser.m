#import "BattleNetBrowser.h"
#import "BattleNetSession.h"
#import "../App/WKLocalization.h"
#import <WebKit/WebKit.h>

@interface TKBattleNetBrowser () <WKNavigationDelegate>
@end

@implementation TKBattleNetBrowser {
    NSString *_region;
    NSString *_locale;
    WKWebView *_web;
    BOOL _finished;
    BOOL _trustedMainNavigation;
    WKNavigation *_navigation;
    NSTimer *_deadline;
}

+ (WKWebsiteDataStore *)signInDataStore {
    // Isolated from add-on browsing. WebKit owns the cookies; the launcher never
    // reads or exports their values. Keep the identifier stable across launches.
    NSUUID *identifier=[[NSUUID alloc] initWithUUIDString:@"CED7AF62-60E2-4AA2-B14F-39C844EAA482"];
    return [WKWebsiteDataStore dataStoreForIdentifier:identifier];
}

+ (void)clearSavedSignInWithCompletion:(void (^)(void))completion {
    [TKBattleNetSession clear];
    [[self signInDataStore] removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes
                              modifiedSince:NSDate.distantPast completionHandler:completion];
}

- (instancetype)initWithRegion:(NSString *)region locale:(NSString *)locale {
    if ((self=[super init])) {
        _region=[region.lowercaseString copy];
        _locale=[locale copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=WKLocalized(@"login.title");
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    // No injected scripts, password storage or JavaScript bridge.
    configuration.websiteDataStore=[TKBattleNetBrowser signInDataStore];
    _web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _web.navigationDelegate=self;
    _web.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_web];
    [NSLayoutConstraint activateConstraints:@[
        [_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_web.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    if (![@[@"us", @"eu", @"kr", @"tw"] containsObject:_region]) {
        [self cancel];
        return;
    }
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:
        @"https://%@.battle.net/login/en/?externalChallenge=login&app=WoW", _region]];
    self.navigationItem.prompt=url.host;
    [_web loadRequest:[NSURLRequest requestWithURL:url]];
    __weak typeof(self) weakSelf=self;
    _deadline=[NSTimer scheduledTimerWithTimeInterval:600 repeats:NO block:^(__unused NSTimer *timer) {
        [weakSelf cancel];
    }];
}

- (void)finish:(BOOL)received {
    if (_finished) return;
    _finished=YES;
    [_deadline invalidate];
    _deadline=nil;
    _navigation=nil;
    _web.navigationDelegate=nil;
    [_web stopLoading];
    [_web removeFromSuperview];
    _web=nil;
    if (!received) [TKBattleNetSession clear];
    void (^completion)(BOOL)=self.completion;
    self.completion=nil;
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(received);
    }];
}

- (void)cancel { [self finish:NO]; }

- (void)webView:(__unused WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (_finished) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *url=action.request.URL;
    NSString *ticket=TKBattleNetCallbackTicket(url);
    if (ticket) {
        // A callback must originate in the main frame of an approved sign-in page.
        WKSecurityOrigin *origin=action.sourceFrame.securityOrigin;
        NSURLComponents *source=[NSURLComponents new];
        source.scheme=origin.protocol;
        source.host=origin.host;
        if (origin.port) source.port=@(origin.port);
        BOOL trusted=action.sourceFrame.mainFrame && action.targetFrame.mainFrame &&
                     TKBattleNetTrustedURL(source.URL);
        // A rejected navigation must never become an accepted failure callback.
        _trustedMainNavigation=NO;
        decisionHandler(WKNavigationActionPolicyCancel);
        if (trusted) [self finish:[TKBattleNetSession acceptTicket:ticket region:_region locale:_locale]];
        return;
    }
    // Subframes (including CAPTCHA providers) follow WebKit's normal rules.
    // Top-level navigation stays on Blizzard's HTTPS sites.
    if (action.targetFrame.mainFrame || !action.targetFrame) {
        _trustedMainNavigation=TKBattleNetTrustedURL(url);
        if (!_trustedMainNavigation) {
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
        if (!action.targetFrame) {
            decisionHandler(WKNavigationActionPolicyCancel);
            [_web loadRequest:action.request];
            return;
        }
        self.navigationItem.prompt=url.host;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(__unused WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    _navigation=navigation;
}

- (BOOL)acceptMainFrameRedirect:(NSURL *)url navigation:(WKNavigation *)navigation {
    // WebKit can reject port zero before a navigation action is delivered. Only
    // accept a redirect/error for the current, approved main-frame navigation.
    if (_finished || !_trustedMainNavigation || !navigation || navigation!=_navigation) return NO;
    NSString *ticket=TKBattleNetCallbackTicket(url);
    if (!ticket) return NO;
    [self finish:[TKBattleNetSession acceptTicket:ticket region:_region locale:_locale]];
    return YES;
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    if ([self acceptMainFrameRedirect:webView.URL navigation:navigation]) [webView stopLoading];
}

- (void)webView:(__unused WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    if (_finished || ([error.domain isEqual:NSURLErrorDomain] && error.code==NSURLErrorCancelled)) return;
    id failingURL=error.userInfo[NSURLErrorFailingURLErrorKey];
    if ([failingURL isKindOfClass:NSURL.class] &&
        [self acceptMainFrameRedirect:failingURL navigation:navigation]) return;
    // NSError descriptions can contain credential-bearing URLs; never show/log them.
    self.navigationItem.prompt=WKLocalized(@"login.failed");
}

- (void)dealloc { [_deadline invalidate]; }
@end
