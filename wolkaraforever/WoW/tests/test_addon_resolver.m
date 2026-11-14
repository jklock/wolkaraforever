// The Add-on Hub's update resolver and its log line, built the way the launcher's own suites are:
// no UIKit, no network, AddressSanitizer and UBSan on. The fixture covers the same decisions
// through the page; this covers them where a memory-safety fault would actually be caught.
#include <assert.h>
#include <stdio.h>
#import <Foundation/Foundation.h>
#import "AddonUpdateResolver.h"
#import "AddonHubLog.h"
#import "AddonStore.h"

static TKAddonUpdateFacts *Facts(BOOL linked, BOOL answered, BOOL newer, BOOL api) {
    TKAddonUpdateFacts *facts = [TKAddonUpdateFacts new];
    facts.linked = linked;
    facts.answered = answered;
    facts.newerFileExists = newer;
    facts.apiArchiveAvailable = api;
    facts.browserRoutable = YES;
    return facts;
}

int main(void) {
    @autoreleasepool {
        // The nine states the plan names, each reached from its own facts and no other way.
        // A linked package nothing has answered for is *not* checking: the row says so and
        // offers the check, which is the fault this state exists to end.
        TKAddonUpdateFacts *facts = Facts(YES, NO, NO, NO);
        assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultNotChecked);
        assert(TKAddonUpdateStoredValue(TKAddonUpdateResultNotChecked) == nil);
        assert([TKAddonUpdateTitleKey(TKAddonUpdateResultNotChecked) isEqual:@"addons.update.notChecked"]);
        assert(TKAddonUpdateIsActionable(TKAddonUpdateResultNotChecked));
        assert(!TKAddonUpdateIsBusy(TKAddonUpdateResultNotChecked));
        facts.checking = YES;
        assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultChecking);
        assert(TKAddonUpdateIsBusy(TKAddonUpdateResultChecking));
        facts.checking = NO;
        facts.heldBack = YES;
        assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultNotApplicable);
        facts.heldBack = NO;
        facts.downloading = YES;
        assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultDownloading);
        facts.downloading = NO;
        facts.failedRetryable = YES;
        assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultFailedRetryable);
        facts.failedRetryable = NO;
        facts.failedTerminal = YES;
        assert(TKAddonUpdateResolve(facts) == TKAddonUpdateResultFailedTerminal);
        facts.failedTerminal = NO;
        assert(TKAddonUpdateResolve(Facts(NO, NO, NO, NO)) == TKAddonUpdateResultUnlinked);
        TKAddonUpdateFacts *current = Facts(YES, YES, NO, NO);
        current.installedFileIsCurrent = YES;
        assert(TKAddonUpdateResolve(current) == TKAddonUpdateResultUpToDate);
        assert(TKAddonUpdateResolve(Facts(YES, YES, YES, YES)) == TKAddonUpdateResultUpdateAvailable);
        assert(TKAddonUpdateResolve(Facts(YES, YES, YES, NO)) == TKAddonUpdateResultNeedsBrowserConfirmation);
        TKAddonUpdateFacts *none = Facts(YES, YES, NO, NO);
        none.noCompatibleFile = YES;
        assert(TKAddonUpdateResolve(none) == TKAddonUpdateResultUnavailableNoCompatibleFile);
        // No facts at all is still an answer, not a crash.
        assert(TKAddonUpdateResolve(nil) == TKAddonUpdateResultUnlinked);
        // Nothing is actionable but the four that can start work.
        assert(TKAddonUpdateIsActionable(TKAddonUpdateResultUpdateAvailable));
        assert(TKAddonUpdateIsActionable(TKAddonUpdateResultNeedsBrowserConfirmation));
        assert(TKAddonUpdateIsActionable(TKAddonUpdateResultFailedRetryable));
        assert(TKAddonUpdateIsActionable(TKAddonUpdateResultUnlinked));
        assert(!TKAddonUpdateIsActionable(TKAddonUpdateResultUpToDate));
        assert(TKAddonUpdateIsBusy(TKAddonUpdateResultChecking));
        assert(TKAddonUpdateIsBusy(TKAddonUpdateResultDownloading));
        // The stored form round-trips for the settled states and refuses the moving ones.
        assert(TKAddonUpdateResultForStoredValue(TKAddonUpdateStoredValue(TKAddonUpdateResultUpToDate)) == TKAddonUpdateResultUpToDate);
        assert(TKAddonUpdateResultForStoredValue(TKAddonUpdateStoredValue(TKAddonUpdateResultNeedsBrowserConfirmation)) == TKAddonUpdateResultNeedsBrowserConfirmation);
        assert(TKAddonUpdateStoredValue(TKAddonUpdateResultChecking) == nil);
        assert(TKAddonUpdateStoredValue(TKAddonUpdateResultDownloading) == nil);
        assert(TKAddonUpdateStoredValue(TKAddonUpdateResultNotApplicable) == nil);

        // The log drops everything it has no key for: a URL, a cookie and a token cannot reach
        // the file through it, whatever a caller passes.
        NSString *line = TKAddonHubLogLine(TKAddonHubEventHandoff, @{
            @"url": @"https://media.forgecdn.net/files/1/2/x.zip?token=abc",
            @"cookie": @"session=1",
            TKAddonHubKeyOutcome: @"downloaded",
            TKAddonHubKeyProvider: TKAddonProvenanceBrowser,
            TKAddonHubKeyDigest: @"fedcba9876543210fedcba9876543210",
            TKAddonHubKeyCount: @3,
        });
        assert([line hasPrefix:@"event=handoff"]);
        assert([line containsString:@"provider=browser"]);
        assert([line containsString:@"digest=fedcba9876543210"]);
        assert([line containsString:@"count=3"]);
        assert([line rangeOfString:@"http"].location == NSNotFound);
        assert([line rangeOfString:@"token"].location == NSNotFound);
        assert([line rangeOfString:@"session"].location == NSNotFound);
        // A value of the wrong shape is a `-`, never a fragment of itself.
        NSString *hostile = TKAddonHubLogLine(TKAddonHubEventArchive, @{
            TKAddonHubKeyIdentifier: @"/Users/someone/x.zip",
            TKAddonHubKeyReason: @"a:b",
            TKAddonHubKeyDigest: @"not a digest",
            TKAddonHubKeyProvider: @"scraped",
            TKAddonHubKeyCount: @(-4),
        });
        assert([hostile containsString:@"identifier=-"]);
        assert([hostile containsString:@"reason=-"]);
        assert([hostile containsString:@"digest=-"]);
        assert([hostile containsString:@"provider=-"]);
        assert([hostile rangeOfString:@"count"].location == NSNotFound);
        assert([hostile rangeOfString:@"/Users"].location == NSNotFound);
        // An event with no fields is still one bounded line.
        assert([TKAddonHubLogLine(TKAddonHubEventRecovery, nil) isEqual:@"event=recovery"]);
        puts("ADDON HUB RESOLVER PASS: nine update states from facts alone, the stored round-trip, "
             "and a log that cannot carry a URL, a cookie, a token or a path");
    }
    return 0;
}
