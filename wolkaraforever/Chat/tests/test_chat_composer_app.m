// WolkaraForever: the Chat Composer's own fixture.
//
// Every state, every terminal outcome and every stale callback, driven through the real
// AKChatComposer with a target that records what it was asked to do and a capture seam that
// answers by hand. No guest, no microphone, no window: the point is that the ownership rules can
// be exercised without any of the three.
//
// The structured log is the second half of the evidence: the runner greps the console for the
// `chat-composer:` lines this suite provokes, so "a terminal state says what happened" is checked
// from outside the process that printed it.

#import <UIKit/UIKit.h>
#import "ChatComposer.h"

static NSUInteger checks, failures;

#define CHECK(condition, ...) do { \
    checks++; \
    if (!(condition)) { \
        failures++; \
        NSString *why = [NSString stringWithFormat:__VA_ARGS__]; \
        printf("FAIL %s:%d %s\n", __FILE__, __LINE__, why.UTF8String); \
    } \
} while (0)

#pragma mark - A guest that only records

@interface AKComposerFakeTarget : NSObject <AKChatTextTarget>
@property (nonatomic) BOOL live;
@property (nonatomic) BOOL refusesOpen;
@property (nonatomic) BOOL refusesInsert;
@property (nonatomic) BOOL refusesKey;
@property (nonatomic, strong) NSMutableArray<NSString *> *calls;
@end

@implementation AKComposerFakeTarget
- (instancetype)init {
    if ((self = [super init])) { _live = YES; _calls = [NSMutableArray array]; }
    return self;
}
- (void)reset { [self.calls removeAllObjects]; }
- (BOOL)chatTargetIsLive { return self.live; }
- (BOOL)chatOpen {
    [self.calls addObject:@"open"];
    return !self.refusesOpen;
}
- (BOOL)chatInsertText:(NSString *)text {
    [self.calls addObject:[@"insert:" stringByAppendingString:text]];
    return !self.refusesInsert;
}
- (BOOL)chatPostKey:(unsigned short)code characters:(NSString *)characters {
    (void)characters;
    [self.calls addObject:[NSString stringWithFormat:@"key:%u", code]];
    return !self.refusesKey;
}
- (NSUInteger)countOf:(NSString *)prefix {
    NSUInteger count = 0;
    for (NSString *call in self.calls) if ([call hasPrefix:prefix]) count++;
    return count;
}
- (NSString *)line {
    return [self.calls componentsJoinedByString:@" "];
}
@end

#pragma mark - Capture that answers on demand

/// Stands in for the shell + AKDictation: it records the generations the Composer asks for and
/// says what a pressed Stop must do. Nothing here talks to a recogniser.
static NSUInteger AKCaptureStarts, AKCaptureStops;
static NSUInteger AKCaptureGeneration;

static void AKResetCapture(void) { AKCaptureStarts = AKCaptureStops = 0; AKCaptureGeneration = 0; }

#pragma mark - The cases

static void TestDeliveryModeMigration(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[@"AKChatDeliveryMode", @"AKVoiceEnabled", @"AKVoiceAutoSubmit",
                            @"AKVoiceMode", @"AKVoiceCustomWords", @"AKVoiceTakeButtonFromGame"])
        [defaults removeObjectForKey:key];
    AKChatDeliveryModeResetCacheForTesting();
    // A fresh installation is the product's default: review then send.
    CHECK(AKChatDeliveryModeInForce() == AKChatDeliveryModeReview,
          @"a fresh install starts in review, got %ld", (long)AKChatDeliveryModeInForce());
    CHECK([[defaults stringForKey:@"AKChatDeliveryMode"] isEqual:@"review"],
          @"and the migration is written down, got %@", [defaults stringForKey:@"AKChatDeliveryMode"]);

    // An installation with any voice setting from before the Composer keeps classic direct.
    [defaults removeObjectForKey:@"AKChatDeliveryMode"];
    [defaults setBool:YES forKey:@"AKVoiceAutoSubmit"];
    AKChatDeliveryModeResetCacheForTesting();
    CHECK(AKChatDeliveryModeInForce() == AKChatDeliveryModeClassicDirect,
          @"an existing auto-submit player keeps classic direct, got %ld", (long)AKChatDeliveryModeInForce());
    CHECK([[defaults stringForKey:@"AKChatDeliveryMode"] isEqual:@"classicDirect"],
          @"and that decision is written down too, got %@", [defaults stringForKey:@"AKChatDeliveryMode"]);

    // A stored choice wins over any migration.
    [defaults setObject:@"review" forKey:@"AKChatDeliveryMode"];
    AKChatDeliveryModeResetCacheForTesting();
    CHECK(AKChatDeliveryModeInForce() == AKChatDeliveryModeReview, @"a stored mode is the mode in force");

    // A stored value this build does not know is not trusted; the migration decides again.
    [defaults setObject:@"somethingElse" forKey:@"AKChatDeliveryMode"];
    AKChatDeliveryModeResetCacheForTesting();
    CHECK(AKChatDeliveryModeInForce() == AKChatDeliveryModeClassicDirect,
          @"an unknown stored mode falls back to the migration, got %ld", (long)AKChatDeliveryModeInForce());
    [defaults removeObjectForKey:@"AKVoiceAutoSubmit"];
    [defaults removeObjectForKey:@"AKChatDeliveryMode"];
    AKChatDeliveryModeResetCacheForTesting();
}

static void TestDestinations(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:AKChatDestinationsDefaultsKey];
    AKChatDestinationStore *store = AKChatDestinationStore.shared;

    // Nothing is configured, so there are no destinations and nothing is enabled by accident.
    CHECK(store.all.count == 0 && store.enabled.count == 0, @"nothing configured means nothing offered");

    NSArray<AKChatDestination *> *kept = [AKChatDestinationStore sanitizedDestinations:@[
        @{@"id": @"say", @"title": @"Say", @"command": @"/say", @"enabled": @YES},
        @{@"id": @"say", @"title": @"Again", @"command": @"/yell", @"enabled": @YES},      // duplicate id
        @{@"id": @"party", @"title": @"Party", @"command": @"/p", @"enabled": @YES},
        @{@"id": @"nolone", @"title": @"No line", @"command": @"say hi", @"enabled": @YES}, // no leading slash
        @{@"id": @"control", @"title": @"Control", @"command": @"/say\r", @"enabled": @YES},
        @{@"id": @"longtitle", @"title": @"This title is far too long to fit", @"command": @"/long", @"enabled": @YES},
        @{@"id": @"silent", @"title": @"Silent", @"command": @"/s"},
        @{@"not": @"a record"},
    ]];
    CHECK(kept.count == 3, @"three records are usable, got %lu", (unsigned long)kept.count);
    CHECK([kept.firstObject.identifier isEqual:@"say"], @"the first valid record is kept in order");
    CHECK(!kept[2].enabled, @"a record with no enabled flag is off, never on by omission");
    CHECK(kept[1].title.length <= [AKChatDestinationStore maximumTitleLength],
          @"a title over the limit was dropped rather than truncated");

    // At most four, whichever order they arrive in.
    NSArray<AKChatDestination *> *many = [AKChatDestinationStore sanitizedDestinations:@[
        @{@"id": @"a", @"title": @"A", @"command": @"/a"},
        @{@"id": @"b", @"title": @"B", @"command": @"/b"},
        @{@"id": @"c", @"title": @"C", @"command": @"/c"},
        @{@"id": @"d", @"title": @"D", @"command": @"/d"},
        @{@"id": @"e", @"title": @"E", @"command": @"/e"},
    ]];
    CHECK(many.count == [AKChatDestinationStore maximumCount], @"at most four survive, got %lu",
          (unsigned long)many.count);

    // Stored, and read back through the same rules.
    CHECK([store replaceAll:@[[AKChatDestination destinationWithIdentifier:@"say" title:@"Say"
                                                                   command:@"/say" enabled:YES]]],
          @"a valid destination is stored");
    CHECK(store.enabled.count == 1 && [store.enabled.firstObject.command isEqual:@"/say"],
          @"and comes back enabled, got %@", store.enabled);
    CHECK([defaults objectForKey:AKChatDestinationsDefaultsKey] != nil, @"it is in the defaults database");

    // A hand-written value that is not a list at all is refused without taking the store down.
    [defaults setObject:@"not a list" forKey:AKChatDestinationsDefaultsKey];
    NSArray<AKChatDestination *> *afterGarbage = [AKChatDestinationStore sanitizedDestinations:
        [defaults objectForKey:AKChatDestinationsDefaultsKey]];
    CHECK(afterGarbage.count == 0, @"a value that is not a list yields no destinations");

    [defaults removeObjectForKey:AKChatDestinationsDefaultsKey];
    [store replaceAll:@[]];
}

static AKChatComposer *ComposerForTest(AKComposerFakeTarget *target) {
    AKChatComposer *composer = AKChatComposer.shared;
    AKChatDeliveryModeSet(AKChatDeliveryModeReview);
    [composer resetForTesting];
    composer.target = target;
    composer.testOnlyCapture = ^(BOOL start, NSUInteger generation) {
        if (start) { AKCaptureStarts++; AKCaptureGeneration = generation; }
        else AKCaptureStops++;
    };
    AKResetCapture();
    [target reset];
    return composer;
}

static void TestOpenRefusals(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);

    // No target at all: the open fails, and it fails visibly.
    composer.target = nil;
    CHECK(![composer openWithSource:AKChatComposerSourceToolbar], @"no target means no Composer");
    CHECK(composer.state == AKChatComposerStateFailed && [composer.problem isEqual:@"notSent"],
          @"and it says the message was not sent, got %ld/%@", (long)composer.state, composer.problem);

    // A target whose window has gone.
    [composer resetForTesting];
    composer.target = target;
    target.live = NO;
    CHECK(![composer openWithSource:AKChatComposerSourceKeyboard], @"a target with no window is refused");
    CHECK(composer.state == AKChatComposerStateFailed, @"and the card reports it");

    // The guest could not be asked to open its chat (a password field, say).
    [composer resetForTesting];
    target.live = YES;
    target.refusesOpen = YES;
    CHECK(![composer openWithSource:AKChatComposerSourceController], @"a refused chat open is a failed open");
    CHECK([target countOf:@"open"] == 1, @"it was asked exactly once, got %@", target.line);
    CHECK([target countOf:@"insert"] == 0, @"and nothing was typed into the guest");
    CHECK(AKCaptureStarts == 0, @"and no capture was started");
    target.refusesOpen = NO;
}

static void TestOpenAndCapture(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);

    CHECK([composer openWithSource:AKChatComposerSourceController], @"the Composer opens");
    CHECK(composer.state == AKChatComposerStateListening, @"and starts listening, got %ld", (long)composer.state);
    CHECK([target countOf:@"open"] == 1, @"one Return opened the chat, got %@", target.line);
    CHECK(AKCaptureStarts == 1, @"capture was asked for once");
    NSUInteger generation = composer.generation;
    CHECK(AKCaptureGeneration == generation, @"with the generation in force");

    // A repeated down edge is the same press.
    CHECK(![composer openWithSource:AKChatComposerSourceController], @"a repeated open is refused");
    CHECK([target countOf:@"open"] == 1, @"and it does not press Return again, got %@", target.line);

    // A partial draft is the card's business only.
    [composer speechDraft:@"hello the" provisional:YES generation:generation];
    CHECK([composer.draft isEqual:@"hello the"] && composer.state == AKChatComposerStateListening,
          @"a partial shows in the draft and does not leave listening, got %@/%ld", composer.draft, (long)composer.state);
    CHECK(!composer.canSend, @"and Send is disabled while the result is provisional");

    // The final result replaces the provisional segment and the session is ready.
    [composer speechFinished:@"hello there" generation:generation];
    CHECK([composer.draft isEqual:@"hello there"], @"the final result is the draft, got %@", composer.draft);
    CHECK(composer.state == AKChatComposerStateReady && composer.canSend, @"and the session is ready to send");
    CHECK([target countOf:@"insert"] == 0, @"nothing has reached the guest yet");
}

static void TestStaleCallbacks(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);
    [composer openWithSource:AKChatComposerSourceController];
    NSUInteger stale = composer.generation;

    [composer speechDraft:@"first words" provisional:YES generation:stale];
    // Typing pauses capture, which moves the generation on.
    [composer userChangedDraft:@"first words typed"];
    CHECK(composer.state == AKChatComposerStateEditing, @"editing is the state after typing");
    CHECK(AKCaptureStops == 1, @"and capture was stopped once");

    [composer speechDraft:@"late partial" provisional:YES generation:stale];
    [composer speechFinished:@"late final" generation:stale];
    CHECK([composer.draft isEqual:@"first words typed"], @"a late result cannot change the draft, got %@", composer.draft);
    CHECK([target countOf:@"insert"] == 0 && [target countOf:@"key"] == 0,
          @"and it cannot reach the guest, got %@", target.line);

    // The same after a send: the session is over and nothing may be posted.
    [composer sendWithDestination:nil];
    NSUInteger callsAfterSend = target.calls.count;
    [composer speechFinished:@"after the send" generation:stale];
    [composer speechDraft:@"after the send" provisional:YES generation:stale];
    CHECK(target.calls.count == callsAfterSend, @"a stale callback after Send posts nothing");
}

static void TestSendTransaction(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);
    [composer openWithSource:AKChatComposerSourceToolbar];

    // An empty draft cannot be sent.
    CHECK(!composer.canSend, @"an empty draft cannot be sent");
    [composer sendWithDestination:nil];
    CHECK([target countOf:@"insert"] == 0, @"and a Send with nothing in it posts no text");

    [composer userChangedDraft:@"  hello\tthere  "];
    CHECK(composer.canSend, @"a typed draft can be sent");
    [target reset];
    [composer sendWithDestination:nil];
    CHECK([target.line isEqual:@"insert:hello there key:36 key:53"],
          @"one insertion, Return once, Escape once, got %@", target.line);
    CHECK(composer.state == AKChatComposerStateIdle && composer.draft.length == 0,
          @"the draft is cleared and the session closed, got %ld/%@", (long)composer.state, composer.draft);

    // A destination prefixes its command to the same line.
    [composer openWithSource:AKChatComposerSourceToolbar];
    [composer userChangedDraft:@"hi"];
    AKChatDestination *party = [AKChatDestination destinationWithIdentifier:@"party"
                                                                      title:@"Party"
                                                                    command:@"/p"
                                                                    enabled:YES];
    [target reset];
    [composer sendWithDestination:party];
    CHECK([target.line isEqual:@"insert:/p hi key:36 key:53"],
          @"a destination sends its command and the draft, got %@", target.line);

    // A slash command typed by the player is sent as typed.
    [composer openWithSource:AKChatComposerSourceToolbar];
    [composer userChangedDraft:@"/who"];
    [target reset];
    [composer sendWithDestination:nil];
    CHECK([target.line isEqual:@"insert:/who key:36 key:53"], @"/who is a chat line like any other, got %@", target.line);

    // Unicode survives, and control characters do not become key events.
    [composer openWithSource:AKChatComposerSourceToolbar];
    [composer userChangedDraft:@"é ñ ü 🙂\r"];
    [target reset];
    [composer sendWithDestination:nil];
    CHECK([target.line isEqual:@"insert:é ñ ü 🙂 key:36 key:53"],
          @"composed Unicode is preserved and a pasted Return is a space, got %@", target.line);
}

static void TestSendFailures(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);
    [composer openWithSource:AKChatComposerSourceController];
    [composer userChangedDraft:@"keep me"];

    // A target that goes away between typing and Send.
    target.live = NO;
    [target reset];
    [composer sendWithDestination:nil];
    CHECK(composer.state == AKChatComposerStateFailed && [composer.problem isEqual:@"notSent"],
          @"a failed send reports failure, got %ld/%@", (long)composer.state, composer.problem);
    CHECK([composer.draft isEqual:@"keep me"], @"and keeps the draft, got %@", composer.draft);
    CHECK([target countOf:@"insert"] == 0, @"nothing was inserted, got %@", target.line);
    // It does not retry itself: nothing happens without another explicit action.
    [target reset];
    NSUInteger generation = composer.generation;
    [composer speechFinished:@"late" generation:generation];
    CHECK([target countOf:@"insert"] == 0, @"a failed send does not retry, got %@", target.line);

    // A target that refuses the text keeps the draft too, and posts no Return.
    [composer resetForTesting];
    target.live = YES;
    target.refusesInsert = YES;
    [composer openWithSource:AKChatComposerSourceController];
    [composer userChangedDraft:@"second try"];
    [target reset];
    [composer sendWithDestination:nil];
    CHECK([target countOf:@"insert"] == 1, @"it was tried once, got %@", target.line);
    CHECK([target countOf:@"key"] == 0, @"and no Return or Escape followed a failed insertion, got %@", target.line);
    CHECK([composer.draft isEqual:@"second try"], @"the draft is still there");
    target.refusesInsert = NO;

    // A failed Return is reported and neither retried nor followed by Escape.
    [composer resetForTesting];
    target.refusesKey = YES;
    [composer openWithSource:AKChatComposerSourceController];
    [composer userChangedDraft:@"third try"];
    [target reset];
    [composer sendWithDestination:nil];
    CHECK([target countOf:@"key"] == 1, @"only the Return was attempted, got %@", target.line);
    CHECK([composer.draft isEqual:@"third try"], @"and the draft is kept");
    CHECK(composer.state == AKChatComposerStateFailed, @"the session failed");
    target.refusesKey = NO;
}

static void TestCancelAndLifecycle(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);

    // Cancel after a capture: no text, one Escape, the draft gone.
    [composer openWithSource:AKChatComposerSourceController];
    NSUInteger generation = composer.generation;
    [composer speechDraft:@"half a sentence" provisional:YES generation:generation];
    [target reset];
    [composer cancel];
    CHECK([target countOf:@"insert"] == 0, @"Cancel sends no text, got %@", target.line);
    CHECK([target countOf:@"key:53"] == 1, @"and closes the chat once, got %@", target.line);
    CHECK(composer.state == AKChatComposerStateCancelled && composer.draft.length == 0,
          @"the session is cancelled and the draft dropped, got %ld/%@", (long)composer.state, composer.draft);
    CHECK(AKCaptureStops >= 1, @"and capture was stopped");

    // Cancel with no session open is a no-op that says so.
    [composer resetForTesting];
    [target reset];
    [composer cancel];
    CHECK(target.calls.count == 0, @"a cancel with nothing open posts nothing, got %@", target.line);

    // Background and return: the draft is kept and nothing is sent.
    [composer resetForTesting];
    [composer openWithSource:AKChatComposerSourceKeyboard];
    [composer userChangedDraft:@"unsent words"];
    [target reset];
    [composer appDidBackground];
    CHECK([target countOf:@"insert"] == 0, @"backgrounding never sends, got %@", target.line);
    CHECK([composer.draft isEqual:@"unsent words"], @"the draft is kept for the return, got %@", composer.draft);
    CHECK(composer.state == AKChatComposerStateCancelled, @"and the session is closed");
    // Coming back re-opens with that draft.
    [target reset];
    CHECK([composer openWithSource:AKChatComposerSourceKeyboard], @"the Composer opens again");
    CHECK([composer.draft isEqual:@"unsent words"], @"with the words that were kept, got %@", composer.draft);
    CHECK([target countOf:@"open"] == 1, @"and one new Return opened the chat again");

    // A controller that goes away mid-capture ends the session and sends nothing.
    [composer resetForTesting];
    [composer openWithSource:AKChatComposerSourceController];
    NSUInteger live = composer.generation;
    [composer speechDraft:@"in flight" provisional:YES generation:live];
    [target reset];
    [composer controllerDidDisconnect];
    CHECK([target countOf:@"insert"] == 0, @"a disconnect sends nothing, got %@", target.line);
    CHECK(composer.state == AKChatComposerStateCancelled, @"and the session is cancelled");
    [composer speechFinished:@"after the disconnect" generation:live];
    CHECK([composer.draft isEqual:@"in flight"], @"a late result after the disconnect is ignored, got %@", composer.draft);
}

static void TestEditingAndRollback(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);

    // Editing after dictation keeps what was typed before the microphone opened.
    [composer openWithSource:AKChatComposerSourceController];
    [composer userChangedDraft:@"prefix"];
    [composer resumeCapture];
    NSUInteger generation = composer.generation;
    [composer speechFinished:@"spoken words" generation:generation];
    CHECK([composer.draft isEqual:@"prefix spoken words"], @"the transcript is appended to the typed draft, got %@", composer.draft);

    // Rollback: the draft goes, destinations and the mapping do not.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [AKChatDestinationStore.shared replaceAll:@[[AKChatDestination destinationWithIdentifier:@"say"
                                                                                      title:@"Say"
                                                                                    command:@"/say"
                                                                                    enabled:YES]]];
    [defaults setObject:@{@"element": @"controller.button.share"} forKey:@"AKInputTrigger.fixture"];
    [composer resetForTesting];
    [composer openWithSource:AKChatComposerSourceController];
    [composer userChangedDraft:@"should not survive a rollback"];
    [target reset];
    [composer composerWasTurnedOff];
    CHECK(composer.draft.length == 0, @"rollback clears the ephemeral draft, got %@", composer.draft);
    CHECK([target countOf:@"insert"] == 0, @"and sends nothing, got %@", target.line);
    CHECK(AKChatDestinationStore.shared.all.count == 1, @"destinations stay for a later re-enable");
    CHECK([defaults dictionaryForKey:@"AKInputTrigger.fixture"] != nil, @"and so does the mapping");
    [defaults removeObjectForKey:@"AKInputTrigger.fixture"];
    [AKChatDestinationStore.shared replaceAll:@[]];

    // The feature flag is the rollback switch: off means no Composer at all.
    [defaults setBool:NO forKey:AKChatComposerEnabledKey];
    [composer resetForTesting];
    CHECK(!AKChatComposerIsAvailable(), @"the flag turns the Composer off");
    CHECK(![composer openWithSource:AKChatComposerSourceController], @"and an open is refused");
    [defaults removeObjectForKey:AKChatComposerEnabledKey];
    CHECK(AKChatComposerIsAvailable(), @"and on again once the flag is gone");
}

static void TestDraftBounds(void) {
    AKComposerFakeTarget *target = [AKComposerFakeTarget new];
    AKChatComposer *composer = ComposerForTest(target);
    [composer openWithSource:AKChatComposerSourceToolbar];
    NSMutableString *longText = [NSMutableString string];
    for (NSUInteger index = 0; index < 3000; index++) [longText appendString:@"x"];
    [composer userChangedDraft:longText];
    CHECK(composer.draft.length <= 1024, @"the draft is bounded, got %lu", (unsigned long)composer.draft.length);
    [target reset];
    [composer sendWithDestination:nil];
    NSString *inserted = target.calls.firstObject ?: @"";
    CHECK(inserted.length <= 1024 + @"insert:".length, @"and so is what reaches the guest, got %lu",
          (unsigned long)inserted.length);
}

#pragma mark - Running them

@interface AKComposerTestScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic) UIWindow *window;
@end

@implementation AKComposerTestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    // A fixture that can hang is not a fixture.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        fprintf(stderr, "CHAT_COMPOSER_TIMEOUT\n");
        _Exit(1);
    });
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];

    TestDeliveryModeMigration();
    TestDestinations();
    TestOpenRefusals();
    TestOpenAndCapture();
    TestStaleCallbacks();
    TestSendTransaction();
    TestSendFailures();
    TestCancelAndLifecycle();
    TestEditingAndRollback();
    TestDraftBounds();

    if (failures == 0) {
        printf("CHAT_COMPOSER PASS: %lu checks\n", (unsigned long)checks);
        fflush(stdout);
        exit(0);
    }
    printf("CHAT_COMPOSER FAIL: %lu of %lu checks failed\n", (unsigned long)failures, (unsigned long)checks);
    fflush(stdout);
    exit(1);
}
@end

@interface AKComposerTestApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKComposerTestApp
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Composer tests"
                                                                        sessionRole:session.role];
    configuration.delegateClass = AKComposerTestScene.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AKComposerTestApp.class));
    }
}
