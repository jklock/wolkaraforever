// WolkaraForever: the Chat Composer, one owner for an in-game message.
//
// Three asynchronous systems meet at one line of chat: UIKit's text and IME, the on-device
// recogniser, and the guest's own key events. Before this class each of them owned a piece of
// the lifecycle, so a final transcript could arrive after the text - and the Return - had
// already gone to the game. The Composer makes ownership explicit:
//
//   * the native card owns the editable draft;
//   * the guest sees committed text only, once, after the player presses Send;
//   * every capture carries a generation, and a callback from an older generation is ignored
//     before it can touch the draft or the game.
//
// It is deliberately view-free. The card, the draft editor and the keyboard rules live in
// TouchControls, which is the layer that already avoids the keyboard and already posts the
// guest's keys; this class decides *what* happens and in which order, so the whole state
// machine can be exercised without a window. `AKChatTextTarget` is the only thing it asks of
// the guest, and a test can implement it in thirty lines.
//
// Placement: this file is compiled into translation/AppKit, the signed compatibility library
// the app loads by name (see wolkaraforever/overlay.map). It has to be there - the draft
// editor, the card and the guest's key path are all in that binary, and a Composer in the app
// would have to drive a panel it cannot link. See development/technical/CHAT_COMPOSER.md.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The states named in the plan, and no others. `cancelled` and `failed` are terminal: each
/// ends the session, says why in the log, and returns to `idle` on the next Open.
typedef NS_ENUM(NSInteger, AKChatComposerState) {
    AKChatComposerStateIdle = 0,
    AKChatComposerStateOpening,
    AKChatComposerStateListening,
    AKChatComposerStateEditing,
    AKChatComposerStateReady,
    AKChatComposerStateSending,
    AKChatComposerStateCancelled,
    AKChatComposerStateFailed,
};

/// Where the player started the Composer. Logged; never inferred.
typedef NS_ENUM(NSInteger, AKChatComposerSource) {
    AKChatComposerSourceToolbar = 0,
    AKChatComposerSourceKeyboard,
    AKChatComposerSourceController,
};

/// How a committed line reaches the game. `classicDirect` is everything WolkaraForever did
/// before the Composer existed and stays the meaning of an installation that predates it;
/// `review` is the Composer's review-then-Send.
typedef NS_ENUM(NSInteger, AKChatDeliveryMode) {
    AKChatDeliveryModeClassicDirect = 0,
    AKChatDeliveryModeReview,
};

/// Posted on the main queue whenever the state, draft or problem changed, so a card can
/// redraw. `AKChatComposerStateKey` carries the new state.
extern NSNotificationName const AKChatComposerDidChangeNotification;
extern NSString *const AKChatComposerStateKey;

/// The keys the delivery-mode readers share. Spelled here so the composer and the shell (which
/// cannot include this header - it is in the app, this is in the compatibility library) agree
/// on the spelling; the app names the same string in its own config schema.
extern NSString *const AKChatComposerEnabledKey;      // "AKChatComposerEnabled", BOOL
extern NSString *const AKChatDestinationsDefaultsKey; // "AKChatDestinationsV1", array of records

/// The mode that is in force, including the one-time migration. Reads (and on the first call
/// writes) `AKChatDeliveryMode`: an installation that has any voice setting from before the
/// Composer keeps `classicDirect`; anything else - a fresh install - starts in `review`, which
/// is the product default for new Composer users. Safe to call from any thread; the answer is
/// cached.
AKChatDeliveryMode AKChatDeliveryModeInForce(void);
/// Persist a mode. Called by the Composer's own settings sheet.
void AKChatDeliveryModeSet(AKChatDeliveryMode mode);
/// Whether the Composer may be used at all. Its own saved flag, default on, so a release can
/// turn the whole feature off without touching mappings or destinations.
BOOL AKChatComposerIsAvailable(void);
/// Forget the cached answer so the next reader sees what is stored now. For tests, and for the
/// settings sheet after it writes a new mode; the app itself reads one mode per launch.
void AKChatDeliveryModeResetCacheForTesting(void);

#pragma mark - Destinations

/// One player-configured destination: a title on a chip and the command it sends. Never
/// invented: until the player writes one there are none, and a message is just a message.
@interface AKChatDestination : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *command;
@property (nonatomic) BOOL enabled;
+ (instancetype)destinationWithIdentifier:(NSString *)identifier
                                    title:(NSString *)title
                                  command:(NSString *)command
                                  enabled:(BOOL)enabled;
@end

/// The stored destinations, validated on the way in and on the way out.
///
/// The limits are the ones `07-completion-spec.md` fixes: at most four records, a title of 24
/// visible characters, a command of 64 characters that is printable text with one leading
/// slash, unique identifiers and unique commands. A record that breaks a rule is dropped on
/// its own; its valid siblings are kept, because one hand-edited line is not a reason to lose
/// the other three.
///
/// The configuration file validates the same shape at its own boundary (see
/// Shell/WolkaraForeverConfig.m); these rules are repeated here because NSUserDefaults is
/// writable by anything in the process, so the runtime cannot assume the file was involved.
@interface AKChatDestinationStore : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, copy) NSArray<AKChatDestination *> *all;
@property (nonatomic, readonly, copy) NSArray<AKChatDestination *> *enabled;
/// Replace the whole list. Returns NO when nothing could be kept, and leaves what was stored.
- (BOOL)replaceAll:(NSArray<AKChatDestination *> *)destinations;
/// The rules, on their own, for a file or a defaults value that may be anything.
+ (NSArray<AKChatDestination *> *)sanitizedDestinations:(nullable id)raw;
+ (NSUInteger)maximumCount;
+ (NSUInteger)maximumTitleLength;
+ (NSUInteger)maximumCommandLength;
@end

#pragma mark - What the guest looks like from here

/// The Composer asks for exactly three things, and never for a view, a window search or a
/// peek at the guest's text. The object that implements this is the layer's touch controls:
/// it is the registered text input, it posts the guest's own key events, and it can say
/// whether its window is still there.
@protocol AKChatTextTarget <NSObject>
/// The target is still the registered one and can still reach the guest.
- (BOOL)chatTargetIsLive;
/// One Return: the game's chat shortcut. NO when it could not be asked (no guest, or a
/// password field has the keyboard, where a chat key has no business).
- (BOOL)chatOpen;
/// The committed line, exactly once. NO when nothing was delivered.
- (BOOL)chatInsertText:(NSString *)text;
/// One explicit guest key: Return (36) or Escape (53).
- (BOOL)chatPostKey:(unsigned short)code characters:(NSString *)characters;
@end

#pragma mark - The Composer

@interface AKChatComposer : NSObject

+ (instancetype)shared;

@property (nonatomic, weak, nullable) id<AKChatTextTarget> target;
/// Asked to start, end or abandon capture. The answer arrives through the `speech…` methods
/// below with the same generation, on the main queue. Set by the layer that reaches the
/// microphone (TouchControls -> the shell -> AKDictation).
@property (nonatomic, copy, nullable) void (^captureRequest)(BOOL start, NSUInteger generation);

@property (nonatomic, readonly) AKChatComposerState state;
@property (nonatomic, readonly) AKChatComposerSource source;
/// Monotonic. Every capture request, Send and Cancel moves it on; a callback that carries an
/// older number is ignored before it can change the draft or post a key.
@property (nonatomic, readonly) NSUInteger generation;
/// The visible draft. Empty rather than nil when there is nothing.
@property (nonatomic, copy, readonly) NSString *draft;
/// Why the session ended badly, as a code the card localizes: `notSent` or `nothingHeard`.
/// Nil otherwise. Never a sentence, because the card is the only place that knows the app's
/// language - this class is in the compatibility library and must not decide it.
@property (nonatomic, copy, readonly, nullable) NSString *problem;
/// Whether the microphone is live for this session (listening and finalising count).
@property (nonatomic, readonly) BOOL capturing;
/// Whether the draft can still be edited: true while listening, editing or ready.
@property (nonatomic, readonly) BOOL draftEditable;
/// Whether Send would do anything. False for an empty draft, a provisional result and any
/// state that is not a session.
@property (nonatomic, readonly) BOOL canSend;

#pragma mark Entry and editing

/// Open the Composer. Returns NO when it is already open, when the feature is off, or when the
/// guest could not be asked to open its chat - in which case nothing is left open behind.
- (BOOL)openWithSource:(AKChatComposerSource)source;
/// The player changed the text. Capture is paused first: words arriving afterwards belong to a
/// generation that is no longer in force.
- (void)userChangedDraft:(NSString *)text;
/// Pause capture without changing the draft, for a keyboard that is about to take over.
- (void)pauseForEditing;
/// Start capture again for the same draft, after a pause or an explicit stop. A no-op while the
/// microphone is already live or when the draft is no longer editable.
- (void)resumeCapture;

#pragma mark Speech, from the layer that owns the microphone

- (void)speechDraft:(NSString *)text provisional:(BOOL)provisional generation:(NSUInteger)generation;
- (void)speechFinished:(nullable NSString *)text generation:(NSUInteger)generation;
- (void)speechFailed:(NSString *)reason generation:(NSUInteger)generation;
/// Capture ended without a result (a cancel, a timeout, an app going away).
- (void)speechStoppedWithReason:(NSString *)reason generation:(NSUInteger)generation;

#pragma mark The transaction

/// Send exactly once: the destination's command and the draft become one line, the text is
/// inserted once, Return once, and Escape once only when this Composer opened the chat.
/// A duplicate Send is ignored; a failure before the text goes in keeps the draft and never
/// retries.
- (void)sendWithDestination:(nullable AKChatDestination *)destination;
- (void)cancel;
- (void)appDidBackground;
- (void)controllerDidDisconnect;

#pragma mark Rollback

/// The saved flag was turned off. Ephemeral work is abandoned and the draft is dropped;
/// mappings and destinations stay for a later re-enable.
- (void)composerWasTurnedOff;

#pragma mark Tests

/// Where the draft goes for a test that must not touch the guest. Nil in the app.
@property (nonatomic, copy, nullable) void (^testOnlyCapture)(BOOL start, NSUInteger generation);
/// Back to a closed session without consulting a guest, so a fixture can run case after case.
- (void)resetForTesting;

@end

NS_ASSUME_NONNULL_END
