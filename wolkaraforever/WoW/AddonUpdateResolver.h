#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What a row can say about one installed package's update, and what its action can do.
//
// This is the whole vocabulary the Add-ons list is allowed to use about an update. It lives in
// its own Foundation-only file so the page, the store and the fixture can ask the same question
// and get the same answer: the previous arrangement had six ad-hoc states spread across the
// view controller, and "needs a browser confirmation" had no state at all - so a package whose
// author does not allow API downloads looked permanently up to date.
typedef NS_ENUM(NSInteger, TKAddonUpdateResult) {
    // Not an update question: the package is disabled or pinned, so nothing will be offered and
    // nothing is checked. The row still manages it.
    TKAddonUpdateResultNotApplicable = 0,
    // The provider has exactly the file this package holds.
    TKAddonUpdateResultUpToDate,
    // The provider has a newer file and this app can download it.
    TKAddonUpdateResultUpdateAvailable,
    // A metadata answer is being waited for.
    TKAddonUpdateResultChecking,
    // An update archive is being downloaded and installed.
    TKAddonUpdateResultDownloading,
    // A newer file exists, but the project does not hand archives to the API. The row's action
    // opens that exact project inside the app instead of failing.
    TKAddonUpdateResultNeedsBrowserConfirmation,
    // No project identity is recorded. Nothing is inferred from the package's name or folder.
    TKAddonUpdateResultUnlinked,
    // The provider answered and there is no file this app could install for this project.
    TKAddonUpdateResultUnavailableNoCompatibleFile,
    // The check failed in a way a second attempt can fix: a timeout, a rate limit, a network.
    TKAddonUpdateResultFailedRetryable,
    // The check failed in a way a second attempt cannot fix: a rejected key, a gone project.
    TKAddonUpdateResultFailedTerminal,
};

// The facts a decision is made from. Every one of them is something a caller knows for certain;
// nothing here is a guess about a package's identity.
@interface TKAddonUpdateFacts : NSObject
// The record names the project it came from, so it can participate in update checks at all.
@property(nonatomic) BOOL linked;
// The record is disabled or pinned. Both mean "leave this alone", and neither is a failure.
@property(nonatomic) BOOL heldBack;
// The project lets the API hand out its archives.
@property(nonatomic) BOOL apiArchiveAvailable;
// The project has a page the in-app browser can open for this build.
@property(nonatomic) BOOL browserRoutable;
// A check has answered for this package.
@property(nonatomic) BOOL answered;
// What that answer said. Only meaningful when `answered` is YES.
@property(nonatomic) BOOL newerFileExists;
@property(nonatomic) BOOL installedFileIsCurrent;
@property(nonatomic) BOOL noCompatibleFile;
// Work is in flight, if any.
@property(nonatomic) BOOL checking;
@property(nonatomic) BOOL downloading;
// A recorded failure, if any.
@property(nonatomic) BOOL failedRetryable;
@property(nonatomic) BOOL failedTerminal;
@end

// The decision. Pure: same facts in, same answer out, on any thread, with nothing to observe.
FOUNDATION_EXPORT TKAddonUpdateResult TKAddonUpdateResolve(TKAddonUpdateFacts *_Nullable facts);

// The stored string for a result, and the result for a stored string. Checking and downloading
// have no stored form: a relaunch must not claim work that is not running, so those round-trip
// as "not answered yet" and the next check speaks for itself.
FOUNDATION_EXPORT NSString *_Nullable TKAddonUpdateStoredValue(TKAddonUpdateResult result);
FOUNDATION_EXPORT TKAddonUpdateResult TKAddonUpdateResultForStoredValue(NSString *_Nullable value);

// The localization key for the row's own word, e.g. `addons.update.state.upToDate`. Every
// visible sentence about an update comes from here, so no caller invents its own.
FOUNDATION_EXPORT NSString *TKAddonUpdateTitleKey(TKAddonUpdateResult result);

// YES when tapping the row's action should start work (an update, a retry, or a browser
// handoff). NO when the action is a statement rather than a control.
FOUNDATION_EXPORT BOOL TKAddonUpdateIsActionable(TKAddonUpdateResult result);
// YES when the row should show a spinner rather than a word.
FOUNDATION_EXPORT BOOL TKAddonUpdateIsBusy(TKAddonUpdateResult result);

NS_ASSUME_NONNULL_END
