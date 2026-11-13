// WolkaraForever: the voice settings, where every part of the feature is decided.
//
// Modelled on Handy's, because it has already worked out what these options should
// be: hold to talk or tap to toggle, whether to send after inserting, a dictionary of
// words to recognise, and - our own addition - a mapping that can come from any
// button on any controller.
//
// Two rules come straight out of the 2026-10-16 audit and are the reason this class
// looks the way it does:
//
//   1. **Off until asked for.** `enabled` is NO until the user turns it on, and there
//      is no default trigger and no fallback. Nothing listens, nothing is mapped, and
//      no system gesture is held, until a person has said so.
//   2. **The mode owns the pattern.** A mapping stores which *element* the user chose;
//      whether that means hold-to-talk or press-to-toggle is the mode, read at the
//      time. Storing the pattern as well let the two disagree after a mode change.

#import <Foundation/Foundation.h>
#import "Trigger.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AKVoiceMode) {
    // Hold the button to talk, release to finish. Handy's default.
    AKVoiceModeHold = 0,
    // Press once to start, once more to stop.
    AKVoiceModeToggle,
};

// The language the recogniser listens in. On-device recognition is per locale, so this is
// recognition configuration rather than app chrome: it never follows the app's own language
// (`WolkaraForeverAppLanguage`), and changing the app language never changes it.
//
// The list is deliberately small. `System` means whatever the iPad itself recognises, which is
// what the app used to do implicitly and what an invalid stored value falls back to. The three
// named languages are the ones this product's copy ships in; Spanish is the game's fourth text
// locale and is offered as the current game-text choice. Anything else is refused rather than
// guessed at.
typedef NS_ENUM(NSInteger, AKVoiceSpeechLanguage) {
    AKVoiceSpeechLanguageSystem = 0,
    AKVoiceSpeechLanguageEnglish,   // en-US
    AKVoiceSpeechLanguageGerman,    // de-DE
    AKVoiceSpeechLanguageFrench,    // fr-FR
    AKVoiceSpeechLanguageSpanish,   // es-ES, the game's fourth text locale
};

@interface AKVoiceSettings : NSObject

+ (instancetype)shared;

// The whole feature, on or off. Off means: no trigger fires, nothing is mapped, and
// the system keeps its own gestures. Default NO.
@property (nonatomic) BOOL enabled;

@property (nonatomic) AKVoiceMode mode;
// The language the recogniser listens in. Default System. Validated before it is stored: an
// unrecognised value - a hand-edited config file, a value from a later build - becomes System
// rather than being written back, so migration cannot leave the recogniser pointed at a
// language this build has never heard of.
@property (nonatomic) AKVoiceSpeechLanguage speechLanguage;
// The BCP-47 identifier the recogniser should be constructed with, or nil for System. Read by
// the recogniser at the start of each capture, never cached by a caller.
@property (nonatomic, readonly, copy, nullable) NSString *speechLanguageIdentifier;
// The stored spelling, and the setting a stored spelling means. Anything unrecognised, including
// a missing value, is System.
+ (NSString *)storedValueForSpeechLanguage:(AKVoiceSpeechLanguage)language;
+ (AKVoiceSpeechLanguage)speechLanguageForStoredValue:(nullable id)value;
// The identifier for a language, or nil for System. The one place the mapping lives.
+ (nullable NSString *)identifierForSpeechLanguage:(AKVoiceSpeechLanguage)language;
// The choices the page offers, in order.
+ (NSArray<NSNumber *> *)speechLanguageChoices;
// Send Return once the transcript has been typed in.
@property (nonatomic) BOOL autoSubmit;
// A space after the text, for a field that needs one.
@property (nonatomic) BOOL trailingSpace;
// Words the recogniser should expect: names, places, game terms. Handy calls this the
// dictionary; the SDK calls it contextualStrings.
@property (nonatomic, copy) NSArray<NSString *> *customWords;

// The mapping for a device, or nil when there is none - which is the normal state
// until the user makes one. Never invents a trigger.
- (nullable AKTrigger *)triggerForDevice:(nullable NSString *)device;
// Remember a learned trigger for the device it came from.
- (void)setTrigger:(AKTrigger *)trigger forDevice:(nullable NSString *)device;
// Adopt the element that was just pressed, using the pattern this mode needs.
- (void)setLearnedElement:(NSString *)element forDevice:(nullable NSString *)device;
// Remove a mapping, so the device fires nothing at all.
- (void)clearMappingForDevice:(nullable NSString *)device;

// Moves a mapping made by an older build - keyed by the vendor name alone - onto the
// controller's own identity, once, the first time that controller is seen. Returns
// YES if it moved one.
- (BOOL)adoptLegacyMappingForDevice:(NSString *)device vendor:(nullable NSString *)vendor;

// How the mapping reads in the launcher: "Share (screenshot) (hold to talk)",
// "Key 70 (press)", "Not set".
- (NSString *)mappingSummaryForDevice:(nullable NSString *)device;

// Whether the game is also to be kept from seeing the button the user mapped. Off by
// default, because on is a real change to how the game behaves: with it off the mapping
// only listens, and a button the game uses does both things at once. With it on, a key
// the user has taken for dictation does not reach the game at all - see
// `-ownsElement:` for exactly which inputs that covers, and which it cannot.
@property (nonatomic) BOOL takeButtonFromGame;

// The whole decision, in one place, asked by the input router on behalf of the adapter at
// the point where guest key events are posted: is this element mapped for dictation, and
// has the user asked for the game not to see it?
//
// What it cannot cover: a *controller* button. iPadOS gives us the pad's buttons as
// gamepad elements, and the guest receives them as key events we have no way to identify -
// there is no API that says which HID usage a given pad button becomes. So a pad mapping
// cannot be taken from the game, and the app says so on the page rather than pretending.
// A keyboard key can be, because both the observation and the forwarding name it the same
// way. A system signal can never be: there is nothing to swallow, and the layer already
// releases the system gesture for the element it holds.
- (BOOL)ownsElement:(NSString *)element;

// The keyboard usages that follow from `ownsElement:` - the elements of the form
// `keyboard.key.<usage>` that are mapped and taken. The shell publishes this set to the
// adapter, which is a dylib it does not link against: the adapter cannot ask about a mapping,
// so it is told which keys to swallow before the guest sees them.
- (NSSet<NSNumber *> *)ownedKeyUsages;

#pragma mark - Keeping one controller button out of the game

// Whether this build can hold back *one selected controller button* before the game sees it.
//
// NO, and the answer is measured rather than assumed. iPadOS hands a physical pad's buttons to
// every observer in the process, and the guest is an observer this app does not own: it links the
// real GameController framework and reads `GCController.controllers` itself. An app can give a
// button back to the system (`preferredSystemGestureState`), install a `pressedChangedHandler` -
// one per element, so installing ours replaces the guest's rather than sparing it - or read a
// value. None of those removes a press from another reader. The one build that could, the
// `translation/GameController` adapter, hides every pad from every application, so it cannot claim
// one button and preserve the rest.
//
// The settings therefore keep the note that already says so, and do not offer a switch that could
// do nothing. `setControllerClaimSeamAvailableForTesting:` exists so the restore paths below are
// exercised now rather than written blind for the day this answer changes.
@property (class, nonatomic, readonly) BOOL controllerClaimIsAvailable;
+ (void)setControllerClaimSeamAvailableForTesting:(BOOL)available;

// The persistence that does not depend on the answer above: one canonical controller button per
// controller identity, default false, never invented. Read by this build, written only by a build
// that can actually claim - so a preference made elsewhere is kept rather than dropped.
- (BOOL)isElement:(NSString *)element claimedForDevice:(nullable NSString *)device;

// Ask to hold one element of one controller back. NO - and nothing stored - when there is no seam
// to honour it, or when the element is not a controller button: a stored "yes" that nothing
// applies is worse than no record, because the page would then describe a state the app is not in.
- (BOOL)claimElement:(NSString *)element device:(nullable NSString *)device;
- (void)releaseClaimForElement:(NSString *)element device:(nullable NSString *)device;

// What is held back right now, by element id. Empty in this build.
@property (nonatomic, readonly, copy) NSSet<NSString *> *claimedElements;

// Disable, disconnect, background, route failure, app exit: everything held back becomes the
// game's again at once, and each one says so in `controller-input`. The saved preference stays,
// so switching the feature back on restores the same choice. `reason` is one of
// `disable`, `disconnect`, `background`, `route-failure`, `exit`.
- (void)releaseClaimsWithReason:(NSString *)reason;


// Fired when anything above changes, so the launcher can redraw and the input router
// can re-decide which system gestures are ours to hold.
extern NSNotificationName const AKVoiceSettingsDidChangeNotification;

@end

NS_ASSUME_NONNULL_END
