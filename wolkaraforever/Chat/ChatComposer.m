// WolkaraForever: the Chat Composer, in full. See ChatComposer.h for why it is shaped this way.

#import "ChatComposer.h"
#import "AKSupport.h"

NSNotificationName const AKChatComposerDidChangeNotification = @"AKChatComposerDidChange";
NSString *const AKChatComposerStateKey = @"state";

NSString *const AKChatComposerEnabledKey = @"AKChatComposerEnabled";
NSString *const AKChatDestinationsDefaultsKey = @"AKChatDestinationsV1";
static NSString *const AKChatDeliveryModeKey = @"AKChatDeliveryMode";
static NSString *const AKChatDeliveryClassic = @"classicDirect";
static NSString *const AKChatDeliveryReview = @"review";

// The settings that existed before the Composer did. One of them being in the defaults database
// is what makes an installation "existing" for the one-time migration below: a player who has
// used dictation keeps exactly the behaviour those settings gave them.
static NSArray<NSString *> *AKChatLegacyVoiceKeys(void) {
    return @[@"AKVoiceEnabled", @"AKVoiceAutoSubmit", @"AKVoiceMode",
             @"AKVoiceCustomWords", @"AKVoiceTakeButtonFromGame"];
}

#pragma mark - Delivery mode

static AKChatDeliveryMode AKChatCachedMode;
static BOOL AKChatModeCached;

AKChatDeliveryMode AKChatDeliveryModeInForce(void) {
    // Computed once per process and cached: the open path reads it, and a migration decision
    // must not be re-taken while the player is typing. Everything here runs on the main thread.
    if (AKChatModeCached) return AKChatCachedMode;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id stored = [defaults objectForKey:AKChatDeliveryModeKey];
    if ([stored isKindOfClass:NSString.class] &&
        ([stored isEqual:AKChatDeliveryClassic] || [stored isEqual:AKChatDeliveryReview])) {
        AKChatCachedMode = [stored isEqual:AKChatDeliveryReview] ? AKChatDeliveryModeReview
                                                                 : AKChatDeliveryModeClassicDirect;
        AKChatModeCached = YES;
        AKLog(@"chat-composer: delivery mode %@ (stored)", stored);
        return AKChatCachedMode;
    }
    // Migrated once, and written down, so the decision cannot drift between launches or
    // between the two readers of this key (here, and the shell that routes the mapped
    // button). Nothing about an existing player's settings is altered: classic direct is
    // what those settings already produced.
    BOOL existing = NO;
    for (NSString *key in AKChatLegacyVoiceKeys()) {
        if ([defaults objectForKey:key]) { existing = YES; break; }
    }
    AKChatCachedMode = existing ? AKChatDeliveryModeClassicDirect : AKChatDeliveryModeReview;
    AKChatModeCached = YES;
    [defaults setObject:(existing ? AKChatDeliveryClassic : AKChatDeliveryReview)
                 forKey:AKChatDeliveryModeKey];
    AKLog(@"chat-composer: delivery mode %@ (migrated: %@ installation)",
          existing ? AKChatDeliveryClassic : AKChatDeliveryReview,
          existing ? @"an existing" : @"a new");
    return AKChatCachedMode;
}

void AKChatDeliveryModeSet(AKChatDeliveryMode mode) {
    [NSUserDefaults.standardUserDefaults setObject:(mode == AKChatDeliveryModeReview
        ? AKChatDeliveryReview : AKChatDeliveryClassic)
                                            forKey:AKChatDeliveryModeKey];
    AKLog(@"chat-composer: delivery mode %@", mode == AKChatDeliveryModeReview
          ? AKChatDeliveryReview : AKChatDeliveryClassic);
    AKChatDeliveryModeResetCacheForTesting();
}

void AKChatDeliveryModeResetCacheForTesting(void) {
    // The in-force answer is computed once per process. A test that changes the mode has to be
    // able to make the next reader see it, and so does nothing else: the app has one mode per
    // launch, and that is the behaviour a player gets.
    AKChatModeCached = NO;
}

BOOL AKChatComposerIsAvailable(void) {
    NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:AKChatComposerEnabledKey];
    // On unless the player (or a release) turned it off: the Composer is the product's default
    // for a new installation, and the delivery mode decides whether it is used automatically.
    if (![saved isKindOfClass:NSNumber.class]) return YES;
    return saved.boolValue;
}

#pragma mark - A destination

@implementation AKChatDestination
+ (instancetype)destinationWithIdentifier:(NSString *)identifier
                                    title:(NSString *)title
                                  command:(NSString *)command
                                  enabled:(BOOL)enabled {
    AKChatDestination *destination = [AKChatDestination new];
    destination.identifier = identifier ?: @"";
    destination.title = title ?: @"";
    destination.command = command ?: @"";
    destination.enabled = enabled;
    return destination;
}
- (NSString *)description {
    // The identifier and the title are the player's words for a feature, not a message; the
    // command is a channel name, never a line they typed into the draft.
    return [NSString stringWithFormat:@"<destination %@ %@>", self.identifier, self.enabled ? @"on" : @"off"];
}
@end

#pragma mark - The destination store

// The limits from 07-completion-spec.md. Repeated at the configuration file's boundary, for the
// reason in ChatComposer.h: NSUserDefaults can be written by anything in the process.
static NSUInteger const AKChatDestinationLimit = 4;
static NSUInteger const AKChatDestinationIdentifierLimit = 24;
static NSUInteger const AKChatDestinationTitleLimit = 24;
static NSUInteger const AKChatDestinationCommandLimit = 64;

@implementation AKChatDestinationStore {
    NSArray<AKChatDestination *> *_all;
}

+ (instancetype)shared {
    static AKChatDestinationStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKChatDestinationStore new]; });
    return shared;
}

+ (NSUInteger)maximumCount { return AKChatDestinationLimit; }
+ (NSUInteger)maximumTitleLength { return AKChatDestinationTitleLimit; }
+ (NSUInteger)maximumCommandLength { return AKChatDestinationCommandLimit; }

- (NSArray<AKChatDestination *> *)all {
    if (!_all) _all = [AKChatDestinationStore sanitizedDestinations:
                       [NSUserDefaults.standardUserDefaults objectForKey:AKChatDestinationsDefaultsKey]];
    return _all;
}

- (NSArray<AKChatDestination *> *)enabled {
    NSMutableArray<AKChatDestination *> *enabled = [NSMutableArray array];
    for (AKChatDestination *destination in self.all) if (destination.enabled) [enabled addObject:destination];
    return enabled;
}

- (BOOL)replaceAll:(NSArray<AKChatDestination *> *)destinations {
    NSArray<NSDictionary *> *encode = [AKChatDestinationStore encodedForm:destinations];
    NSArray<AKChatDestination *> *sanitized = [AKChatDestinationStore sanitizedDestinations:encode];
    if (destinations.count && !sanitized.count) {
        AKLog(@"chat-composer: destinations refused; %lu record(s) broke a rule and none could be kept",
              (unsigned long)destinations.count);
        return NO;
    }
    [NSUserDefaults.standardUserDefaults setObject:encode forKey:AKChatDestinationsDefaultsKey];
    _all = sanitized;
    AKLog(@"chat-composer: %lu destination(s) stored, %lu enabled",
          (unsigned long)sanitized.count, (unsigned long)self.enabled.count);
    return YES;
}

+ (NSArray<NSDictionary *> *)encodedForm:(NSArray<AKChatDestination *> *)destinations {
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    for (AKChatDestination *destination in destinations) {
        [records addObject:@{@"id": destination.identifier ?: @"",
                             @"title": destination.title ?: @"",
                             @"command": destination.command ?: @"",
                             @"enabled": @(destination.enabled)}];
    }
    return records;
}

/// A character a command may hold: printable, no control characters, no line breaks. A newline
/// in a command is an injected Return, which is the one thing a stored record must never be
/// able to smuggle into the send transaction.
static BOOL AKChatCharacterIsPrintable(unichar character) {
    NSCharacterSet *refused = NSCharacterSet.controlCharacterSet;
    return ![refused characterIsMember:character];
}

+ (NSArray<AKChatDestination *> *)sanitizedDestinations:(nullable id)raw {
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<AKChatDestination *> *kept = [NSMutableArray array];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    NSMutableSet<NSString *> *commands = [NSMutableSet set];
    for (id entry in (NSArray *)raw) {
        if (kept.count >= AKChatDestinationLimit) break;
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *record = entry;
        id identifier = record[@"id"], title = record[@"title"], command = record[@"command"];
        id enabled = record[@"enabled"];
        if (![identifier isKindOfClass:NSString.class] || ![title isKindOfClass:NSString.class] ||
            ![command isKindOfClass:NSString.class]) continue;

        NSString *name = [(NSString *)identifier stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *label = [(NSString *)title stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *line = [(NSString *)command stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length || name.length > AKChatDestinationIdentifierLimit) continue;
        if (!label.length || label.length > AKChatDestinationTitleLimit) continue;
        // One leading slash, printable, and no Return hiding in it.
        if (line.length < 2 || line.length > AKChatDestinationCommandLimit) continue;
        if (![line hasPrefix:@"/"]) continue;
        BOOL printable = YES;
        for (NSUInteger index = 0; index < line.length; index++) {
            if (!AKChatCharacterIsPrintable([line characterAtIndex:index])) { printable = NO; break; }
        }
        if (!printable) continue;
        if ([identifiers containsObject:name] || [commands containsObject:line]) continue;
        [identifiers addObject:name];
        [commands addObject:line];
        BOOL on = [enabled isKindOfClass:NSNumber.class] ? [enabled boolValue] : NO;
        if (!enabled) on = NO;   // absent means disabled: nothing is enabled by omission
        [kept addObject:[AKChatDestination destinationWithIdentifier:name title:label
                                                             command:line enabled:on]];
    }
    return kept;
}
@end

#pragma mark - The Composer

// The longest line the Composer will hand the guest. Long enough for a sentence and a command,
// short enough that a paste or a runaway recogniser cannot turn into a long key sequence.
static NSUInteger const AKChatComposerDraftLimit = 1024;
// kVK_Return and kVK_Escape, the two keys the transaction is allowed to post.
static unsigned short const AKChatKeyReturn = 36;
static unsigned short const AKChatKeyEscape = 53;

@implementation AKChatComposer {
    AKChatComposerState _state;
    AKChatComposerSource _source;
    NSUInteger _generation;
    NSString *_draft;
    NSString *_problem;
    // The draft as it stood when capture began, so a final transcript replaces only the
    // recognised segment.
    NSString *_draftBeforeCapture;
    BOOL _provisional;
    BOOL _ownsChat;
}

+ (instancetype)shared {
    static AKChatComposer *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKChatComposer new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _draft = @"";
        _generation = 0;
        _state = AKChatComposerStateIdle;
    }
    return self;
}

#pragma mark What the card reads

- (AKChatComposerState)state { return _state; }
- (AKChatComposerSource)source { return _source; }
- (NSUInteger)generation { return _generation; }
- (NSString *)draft { return _draft ?: @""; }
- (NSString *)problem { return _problem; }
- (BOOL)capturing { return _state == AKChatComposerStateListening; }
- (BOOL)draftEditable {
    switch (_state) {
        // Idle is the review card with a typed draft and no session yet: the draft is the
        // player's from the first character, before any microphone or Return.
        case AKChatComposerStateIdle:
        case AKChatComposerStateListening:
        case AKChatComposerStateEditing:
        case AKChatComposerStateReady:
        case AKChatComposerStateFailed:
            return YES;
        default:
            return NO;
    }
}

/// The line that would go to the guest, or nil when there is nothing to send.
- (nullable NSString *)committedLineForDestination:(nullable AKChatDestination *)destination {
    // Control characters become spaces, exactly as the draft editor and the Replace path have
    // always done: a pasted Return must not become a guest key event.
    NSString *body = [[self.draft componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]
        componentsJoinedByString:@" "];
    body = [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (body.length > AKChatComposerDraftLimit) body = [body substringToIndex:AKChatComposerDraftLimit];
    if (!body.length) return nil;
    if (!destination.command.length) return body;
    return [NSString stringWithFormat:@"%@ %@", destination.command, body];
}

- (BOOL)canSend {
    switch (_state) {
        // Idle: a typed draft with no session yet. Send opens the chat and commits in one
        // transaction, which is the transaction's step 3. Opening has nothing to send; sending,
        // cancelled and failed are not states a Send may start from - a failed send does not
        // retry itself, and the player's next explicit action is an edit or a Cancel.
        case AKChatComposerStateIdle:
        case AKChatComposerStateListening:
        case AKChatComposerStateEditing:
        case AKChatComposerStateReady:
            break;
        default:
            return NO;
    }
    if (_provisional) return NO;
    return [self committedLineForDestination:nil] != nil;
}

#pragma mark The one place the state changes

- (void)setState:(AKChatComposerState)state {
    AKChatComposerState previous = _state;
    _state = state;
    if (previous != state)
        AKLog(@"chat-composer: state %ld -> %ld generation=%lu source=%ld",
              (long)previous, (long)state, (unsigned long)_generation, (long)_source);
    [self publish];
}

- (void)publish {
    [NSNotificationCenter.defaultCenter postNotificationName:AKChatComposerDidChangeNotification
                                                     object:self
                                                   userInfo:@{AKChatComposerStateKey: @(_state)}];
}

- (void)setDraft:(NSString *)draft {
    _draft = draft ?: @"";
}

- (void)requestCapture:(BOOL)start generation:(NSUInteger)generation {
    // Lengths only, and never the words: a dictated line is the speaker's, and the log of a
    // running game is read by people who are not them.
    AKLog(@"chat-composer: capture %@ requested generation=%lu draft=%lu characters",
          start ? @"start" : @"stop", (unsigned long)generation, (unsigned long)self.draft.length);
    if (_testOnlyCapture) { _testOnlyCapture(start, generation); return; }
    if (_captureRequest) _captureRequest(start, generation);
}

#pragma mark Entry

- (BOOL)openWithSource:(AKChatComposerSource)source {
    if (!AKChatComposerIsAvailable()) {
        AKLog(@"chat-composer: open refused, the Composer is switched off");
        return NO;
    }
    switch (_state) {
        case AKChatComposerStateOpening:
        case AKChatComposerStateListening:
        case AKChatComposerStateEditing:
        case AKChatComposerStateReady:
        case AKChatComposerStateSending:
            // A repeated down edge is the same press: one Composer, not two, and no re-opened
            // chat that would leave a second Return in the guest's box.
            AKLog(@"chat-composer: open ignored in state %ld (a repeated press is the same press)",
                  (long)_state);
            return NO;
        default:
            break;
    }
    _source = source;
    _problem = nil;
    _provisional = NO;
    _ownsChat = NO;
    NSUInteger generation = ++_generation;
    // A draft kept from a session that ended in the background is the player's; it comes back
    // rather than being retyped. A cancelled one was dropped when it was cancelled.
    if (!_draft) [self setDraft:@""];
    [self setState:AKChatComposerStateOpening];
    AKLog(@"chat-composer: open source=%ld generation=%lu draft=%lu characters",
          (long)source, (unsigned long)generation, (unsigned long)self.draft.length);

    id<AKChatTextTarget> target = self.target;
    if (!target || ![target chatTargetIsLive]) {
        AKLog(@"chat-composer: no live text target; nothing was opened");
        _problem = @"notSent";
        [self setState:AKChatComposerStateFailed];
        return NO;
    }
    if (![target chatOpen]) {
        AKLog(@"chat-composer: the guest could not be asked to open its chat");
        _problem = @"notSent";
        [self setState:AKChatComposerStateFailed];
        return NO;
    }
    _ownsChat = YES;
    _draftBeforeCapture = self.draft;
    [self setState:self.draft.length ? AKChatComposerStateReady : AKChatComposerStateListening];
    [self requestCapture:YES generation:generation];
    if (!_captureRequest && !_testOnlyCapture) {
        // Nothing in this process can reach the microphone (a fixture, or a build without the
        // voice module). The card stays usable for typing instead of waiting for a result that
        // was never asked for.
        AKLog(@"chat-composer: no capture route; the card opens for typing");
        [self setState:self.draft.length ? AKChatComposerStateReady : AKChatComposerStateEditing];
    }
    return YES;
}

- (void)userChangedDraft:(NSString *)text {
    if (!self.draftEditable) return;
    if (self.capturing) [self pauseForEditing];
    [self setDraft:[self truncatedDraft:text]];
    _provisional = NO;
    _problem = nil;
    // Editing is the state, whatever the draft says: Send reads the draft itself, so an empty
    // one needs no second state.
    [self setState:AKChatComposerStateEditing];
}

- (NSString *)truncatedDraft:(nullable NSString *)text {
    NSString *draft = text ?: @"";
    return draft.length > AKChatComposerDraftLimit ? [draft substringToIndex:AKChatComposerDraftLimit] : draft;
}

- (void)pauseForEditing {
    if (_state != AKChatComposerStateListening) return;
    // The generation moves on before the microphone is asked to stop, so a result already in
    // flight cannot arrive afterwards and overwrite what the player is typing.
    NSUInteger generation = ++_generation;
    AKLog(@"chat-composer: editing pauses capture generation=%lu", (unsigned long)generation);
    [self requestCapture:NO generation:generation];
    [self setState:AKChatComposerStateEditing];
}

- (void)resumeCapture {
    if (!self.draftEditable || self.capturing) return;
    NSUInteger generation = ++_generation;
    _draftBeforeCapture = self.draft;
    _provisional = NO;
    _problem = nil;
    AKLog(@"chat-composer: capture resumes generation=%lu", (unsigned long)generation);
    [self setState:AKChatComposerStateListening];
    [self requestCapture:YES generation:generation];
    if (!_captureRequest && !_testOnlyCapture)
        [self setState:self.draft.length ? AKChatComposerStateReady : AKChatComposerStateEditing];
}

#pragma mark Speech

- (BOOL)acceptsSpeechForGeneration:(NSUInteger)generation {
    if (generation != _generation) {
        AKLog(@"chat-composer: stale capture callback generation=%lu (in force %lu) ignored",
              (unsigned long)generation, (unsigned long)_generation);
        return NO;
    }
    if (_state != AKChatComposerStateListening && _state != AKChatComposerStateEditing &&
        _state != AKChatComposerStateReady)
        return NO;
    return YES;
}

- (NSString *)draftFromSpeech:(nullable NSString *)text {
    NSString *prefix = _draftBeforeCapture ?: @"";
    NSString *spoken = [self truncatedDraft:text];
    if (!prefix.length) return spoken;
    if (!spoken.length) return prefix;
    BOOL spaced = [prefix hasSuffix:@" "] || [prefix hasSuffix:@"\n"];
    return [NSString stringWithFormat:@"%@%@%@", prefix, spaced ? @"" : @" ", spoken];
}

- (void)speechDraft:(NSString *)text provisional:(BOOL)provisional generation:(NSUInteger)generation {
    if (![self acceptsSpeechForGeneration:generation]) return;
    [self setDraft:[self draftFromSpeech:text]];
    _provisional = provisional;
    _problem = nil;
    [self publish];
}

- (void)speechFinished:(nullable NSString *)text generation:(NSUInteger)generation {
    if (![self acceptsSpeechForGeneration:generation]) return;
    [self setDraft:[self draftFromSpeech:text]];
    _provisional = NO;
    _draftBeforeCapture = nil;
    if (!self.draft.length) {
        AKLog(@"chat-composer: recognition finished with nothing to send generation=%lu",
              (unsigned long)generation);
        _problem = @"nothingHeard";
        [self setState:AKChatComposerStateFailed];
        return;
    }
    [self setState:AKChatComposerStateReady];
}

- (void)speechFailed:(NSString *)reason generation:(NSUInteger)generation {
    if (![self acceptsSpeechForGeneration:generation]) return;
    // The reason is diagnostic and may name the recogniser; what the card says is ours and
    // localized. The draft stays, because a failed capture is not a reason to lose typing.
    AKLog(@"chat-composer: capture failed generation=%lu reason=%@", (unsigned long)generation, reason);
    _provisional = NO;
    _draftBeforeCapture = nil;
    _problem = @"nothingHeard";
    [self setState:AKChatComposerStateFailed];
}

- (void)speechStoppedWithReason:(NSString *)reason generation:(NSUInteger)generation {
    if (![self acceptsSpeechForGeneration:generation]) return;
    AKLog(@"chat-composer: capture stopped generation=%lu reason=%@", (unsigned long)generation, reason);
    _provisional = NO;
    _draftBeforeCapture = nil;
    if (self.draft.length) {
        // Words are still on screen, so the card stays: the player can send them or edit them.
        [self setState:AKChatComposerStateReady];
    } else {
        _problem = @"nothingHeard";
        [self setState:AKChatComposerStateCancelled];
    }
}

#pragma mark The transaction

- (void)sendWithDestination:(nullable AKChatDestination *)destination {
    if (_state == AKChatComposerStateSending) {
        AKLog(@"chat-composer: duplicate Send ignored generation=%lu", (unsigned long)_generation);
        return;
    }
    NSString *line = [self committedLineForDestination:destination];
    if (!line || !self.canSend) {
        AKLog(@"chat-composer: Send refused outcome=empty-draft state=%ld", (long)_state);
        return;
    }
    // 1. The session's callbacks stop here. Anything the recogniser says from now on belongs to
    //    a generation that is no longer in force.
    NSUInteger generation = ++_generation;
    [self requestCapture:NO generation:generation];
    _provisional = NO;
    [self setState:AKChatComposerStateSending];
    AKLog(@"chat-composer: Send destination=%@ generation=%lu characters=%lu",
          destination.identifier ?: @"direct", (unsigned long)generation, (unsigned long)line.length);

    id<AKChatTextTarget> target = self.target;
    if (!target || ![target chatTargetIsLive]) {
        [self failSendAtStage:@"target" generation:generation line:line];
        return;
    }
    // 2. Chat opened by this Composer stays open; one that was never opened is opened now, once.
    if (!_ownsChat) {
        if (![target chatOpen]) {
            [self failSendAtStage:@"open" generation:generation line:line];
            return;
        }
        _ownsChat = YES;
    }
    // 3. The text, exactly once.
    if (![target chatInsertText:line]) {
        [self failSendAtStage:@"insert" generation:generation line:line];
        return;
    }
    // 4. Return, exactly once.
    BOOL submitted = [target chatPostKey:AKChatKeyReturn characters:@"\r"];
    if (!submitted) {
        // The text is already in the box. Saying so is all that is left: retrying here is the
        // duplicate message this transaction exists to prevent.
        [self failSendAtStage:@"return" generation:generation line:line];
        return;
    }
    // 5. Escape, exactly once, and only on a send this Composer may close.
    if (_ownsChat) [target chatPostKey:AKChatKeyEscape characters:@"\x1b"];

    AKLog(@"chat-composer: Send outcome=sent destination=%@ generation=%lu characters=%lu",
          destination.identifier ?: @"direct", (unsigned long)generation, (unsigned long)line.length);
    [self setDraft:@""];
    _draftBeforeCapture = nil;
    _ownsChat = NO;
    _problem = nil;
    [self setState:AKChatComposerStateIdle];
}

- (void)failSendAtStage:(NSString *)stage generation:(NSUInteger)generation line:(NSString *)line {
    AKLog(@"chat-composer: Send outcome=failed stage=%@ generation=%lu characters=%lu",
          stage, (unsigned long)generation, (unsigned long)line.length);
    // The draft is kept, the chat closure is not attempted, and nothing is retried.
    _problem = @"notSent";
    [self setState:AKChatComposerStateFailed];
}

- (void)cancel {
    [self endSessionWithReason:@"cancel" clearDraft:YES];
}

- (void)appDidBackground {
    // The words are kept: returning to the app must not cost the player what they wrote, and
    // coming back must never send it.
    [self endSessionWithReason:@"background" clearDraft:NO];
}

- (void)controllerDidDisconnect {
    [self endSessionWithReason:@"disconnect" clearDraft:NO];
}

- (void)composerWasTurnedOff {
    // Rollback: ephemeral work goes, mappings and destinations stay for a later re-enable.
    [self endSessionWithReason:@"rollback" clearDraft:YES];
    AKLog(@"chat-composer: rollback complete; destinations and mappings were left alone");
}

- (void)endSessionWithReason:(NSString *)reason clearDraft:(BOOL)clearDraft {
    BOOL wasActive = _state != AKChatComposerStateIdle && _state != AKChatComposerStateCancelled;
    NSUInteger generation = ++_generation;
    [self requestCapture:NO generation:generation];
    // Chat is closed at most once, and only when this Composer opened it. No text is ever part
    // of a cancel: Escape is the only key this path may post.
    if (_ownsChat) {
        [self.target chatPostKey:AKChatKeyEscape characters:@"\x1b"];
        _ownsChat = NO;
    }
    if (clearDraft) { [self setDraft:@""]; _draftBeforeCapture = nil; }
    _provisional = NO;
    _problem = nil;
    AKLog(@"chat-composer: %@ generation=%lu active=%d draft=%lu characters%@",
          reason, (unsigned long)generation, (int)wasActive, (unsigned long)self.draft.length,
          clearDraft ? @"" : @" (kept)");
    if (!wasActive) {
        // Nothing to clean up. Said out loud, because "cancel did nothing" and "cancel cleaned
        // up" must not look the same in a log.
        [self publish];
        return;
    }
    [self setState:AKChatComposerStateCancelled];
}

- (void)resetForTesting {
    // A fixture runs case after case in one process; the app never does this. The generation
    // keeps counting, because a stale callback in a test must stay stale for the same reason it
    // is stale in the app.
    _generation++;
    _state = AKChatComposerStateIdle;
    _draft = @"";
    _draftBeforeCapture = nil;
    _problem = nil;
    _provisional = NO;
    _ownsChat = NO;
    [self publish];
}

@end
