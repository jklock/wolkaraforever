#import "AddonUpdateResolver.h"
#import "AddonStore.h"

@implementation TKAddonUpdateFacts
@end

TKAddonUpdateResult TKAddonUpdateResolve(TKAddonUpdateFacts *facts) {
    if (!facts) return TKAddonUpdateResultUnlinked;
    // A package the player has held back is not a package with a problem. Disabled and pinned
    // come first so neither can ever be reported as a failure.
    if (facts.heldBack) return TKAddonUpdateResultNotApplicable;
    // Work in flight outranks a recorded answer: while a download is running, the download is
    // the truth, and a stale "update available" beneath it would offer the same file again.
    if (facts.downloading) return TKAddonUpdateResultDownloading;
    if (facts.failedTerminal) return TKAddonUpdateResultFailedTerminal;
    if (facts.failedRetryable) return TKAddonUpdateResultFailedRetryable;
    if (facts.checking) return TKAddonUpdateResultChecking;
    if (!facts.linked) return TKAddonUpdateResultUnlinked;
    // Nothing has answered for this package. That is not "checking" unless a request is actually
    // in flight, which was handled above; it is a package whose update nobody has asked about.
    if (!facts.answered) return TKAddonUpdateResultNotChecked;
    if (facts.installedFileIsCurrent) return TKAddonUpdateResultUpToDate;
    if (facts.newerFileExists) {
        if (facts.apiArchiveAvailable) return TKAddonUpdateResultUpdateAvailable;
        // The provider has something newer but will not hand it to the API. That is not a
        // failure and must not read like one: the action opens the project in the app.
        return facts.browserRoutable ? TKAddonUpdateResultNeedsBrowserConfirmation
                                     : TKAddonUpdateResultUnavailableNoCompatibleFile;
    }
    if (facts.noCompatibleFile) return TKAddonUpdateResultUnavailableNoCompatibleFile;
    // An answer that names neither a newer file nor the installed one tells us nothing, so the
    // row asks to be checked rather than pretending a request is running.
    return TKAddonUpdateResultNotChecked;
}

NSString *TKAddonUpdateStoredValue(TKAddonUpdateResult result) {
    switch (result) {
        case TKAddonUpdateResultUpToDate: return TKAddonStoredUpdateUpToDate;
        case TKAddonUpdateResultUpdateAvailable: return TKAddonStoredUpdateAvailable;
        case TKAddonUpdateResultNeedsBrowserConfirmation: return TKAddonStoredUpdateBrowser;
        case TKAddonUpdateResultUnlinked: return TKAddonStoredUpdateUnlinked;
        case TKAddonUpdateResultUnavailableNoCompatibleFile: return TKAddonStoredUpdateUnavailable;
        case TKAddonUpdateResultFailedRetryable: return TKAddonStoredUpdateRetryable;
        case TKAddonUpdateResultFailedTerminal: return TKAddonStoredUpdateTerminal;
        // Transient and local states are deliberately not stored.
        case TKAddonUpdateResultNotApplicable:
        case TKAddonUpdateResultChecking:
        case TKAddonUpdateResultDownloading:
        case TKAddonUpdateResultNotChecked:
            return nil;
    }
    return nil;
}

TKAddonUpdateResult TKAddonUpdateResultForStoredValue(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return TKAddonUpdateResultNotChecked;
    if ([value isEqual:TKAddonStoredUpdateUpToDate]) return TKAddonUpdateResultUpToDate;
    if ([value isEqual:TKAddonStoredUpdateAvailable]) return TKAddonUpdateResultUpdateAvailable;
    if ([value isEqual:TKAddonStoredUpdateBrowser]) return TKAddonUpdateResultNeedsBrowserConfirmation;
    if ([value isEqual:TKAddonStoredUpdateUnlinked]) return TKAddonUpdateResultUnlinked;
    if ([value isEqual:TKAddonStoredUpdateUnavailable]) return TKAddonUpdateResultUnavailableNoCompatibleFile;
    if ([value isEqual:TKAddonStoredUpdateRetryable]) return TKAddonUpdateResultFailedRetryable;
    if ([value isEqual:TKAddonStoredUpdateTerminal]) return TKAddonUpdateResultFailedTerminal;
    // A word from a build that does not exist here tells us nothing, so the row asks to be
    // checked rather than claiming a check is running.
    return TKAddonUpdateResultNotChecked;
}

NSString *TKAddonUpdateTitleKey(TKAddonUpdateResult result) {
    switch (result) {
        case TKAddonUpdateResultUpToDate: return @"addons.update.upToDate";
        case TKAddonUpdateResultUpdateAvailable: return @"addons.update.available";
        case TKAddonUpdateResultChecking: return @"addons.update.checking";
        case TKAddonUpdateResultDownloading: return @"addons.update.downloading";
        case TKAddonUpdateResultNeedsBrowserConfirmation: return @"addons.update.needsBrowser";
        case TKAddonUpdateResultUnlinked: return @"addons.update.unlinked";
        case TKAddonUpdateResultUnavailableNoCompatibleFile: return @"addons.update.unavailable";
        case TKAddonUpdateResultFailedRetryable: return @"addons.update.failedRetry";
        case TKAddonUpdateResultFailedTerminal: return @"addons.update.failedTerminal";
        case TKAddonUpdateResultNotApplicable: return @"addons.update.heldBack";
        case TKAddonUpdateResultNotChecked: return @"addons.update.notChecked";
    }
    return @"addons.update.notChecked";
}

// A stable, language-free name for every state. The log prints this, because the stored value is
// nil for the transient ones and every one of them used to come out as the same word: a sweep
// that resolved nothing looked identical to one that was still working (2026-11-13).
NSString *TKAddonUpdateName(TKAddonUpdateResult result) {
    switch (result) {
        case TKAddonUpdateResultNotApplicable: return @"heldBack";
        case TKAddonUpdateResultUpToDate: return @"upToDate";
        case TKAddonUpdateResultUpdateAvailable: return @"available";
        case TKAddonUpdateResultChecking: return @"checking";
        case TKAddonUpdateResultDownloading: return @"downloading";
        case TKAddonUpdateResultNeedsBrowserConfirmation: return @"browser";
        case TKAddonUpdateResultUnlinked: return @"unlinked";
        case TKAddonUpdateResultUnavailableNoCompatibleFile: return @"unavailable";
        case TKAddonUpdateResultFailedRetryable: return @"retryable";
        case TKAddonUpdateResultFailedTerminal: return @"terminal";
        case TKAddonUpdateResultNotChecked: return @"notChecked";
    }
    return @"unknown";
}

BOOL TKAddonUpdateIsActionable(TKAddonUpdateResult result) {
    switch (result) {
        case TKAddonUpdateResultUpdateAvailable:
        case TKAddonUpdateResultNeedsBrowserConfirmation:
        case TKAddonUpdateResultFailedRetryable:
        case TKAddonUpdateResultUnlinked:
        // Asking again is the action: it starts the check the row has never had.
        case TKAddonUpdateResultNotChecked:
            return YES;
        default:
            return NO;
    }
}

BOOL TKAddonUpdateIsBusy(TKAddonUpdateResult result) {
    return result == TKAddonUpdateResultChecking || result == TKAddonUpdateResultDownloading;
}
