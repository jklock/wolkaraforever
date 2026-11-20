// The saved game password, as the launcher keeps it: one item, stored only while the experimental
// Battle.net login is on, replaced without losing the previous one, refused rather than silently
// dropped, and gone after forget. The keyboard's crossings are exercised for real - the requests
// are posted exactly as TouchControls posts them - so the contract in Touch/TouchControls.h is
// checked, not just this class.
//
// A macOS host has no Face ID, so the item is stored without the user-presence access control and
// under a service of its own: a test run can never touch a player's item, and never prompts.
#import <Foundation/Foundation.h>
#import "../launcher/WoW/BattleNetSavedPassword.h"

static NSNotificationName const StoreRequest = @"AKTouchSavedPasswordStoreRequest";
static NSNotificationName const ReadRequest = @"AKTouchSavedPasswordReadRequest";
static NSNotificationName const Availability = @"AKTouchSavedPasswordAvailability";

static int failures;

static void check(BOOL condition, NSString *what) {
    if (condition) { printf("ok   %s\n", what.UTF8String); return; }
    failures++;
    printf("FAIL %s\n", what.UTF8String);
}

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// The answer arrives on the main queue, so the loop has to run for it to be delivered.
static void waitFor(volatile BOOL *done, NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!*done && deadline.timeIntervalSinceNow > 0) spin(0.01);
}

static BOOL setExperimentalLogin(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"WoWBrowserLogin"];
    return [TKBattleNetSavedPassword loginEnabled] == enabled;
}

static NSString *readPassword(void) {
    __block NSString *password = nil;
    __block BOOL done = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:ReadRequest object:nil
        userInfo:@{@"reply": ^(NSString *value) { password = [value copy]; done = YES; }}];
    waitFor(&done, 5);
    return password;
}

static BOOL storePassword(NSString *password) {
    __block BOOL stored = NO;
    __block BOOL done = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:StoreRequest object:nil
        userInfo:@{@"password": password, @"reply": ^(BOOL value) { stored = value; done = YES; }}];
    waitFor(&done, 5);
    return stored;
}

int main(void) {
    @autoreleasepool {
        [TKBattleNetSavedPassword useService:@"org.tolkara.tests.saved-password" plainProtection:YES];
        [TKBattleNetSavedPassword begin];
        [TKBattleNetSavedPassword forget];

        check(![TKBattleNetSavedPassword hasSavedPassword], @"nothing is kept before anything is saved");
        check(readPassword() == nil, @"a read with nothing saved answers with nothing");

        // Off: the store is refused, and nothing is kept. This is the gate that makes the feature
        // part of the experimental login rather than a general keyboard setting.
        setExperimentalLogin(NO);
        check(!storePassword(@"refused-value"), @"a store is refused while the experimental login is off");
        check(![TKBattleNetSavedPassword hasSavedPassword], @"a refused store keeps no flag");
        check(readPassword() == nil, @"a read is refused while the experimental login is off");

        setExperimentalLogin(YES);
        check(storePassword(@"first-value"), @"a store succeeds while the experimental login is on");
        check([TKBattleNetSavedPassword hasSavedPassword], @"the flag reports that one is kept");
        check([readPassword() isEqual:@"first-value"], @"the read returns the password that was stored");

        // A second save replaces the first: the old value is gone, not kept beside the new one.
        check(storePassword(@"second-value"), @"a second store succeeds");
        check([readPassword() isEqual:@"second-value"], @"the second save replaced the first");

        // The item survives the feature going off, but the keyboard is not given it.
        setExperimentalLogin(NO);
        check(readPassword() == nil, @"a read is refused while the feature is off, even with an item kept");
        check([TKBattleNetSavedPassword hasSavedPassword], @"the item is still kept while the feature is off");
        setExperimentalLogin(YES);
        check([readPassword() isEqual:@"second-value"], @"turning the feature back on returns the same password");

        // Forgetting is the player's other way out, and it takes both the item and the flag.
        [TKBattleNetSavedPassword forget];
        check(![TKBattleNetSavedPassword hasSavedPassword], @"forget clears the flag");
        check(readPassword() == nil, @"forget deletes the item");

        // What the keyboard follows: the setting itself, and nothing else.
        setExperimentalLogin(NO);
        __block NSNumber *published = nil;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:Availability object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            published = note.userInfo[@"enabled"];
        }];
        [TKBattleNetSavedPassword postAvailability];
        spin(0.2);
        check(published != nil && !published.boolValue, @"availability reports the feature as off");
        setExperimentalLogin(YES);
        [TKBattleNetSavedPassword postAvailability];
        spin(0.2);
        check(published != nil && published.boolValue, @"availability reports the feature as on");
        [NSNotificationCenter.defaultCenter removeObserver:observer];

        [TKBattleNetSavedPassword forget];
    }
    printf(failures ? "SAVED_PASSWORD FAILED: %d check(s)\n" : "SAVED_PASSWORD PASS: %d checks\n",
           failures ? failures : 21);
    return failures ? 1 : 0;
}
