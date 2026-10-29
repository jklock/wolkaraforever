#import <UIKit/UIKit.h>
#import "../App/AppLibrary.h"
#import "../App/ExecutionMode.h"

NS_ASSUME_NONNULL_BEGIN
@class TKLaunchProgressView;
@interface TKWoWViewController : UIViewController
- (instancetype)initWithLibrary:(TKAppLibrary *)library;
@property(nonatomic, copy, nullable) void (^startApp)(TKApp *app);
@property(nonatomic, copy, nullable) void (^showDiagnostics)(void);
@property(nonatomic) TKExecutionMode executionMode;
@property(nonatomic) BOOL sessionUsed;
// Opening an external page (Download Mac-Ever). Injectable so a test can prove
// the exact URL is requested without a browser opening on the simulator.
@property(nonatomic, copy, nullable) void (^openExternalURL)(NSURL *url);
// The folder the Settings browser would open. Injectable for the same reason:
// a fixture proves the destination without a system file provider.
@property(nonatomic, copy, nullable) void (^openSettingsFolderURL)(NSURL *url);
// The game's add-on folder, opened by the Add-on Directory row. Injectable for
// the same reason as the folder above - it is the same kind of browser, and a
// fixture cannot present one.
@property(nonatomic, copy, nullable) void (^openAddonDirectoryURL)(NSURL *url);
// The folder Restore's file browser would open, holding the backups to pick
// from. Injectable for the same reason as the two above.
@property(nonatomic, copy, nullable) void (^chooseBackupFile)(NSURL *directory);
// The app's own page in Settings, which Toggle Permissions opens. Injectable for
// the same reason again: the system leaves the app to swap to Settings, so a
// fixture that could not intercept it would only be able to prove that the row
// was pressed, not which page it asked for.
@property(nonatomic, copy, nullable) void (^openAppSettingsURL)(NSURL *url);
// Reuse this home screen throughout startup; the runtime retains its execution path.
@property(nonatomic, readonly) UILabel *startupStatusLabel;
@property(nonatomic, readonly) TKLaunchProgressView *launchProgress;
@property(nonatomic, readonly) UIButton *diagnosticsButton;
- (void)beginStartup;
- (void)finishStartupWithMessage:(NSString *)message failed:(BOOL)failed;
// The guest's own window is on screen: the session is running, not loading.
- (void)guestDidStartRunning;
// Development preview: the Add-on Manager, already on Browse. Used by
// tools, never by a normal launch.
- (void)previewAddonBrowser;
@end
NS_ASSUME_NONNULL_END
