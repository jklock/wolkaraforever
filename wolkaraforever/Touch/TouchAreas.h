#import <UIKit/UIKit.h>
#import "TouchContract.h"

NS_ASSUME_NONNULL_BEGIN

/// TouchPlay's buttons, played by the fingers (iPad touch only).
///
/// The TouchPlay add-on draws the buttons in the game and saves where they are (TouchContract.h).
/// This turns a finger on one of them into that button's keys, and draws the app's feedback:
///
/// - A finger that comes down inside an area is that area's, and the host's 1.0.8 gestures never
///   see it. The area lights at once (a soft pale-gold edge glow round it, TouchPlay's press look).
/// - `pressKey` (Jump, Dive): key down when the finger comes down, key up when it lifts or is
///   cancelled - held as long as the finger is.
/// - `holdKey`: a finger kept on the area shows a ring after 0.15 s that fills over the contract's
///   hold time; when it is full the hold key is sent (down, then up), the ring pops, and that finger
///   sends nothing more.
/// - Lifted on the area before a hold: the tap key, down then up, at the lift. An area without a hold
///   key taps however long the finger stayed.
/// - Slid more than 10 pt out of its area before a hold: the tap key once, at that moment (the game
///   starts ground aiming), and the ring greys and shrinks. Off a spell (spell1 ... spell7) the finger
///   then aims (mockups 23, 24): the host's pointer jumps to it and follows it, so the game's circle
///   is under the finger; lifted on the world it is a left click there (the spell lands). Lifted over
///   any button - Interact, the Cancel button while aiming, or any other - it stops the aim: Interact's
///   hold key, which the add-on binds to a hidden "stop" button (stops targeting, only while there is
///   any), down and up; never a click on that button, never Escape (which opens the game menu when
///   nothing is aimed). Cancelled, or let go of by a reload or a size change, it stops the aim the same
///   way. A contract whose Interact has no hold key: the stop sends nothing. Off any other button than a
///   spell the finger sends nothing more.
///   While a spell is aimed, a separate world tap by another finger also places it: the game takes that
///   tap's left click; the aiming finger's own lift then clicks (or stops) as above.
/// - The `chat` strip is the one area that sends no key (ruling A7): lifted on it before sliding off, it posts
///   AKTouchChatAreaTappedNotification and the controls open the app's chat keyboard; slid off, nothing.
/// - Every finger follows these rules on its own.
///
/// Each key goes out with control, option and shift (TouchPlay binds ALT-CTRL-SHIFT-x, the game's own order;
/// older files say CTRL-ALT-SHIFT-x, the same chord to this reader): pressed before
/// the key event and released a few of the game's frames after it (patch 0071: the game reads them in its
/// frame), shared by a tap's down and up; other input waits for them meanwhile. TouchPlay's secure buttons act
/// on the up click, so a tap is always a down and an up. A key name the reader does not know is no
/// key: that gesture sends nothing.
///
/// Nothing here runs without a contract: no contract, no claimed touch, and the host's own gestures
/// are exactly what they were (plain taps). The host makes this only in iPad touch mode.

/// Posted (main thread, object: the areas) when a finger lifts on TouchPlay's `chat` strip before sliding off
/// it (ruling A7). That area's chord is never sent: the controls open the app's chat keyboard instead, whose
/// Send is F12 (TouchPlay binds plain F12 to open the chat) + the line + Return.
FOUNDATION_EXPORT NSNotificationName const AKTouchChatAreaTappedNotification;   // "AKTouchChatAreaTapped"

/// What the host implements to send a key with its modifiers (patch 0066, AppKit.m).
@protocol AKTouchKeySink <NSObject>
/// One key event with `modifiers` (NSEventModifierFlags bits) pressed just before it and released once the
/// game has had it for a frame or more (patch 0071); `modifiers` 0 is a bare key.
- (void)touchKey:(unsigned short)code characters:(NSString *)characters modifiers:(NSUInteger)modifiers pressed:(BOOL)pressed;
/// The pointer to `p` (the view's coordinates, no button down); with `click`, then a left click there.
- (void)touchPointerAt:(CGPoint)p click:(BOOL)click;
@optional
/// The app is being put away (a call, Control Centre, the app switcher, Home; Task 8): lets go of the world
/// gesture a finger started - a mouse button held by a drag comes up, a tap or hold still waiting never
/// fires - and keeps the rest of that finger's gesture quiet until it lifts. Patch 0070.
- (void)touchReleaseWorldGesture;
@end

/// The host that keys go to (held weakly). The host view sets itself when it makes its areas.
FOUNDATION_EXPORT void AKTouchSetKeySink(id<AKTouchKeySink> _Nullable sink);
/// One key down or up through the host's key path, with `mods` around it; nothing without a host.
FOUNDATION_EXPORT void AKTouchSendKey(uint16_t code, NSUInteger mods, BOOL down);
/// The walk stick's movement keys (TouchGamepad.m): the game's own W, A, S and D, sent bare.
///
/// Ruling A22: the host sends a key by its code, so a TouchPlay chord on one of these codes (an older
/// add-on had CTRL-ALT-SHIFT-D, -A and -S) would release the held walk key with its up, or repeat its down.
/// So a contract key on one of these codes is no key (TouchAreas, logged once per key name): no chord is ever
/// sent on a walk key's code, and nothing has to repair a held walk key afterwards.
enum { AKTouchWalkKeyA = 0, AKTouchWalkKeyS = 1, AKTouchWalkKeyD = 2, AKTouchWalkKeyW = 13 };
FOUNDATION_EXPORT BOOL AKTouchIsWalkKeyCode(uint16_t code);
/// A walk key down or up, bare, through the host's key path.
FOUNDATION_EXPORT void AKTouchSendWalkKey(uint16_t code, BOOL down);
/// Lets go of the host's world gesture (mouse buttons up); nothing without a host or on a host without it.
FOUNDATION_EXPORT void AKTouchReleaseWorldGesture(void);
/// The pointer through the host (a spell being aimed): moved to `p`, then clicked there with `click`.
FOUNDATION_EXPORT void AKTouchSendPointer(CGPoint p, BOOL click);
/// The characters a Mac reports for key `code` (a letter, a digit, or the function key's private-use
/// character); empty for a code TouchPlay does not use.
FOUNDATION_EXPORT NSString *AKTouchCharactersForKeyCode(uint16_t code);

/// The press glow (18 Nov 2026, TouchPlay's press look): a soft pale-gold (1, 0.9, 0.55) edge 2 pt outside the area, a faint
/// wash inside and a soft gold shadow, in the area's shape (round areas a circle, the rest a rounded rectangle whose corner
/// suits the size); drawn the frame the finger lands, faded out over 120 ms from the lift (Reduce Motion: lit 120 ms,
/// then gone).
@interface AKTouchPressView : UIView
@property (nonatomic, readonly, copy) NSString *areaName;
/// Once the finger has lifted: the opacity animation it goes with (a fade, or a hold under Reduce Motion); for tests.
@property (nonatomic, readonly, nullable) CABasicAnimation *letGoAnimation;
@end

typedef NS_ENUM(NSInteger, AKTouchHoldRingState) {
    AKTouchHoldRingFilling,     // the finger is still down; `progress` is how full
    AKTouchHoldRingDone,        // full: the hold key went out, the ring pops and fades
    AKTouchHoldRingCancelled,   // the finger slid off or was cancelled: grey, shrinking, fading
};

/// The hold ring: 5 pt, fills gold over the hold time, pops when full, greys and shrinks when the
/// finger slides off.
@interface AKTouchHoldRing : UIView
@property (nonatomic, readonly) AKTouchHoldRingState state;
@property (nonatomic, readonly) CGFloat progress;   // 0...1
/// The small grey finger dot in the centre while the ring fills (mockup 10, "Filling"); hidden once the
/// ring pops or is cancelled.
@property (nonatomic, readonly) CALayer *fingerDot;
@end

@interface AKTouchAreas : NSObject
/// Areas over `view` (rectangles from its bounds, feedback drawn in it), with the current contract
/// (AKTouchCurrentContract), re-read when AKTouchContractDidChangeNotification says the player saved
/// new buttons.
- (instancetype)initWithView:(UIView *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
/// The areas most recently made over `view` (the host's, in iPad touch), while they exist; nil otherwise.
/// The walk stick asks this for the contract and for `claimsPoint:`, so it never reaches into the host.
+ (nullable AKTouchAreas *)areasForView:(nullable UIView *)view;

/// The contract in use; nil means plain taps (nothing is claimed). Setting it lets go of every finger
/// (a held key is released) and keeps the new one.
@property (nonatomic, strong, nullable) AKTouchContract *contract;

/// Each returns YES when the finger is (or was, for the last call) one of an area's: the caller then
/// does nothing else with it. `p` is in the view's coordinates.
- (BOOL)touchBegan:(UITouch *)t at:(CGPoint)p;
- (BOOL)touchMoved:(UITouch *)t at:(CGPoint)p;
- (BOOL)touchEnded:(UITouch *)t at:(CGPoint)p;
- (BOOL)touchCancelled:(UITouch *)t;

/// The host's form: offers every finger in `touches` (`phase` is Began, Moved, Ended or Cancelled)
/// and returns the ones no area took, for the 1.0.8 gestures.
- (NSSet<UITouch *> *)unclaimedTouches:(NSSet<UITouch *> *)touches phase:(UITouchPhase)phase;
/// Whether `t` is a finger an area holds.
- (BOOL)ownsTouch:(UITouch *)t;
/// Whether a finger landing at `p` would be an area's, with this instance's contract and the view's size:
/// the one "is this a button" question (the host's pinch recognizer, and the walk stick's carve-out).
- (BOOL)claimsPoint:(CGPoint)p;
/// Whether TouchPlay's buttons are on screen now (default YES). NO: no area claims a finger (every touch is the
/// host's, as with no contract) and every held key is let go; the contract is kept. A single switch, so a later
/// in-world signal from the add-on (its buttons are not drawn on the login and character screens) only has to
/// set it (ruling A24).
@property (nonatomic, getter=isLive) BOOL live;
/// The contract while the buttons are on screen: `contract` when live, nil when not. The host's world touch (patch
/// 0069) asks this where it used to ask `contract`, so out of the world (login, character select, TouchPlay Off)
/// every touch is 1.0.8's plain touch, exactly as with no contract.
@property (nonatomic, readonly, nullable) AKTouchContract *liveContract;
/// Whether the add-on says a window or panel is open while the player is still in the world (ruling A32, three pulses).
/// Only ever YES with `live` NO: every other touch is plain, as out of the world, but the walk stick stays live in its stick box
/// (the rest ring's square and the lock above it, A34b) - it walks, locks and stops an auto-run (ruling A34, replacing A32's "the stick stops, an auto-run keeps going"; the host's
/// pinch skips its thumb, patch 0072). Set with `setLive:windowOpen:`; setting `live` alone clears it.
@property (nonatomic, readonly, getter=isWindowOpen) BOOL windowOpen;
/// Sets `live` and `windowOpen` together (`windowOpen` is kept only with `live` NO) and posts one
/// AKTouchAreasLiveDidChangeNotification if either changed, so a listener reads both already set.
- (void)setLive:(BOOL)live windowOpen:(BOOL)windowOpen;
/// Posted (object: the areas) after `live` or `windowOpen` changes. The walk stick lets go of everything out of the world
/// (neither live nor a window open), and of nothing with a window open (ruling A34).
FOUNDATION_EXPORT NSNotificationName const AKTouchAreasLiveDidChangeNotification;   // "AKTouchAreasLiveDidChange"
/// Fingers an area holds now.
@property (nonatomic, readonly) NSUInteger activeFingerCount;

/// Lets go of every finger: held press keys are released, nothing is tapped.
- (void)cancelAll;

/// Holds `t` quietly until it lifts: its moves and lift are swallowed and send nothing. The host gives
/// it the fingers that land in the 20 pt edge zone (iPad touch with a contract).
- (void)keepQuiet:(UITouch *)t;
/// The contract's world key (TouchPlay shows the card of what is under the cursor), down then up, with
/// its modifiers. NO, and nothing sent, with no contract or a key name the reader does not know.
- (BOOL)sendWorldKey;

/// Advances the hold timing to the clock's now. A timer calls it while a finger is waiting; tests
/// call it after moving their clock.
- (void)tick;
/// The clock (seconds). The default is the system uptime; tests give their own.
@property (nonatomic, copy, null_resettable) NSTimeInterval (^clock)(void);
/// Where keys go. The default is AKTouchSendKey; tests record.
@property (nonatomic, copy, null_resettable) void (^keySender)(uint16_t code, NSUInteger mods, BOOL down);
/// Where an aiming finger moves the pointer and clicks. The default is AKTouchSendPointer; tests record.
@property (nonatomic, copy, null_resettable) void (^pointerSender)(CGPoint p, BOOL click);
/// Whether Reduce Motion is on (the press glow then drops instead of fading). The default asks UIAccessibility; tests give
/// their own.
@property (nonatomic, copy, null_resettable) BOOL (^reduceMotion)(void);

/// The feedback a finger has now (for tests and the host).
- (nullable AKTouchPressView *)pressViewForTouch:(UITouch *)t;
- (nullable AKTouchHoldRing *)holdRingForTouch:(UITouch *)t;

/// The "touch buttons not found" notice: shown in the view once per game start (process), when there
/// is no contract, for about six seconds; it never takes a touch. Nil when it was not shown. Not while the buttons
/// are not live (login, character select: ruling A24): it waits, and is shown when they go live with no contract.
@property (nonatomic, readonly, nullable) UIView *missingNotice;
/// Shows the notice if this game has no contract and it was not shown yet. Called by the host once it
/// has a size; returns whether it was shown now.
- (BOOL)showMissingNoticeIfNeeded;
@end

/// Where the app's toolbar (and its folded handle) sits in iPad touch: always the top-centre band (8 pt below the safe area's
/// top), folded or open, in the world, out of it or with a window open, keyboard up or not (run 5: the old bottom-centre
/// place out of the world put the open toolbar's keyboard button over TouchPlay's info card). TouchPlay keeps that band
/// clear; should its buttons reach it anyway, the toolbar moves along the top row to the nearest spot 8 pt clear of every
/// area's rectangle (the press glow's edge is 2 pt outside it) and 8 pt inside the screen's sides - for the open toolbar
/// (208 x 44), else the folded handle (96 x 34) - but only within a fifth of the width of the centre; otherwise the centre
/// with `clear` NO. Folded and open share the dock, so the handle does not jump when it opens. No contract, or no areas:
/// the centre. A pure function of its arguments: no view is read.
typedef struct {
    CGFloat centreX;    // the toolbar's middle, in the view's points
    BOOL clear;         // NO: nothing clear near the centre (the centre is returned)
} AKTouchToolbarDock;
FOUNDATION_EXPORT AKTouchToolbarDock AKTouchToolbarDockFor(AKTouchContract *_Nullable contract, CGSize viewSize, UIEdgeInsets safeInsets,
                                                         CGSize openSize, CGSize foldedSize);
/// The margin kept around every area, and from the screen's sides.
FOUNDATION_EXPORT const CGFloat AKTouchToolbarMargin;           // 8

/// Times, in seconds, and distances, in points (the plan's Global Constraints).
FOUNDATION_EXPORT const NSTimeInterval AKTouchHoldRingDelay;    // 0.15
FOUNDATION_EXPORT const CGFloat AKTouchDragOffDistance;         // 10
FOUNDATION_EXPORT const NSTimeInterval AKTouchMissingNoticeSeconds;  // 6

NS_ASSUME_NONNULL_END
