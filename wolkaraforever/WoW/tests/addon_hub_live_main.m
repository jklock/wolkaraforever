// The live Add-on Hub app: a window, a scene and nothing else. It calls the live run and exits
// with the verdict, so the shell script that launched it can decide.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "addon_hub_live.h"
#import "../launcher/App/WolkaraForeverLog.h"

// A web view draws in another process, so `drawViewHierarchyInRect` renders the ink behind it and
// not the page. A capture of the browser is therefore the web view's own snapshot; everything else
// is the window as drawn.
static WKWebView *FindWebView(UIView *view) {
    if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
    for (UIView *child in view.subviews) {
        WKWebView *found = FindWebView(child);
        if (found) return found;
    }
    return nil;
}

static UIImage *SnapshotWebView(WKWebView *web) {
    if (!web) return nil;
    __block UIImage *image = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    WKSnapshotConfiguration *configuration = [WKSnapshotConfiguration new];
    configuration.rect = web.bounds;
    [web takeSnapshotWithConfiguration:configuration completionHandler:^(UIImage *snapshot, NSError *error) {
        (void)error;
        image = snapshot;
        dispatch_semaphore_signal(done);
    }];
    // Bounded. A snapshot that never answers must not hang the whole run, and the window capture
    // below is an honest second best.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4.0];
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) != 0) {
        if (deadline.timeIntervalSinceNow <= 0) return nil;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return image;
}

static UIImage *RenderWindow(UIWindow *window) {
    [window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
}

@interface TKAddonHubLiveScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@end

@implementation TKAddonHubLiveScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    WKLogStart();
    WKLog("test", @"add-on hub live run starting");
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    // A budget, not a measurement: the longest live pass - search, three installs, a browser
    // download, a cancel and the launcher's own restore - measured under three minutes, so a run
    // still going after this is stuck rather than slow, and says so instead of hanging.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 420 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        fprintf(stderr, "ADDON HUB LIVE FAIL: timed out\n");
        _Exit(2);
    });
    // The run is synchronous on purpose: it drives the page's own enter points, waits for the
    // queues those start, and then reports. There is nothing here for a person to press.
    BOOL ok = TKAddonHubLiveRun(self.window, ^(NSString *name) {
        UIImage *image = SnapshotWebView(FindWebView(self.window));
        if (!image) image = RenderWindow(self.window);
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [documents stringByAppendingPathComponent:[name stringByAppendingString:@".png"]];
        BOOL written = [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        WKLog("test", @"capture %@ %@", name, written ? @"written" : @"failed");
    });
    fflush(stdout);
    _Exit(ok ? 0 : 1);
}
@end

@interface TKAddonHubLiveApp : UIResponder <UIApplicationDelegate>
@end

@implementation TKAddonHubLiveApp
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
    options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc]
        initWithName:@"Live" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = TKAddonHubLiveScene.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TKAddonHubLiveApp.class));
    }
}
