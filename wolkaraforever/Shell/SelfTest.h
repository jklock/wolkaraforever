// WolkaraForever: the checks the app can run on the device by itself.
//
// The device matrix can install the app, launch it, read its log and stop it, but it cannot
// press a button on a pad or speak into the microphone - so those paths were written off as
// "needs a person". This is the alternative: the app drives its own code, the same way the
// simulator fixtures stand in for a controller and a recogniser, and reports what happened in
// its own log, which is where the matrix reads it.
//
// What it exercises is WolkaraForever's own code - the input router, the settings, the dictation state
// machine and the real audio session. It never touches a running application, never presses
// anything in the game, and cannot be reached from the UI: it runs only when the app is
// launched with `--selftest=<name>`. Every stored setting it changes it puts back, including
// the user's own mappings, and it says so in the log when it is done.
//
// This is the product's own answer to "are we running every test we can". A build shipped
// without it would have to ask a person to press a pad button to prove the mapper works; with
// it, the same claim is a line in the device matrix.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The names `--selftest=` accepts. An unknown name fails, so a typo in the matrix cannot look
// like a pass.
extern NSString *const AKSelfTestInput;
extern NSString *const AKSelfTestVoice;
/// A bare recorder, opened the way Apple documents it, with none of the app's audio code in the path.
extern NSString *const AKSelfTestMic;
/// The object the touch controls registered as the game's text input, asked what it is. It
/// reads nothing from the game and types nothing; run it with `--local-game-startup`, because
/// the target exists only once the guest has started.
extern NSString *const AKSelfTestDictationTarget;
/// The home page's Forever rows, against the installation actually on the device: backup,
/// reset, restore and the gamepad write, each undone before the check finishes. It leaves the
/// user's UI as it found it (the restore at the end is the proof), and enables the performance
/// overlay so the in-game HUD can be seen; `forever-ui-clean` turns that back off.
extern NSString *const AKSelfTestForeverUI;
extern NSString *const AKSelfTestForeverUIClean;
/// The home page's own Render profile row, pressed on the installed build. It opens the sheet
/// and stops there: choosing a profile writes the user's graphics settings, which is what
/// `forever-ui` covers. What this proves is the thing no other check could - that pressing the
/// row does not terminate the app. It used to: the row built a sheet with its own Cancel and
/// handed it to a presenter that adds another, and UIKit raises on the second one.
extern NSString *const AKSelfTestRenderProfile;
/// The CurseForge key in this device's Keychain and the page it feeds: the key's shape, and
/// that the authenticated search answers with artwork, author, category and a file for the
/// game version the browser asks for. It reads nothing from the game and changes nothing.
extern NSString *const AKSelfTestCurseForge;
/// The recogniser alone, over Documents/dictation-probe.wav: a known sentence, run through the
/// exact request the app uses, on device. This is the only check that proves words come back
/// without a person speaking into the microphone.
extern NSString *const AKSelfTestSpeechFile;
/// The Controller Manager page, driven on the installed build: the switch's off default, that
/// switching it writes WolkaraForever's own key and nothing else, what the page says while
/// routing waits for a game session, and that switching it back undoes all of it. It presses
/// no pad and touches no game file; the routing itself still needs a controller in a hand.
extern NSString *const AKSelfTestControllerManager;
/// The routing chain itself, on the device and with no hardware: a hidden GCVirtualController
/// stands in for the physical pad, the manager attaches its real handlers to it, and a second
/// hidden one stands in for the pad the manager drives. A button, a trigger, a stick and the
/// D-pad are driven on the first and read back off the second, including a reassignment and
/// the release. What it cannot cover is a real pad's own hardware and iPadOS handing a reserved
/// button to this app - those need a pad in a hand.
extern NSString *const AKSelfTestControllerRouting;
/// The three situations the feature is defined by, each asserted on its own:
///   1. no physical controller        - the guest still has Tolkara's own gamepad, and nothing
///                                      changes about it whether capture is on or off;
///   2. physical controller, on       - the guest is offered the virtual gamepad and nothing
///                                      else, and never the pad being read;
///   3. physical controller, off      - the guest is offered the physical pad again, exactly as
///                                      before this feature existed.
extern NSString *const AKSelfTestControllerSituations;
/// What a pass-through press costs: microseconds from the framework entering the handler to the
/// adapter writing the value. The requirement is that this is what it is today, so it is a number
/// rather than an opinion.
extern NSString *const AKSelfTestControllerLatency;
/// The pad that is actually attached, against the rows the page draws for it: which elements
/// iPadOS reports, that every one of them becomes a row this pad has, and what the guest is
/// offered with capture on and off. The fixtures above stand in for hardware; this is the only
/// check that reads hardware. Run it with nothing attached and it fails rather than passes, so a
/// green line always means a pad was there.
extern NSString *const AKSelfTestControllerHardware;

// Runs one self-test and logs the verdict the matrix greps:
//   selftest: <name> PASS <passed>/<total> checks (<what was exercised>)
//   selftest: <name> FAIL <passed>/<total> checks: <the first thing that was wrong>
// The speech test finishes off the main thread - see SelfTest.m for why that is not optional -
// so the verdict is the return value only for the checks that finish synchronously. Read the
// line, not the return.
void AKRunSelfTest(NSString *name);

/// The same, with the launcher's home page in hand, for the checks that have to drive a control
/// on it rather than a page of their own. A plain launch passes its home controller here; the
/// device matrix, which only has a name, passes nil and those controls are reported as not run.
void AKRunSelfTestInHomePage(NSString *name, id _Nullable home);

// The name asked for on the command line, or nil. `--selftest=input` and `--selftest input`
// are both accepted.
NSString *_Nullable AKSelfTestRequestedFromArguments(NSArray<NSString *> *arguments);

NS_ASSUME_NONNULL_END
