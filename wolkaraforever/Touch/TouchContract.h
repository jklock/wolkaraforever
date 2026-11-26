#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// TouchPlay's button list, "contract v1".
///
/// The TouchPlay add-on draws the touch buttons inside the game and, when the player saves its
/// settings, writes one line into its account-wide saved variables file:
///
///   ["contract"] = "TPC1;hold=0.45;hand=R;turn=1;world=ALT-CTRL-SHIFT-F1;areas=<area>|<area>|...",
///
/// Each area is `<name>,<anchor>,<dx>,<dy>,<w>,<h>,<tap>,<hold>,<press>`. This file reads that line
/// and turns it into rectangles and keys; it never writes anything. A file that is missing, cut
/// short, or from a newer TouchPlay (`TPC2`) is not guessed at: the answer is nil, and touch is
/// the plain 1.0.8 touch (a tap is a click), with one notice per game start.
///
/// It is compiled twice, like InterfaceMode: into the app (which loads the contract at game
/// start and tells the player when it is missing) and into the adapter library the guest runs in
/// (which reads it lazily from the game's own working directory, so it needs no handover).

/// The classes below exist in the app's image and in the adapter library's image, and one process
/// loads both. Two images that each implement a class of the same name make the Objective-C runtime
/// warn ("Class ... is implemented in both") and pick one at random, so the app's copy gets its own
/// names. The adapter's copy is the one that sits beside AppKit.h; the app's has no such neighbour.
#if !__has_include("AppKit.h")
#define AKTouchArea AKAppTouchArea
#define AKTouchContract AKAppTouchContract
#endif

/// One touch area. Units are layout units: one unit is the view's height / 1024 points.
@interface AKTouchArea : NSObject
@property (nonatomic, copy) NSString *name;      // spell1 ... dive, see the add-on plan
@property (nonatomic, copy) NSString *anchor;    // TL, TR, BL or BR: the screen corner dx and dy count from
@property (nonatomic) NSInteger dx, dy, w, h;
/// WoW key names ("ALT-CTRL-SHIFT-F2", or "CTRL-ALT-SHIFT-F2" from older TouchPlay); empty when the area has none for that gesture.
@property (nonatomic, copy) NSString *tapKey, *holdKey, *pressKey;
@end

@interface AKTouchContract : NSObject
@property (nonatomic) NSInteger version;         // always 1: other versions are not parsed
@property (nonatomic) double holdSeconds;        // how long a finger stays down to count as a hold
@property (nonatomic) BOOL leftHanded;           // hand L
@property (nonatomic) BOOL turnWithView;
/// YES only for the optional TPC1 field sheet=2.
@property (nonatomic) BOOL sheetPulses;
@property (nonatomic, copy) NSString *worldKey;
@property (nonatomic, copy) NSArray<AKTouchArea *> *areas;
/// ["feel"]["edgeRun"] from the same file; YES when the file does not say.
@property (nonatomic) BOOL edgeRun;
/// What the file said, in one string: the contract line and edgeRun. Two contracts with the same
/// signature are the same contract; a changed file with the same signature is not a change.
@property (nonatomic, copy) NSString *signature;
/// The optional `outline=` field (a device check): the names of the areas whose press the app outlines in gold - the ones
/// the add-on always draws something in. Nil when the field is absent (an add-on from before it): every area is
/// outlined, as before. Empty: none is. An older app ignores the field, as it ignores any field it does not know.
@property (nonatomic, copy, nullable) NSSet<NSString *> *outlineAreas;
/// Whether a press on the area called `name` is outlined: always without the field, else only a listed name.
- (BOOL)outlinesArea:(NSString *)name;
- (nullable AKTouchArea *)areaNamed:(NSString *)name;
@end

/// The contract in `fileText` (the whole TouchPlay.lua), or nil when it has no contract line, the
/// line is malformed or cut short, or its version is not 1.
FOUNDATION_EXPORT AKTouchContract *_Nullable AKTouchContractParse(NSString *_Nullable fileText);

/// The account-wide TouchPlay.lua the contract is read from: the most recently modified
/// `WTF/Account/<ACCOUNT>/SavedVariables/TouchPlay.lua` in the game folder (the folder holding
/// `WTF`; on the iPad `Documents/World of Warcraft/_forever_`). Exactly one level under the
/// account: a character's own file (`<ACCOUNT>/<realm>/<name>/SavedVariables`) holds only that
/// character's settings and is never matched. Nil when there is none.
FOUNDATION_EXPORT NSString *_Nullable AKTouchContractFilePath(NSURL *_Nullable gameFolder);

/// The key `AKTouchContractLoadForGame` passes to its notice when the contract could not be used:
/// "touch.contract.missing". The caller shows it in the app's language.
FOUNDATION_EXPORT NSString *const AKTouchContractMissingNoticeKey;

/// Loads the contract for one game start and makes it the current one. When there is none to use
/// (missing, unreadable, malformed, unknown version) the current contract is nil and `notice` is
/// called once, with `AKTouchContractMissingNoticeKey`. Call it once per game start.
FOUNDATION_EXPORT AKTouchContract *_Nullable AKTouchContractLoadForGame(NSURL *_Nullable gameFolder,
                                                                         void (^_Nullable notice)(NSString *key));

/// The contract for this game. Nil outside iPad touch mode, and nil when there was none to use,
/// which means plain taps. If nothing has loaded one in this process, the first call in iPad touch
/// mode reads it from the current working directory, which is the game folder; no notice then.
FOUNDATION_EXPORT AKTouchContract *_Nullable AKTouchCurrentContract(void);

/// ["feel"]["edgeRun"] of the current contract; YES when there is no contract or the file is silent.
FOUNDATION_EXPORT BOOL AKTouchContractEdgeRun(void);

/// Posted (on the main queue) when the watched file gave a different valid contract and it became the
/// current one; `object` is the new AKTouchContract. Not posted for a file that is unreadable, cut
/// short or unchanged: the previous contract stays.
FOUNDATION_EXPORT NSNotificationName const AKTouchContractDidChangeNotification;

/// iPad touch only: the player saves the add-on's settings with a reload, and the app has to see the
/// new buttons without a restart. Watches the game folder's TouchPlay.lua files (the files, their
/// SavedVariables folders and WTF/Account, because the game replaces the file rather than writing
/// into it) and, when something changes, re-reads the newest account's file: a valid, different
/// contract replaces the current one and posts the notification; an invalid or missing file keeps
/// the last good contract. A no-op outside iPad touch mode. Calling it again moves the watch.
/// AKTouchCurrentContract() starts it itself for the working directory when it reads lazily.
FOUNDATION_EXPORT void AKTouchContractWatch(NSURL *_Nullable gameFolder);

/// Forgets the current contract and what was loaded, so the next game start (or test) begins fresh.
FOUNDATION_EXPORT void AKTouchContractReset(void);

/// The area's rectangle in a view of `viewSize`, in points. The unit is height / 1024; `dx`, `dy`
/// and the size count from the anchor corner to the area's matching corner.
FOUNDATION_EXPORT CGRect AKTouchAreaRect(AKTouchArea *_Nullable area, CGSize viewSize);

/// The macOS virtual key code and modifiers (NSEventModifierFlags bits: control, option, shift)
/// for a TouchPlay key name: ALT, CTRL and SHIFT, each once and in any order, dash-separated, then
/// one of F1..F12, 1..9, 0, A..Z, F13..F19, NUMPAD0..NUMPAD9, NUMPADDECIMAL, NUMPADMULTIPLY, NUMPADPLUS,
/// NUMPADDIVIDE or NUMPADMINUS (70 keys; TouchPlay's pet, stance and Leave areas use the last 22). W, A, S, D
/// parse but TouchAreas refuses them as the walk stick's keys. The game's own order, which it looks bindings up by, is
/// "ALT-CTRL-SHIFT-F2"; older TouchPlay files say "CTRL-ALT-SHIFT-F2", the same chord. NO for
/// anything else (a missing or repeated modifier, META, lower case). `code` or `mods` may be NULL.
FOUNDATION_EXPORT BOOL AKTouchKeyCodeForName(NSString *_Nullable wowKey, uint16_t *_Nullable code, NSUInteger *_Nullable mods);

NS_ASSUME_NONNULL_END
