// WolkaraForever: the Battery Saver choice, and the one place that turns it into a
// frame rate.
//
// Three images read this file and must agree about it: the launcher (which draws the
// submenu and writes the choice), the Metal adapter (which paces presentation), and the
// AppKit adapter (which owns the idle coordinator and the dim layer). One source file,
// overlaid at each path, so the schema and the resolution rule cannot drift apart.
//
// What it is not. Nothing here writes a game CVar, a Config.wtf entry or any other game
// data. The cap lives entirely in the presentation call this app makes on the game's
// behalf, and "Off" makes no call at all.
//
// Every stored value is validated on the way in: an unknown string, an old spelling or a
// number the app never offered resolves to Off, which is what an installation that has
// never touched the submenu already behaves like.
//
// Applies to the next game launch. The launcher copies the selection into a snapshot when
// it starts the guest, and the guest-side adapters read the snapshot only. Changing the
// submenu while a game is running therefore cannot change the session that is playing.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Keys and spellings

/// The frame limit the user selected: "off", "auto", "30" or "60".
FOUNDATION_EXPORT NSString *const AKBatterySaverFrameLimitDefaultsKey;   // "WolkaraForeverBatterySaverFrameLimitV1"
/// The idle timeout in minutes: 0 (off), 2, 5 or 10.
FOUNDATION_EXPORT NSString *const AKBatterySaverAFKMinutesDefaultsKey;   // "WolkaraForeverBatterySaverAFKMinutesV1"
/// The snapshot taken when the launcher starts a guest. Read by the adapters, written by
/// the launcher and by nothing else.
FOUNDATION_EXPORT NSString *const AKBatterySaverLaunchFrameLimitDefaultsKey;
FOUNDATION_EXPORT NSString *const AKBatterySaverLaunchAFKMinutesDefaultsKey;

FOUNDATION_EXPORT NSString *const AKBatterySaverFrameLimitOffName;        // "off"
FOUNDATION_EXPORT NSString *const AKBatterySaverFrameLimitAutomaticName;  // "auto"
FOUNDATION_EXPORT NSString *const AKBatterySaverFrameLimit30Name;         // "30"
FOUNDATION_EXPORT NSString *const AKBatterySaverFrameLimit60Name;         // "60"

/// The fixed rate a dimmed session is held at, whatever was chosen.
FOUNDATION_EXPORT const double AKBatterySaverDimFramesPerSecond;          // 10

typedef NS_ENUM(NSInteger, AKBatterySaverFrameLimit) {
    /// No cap: the presentation call is the game's own, untouched. The default.
    AKBatterySaverFrameLimitOff = 0,
    /// 30 FPS on battery, 60 FPS on external power.
    AKBatterySaverFrameLimitAutomatic,
    AKBatterySaverFrameLimit30,
    AKBatterySaverFrameLimit60,
};

#pragma mark - Reading and writing the stored choice

/// A stored value resolved against the schema. Anything that is not one of the four
/// spellings is Off - never a nearest guess, because a cap nobody asked for is worse than
/// no cap at all.
FOUNDATION_EXPORT AKBatterySaverFrameLimit AKBatterySaverFrameLimitFromStored(id _Nullable value);
/// The spelling a value is stored as, so the launcher and the file agree.
FOUNDATION_EXPORT NSString *AKBatterySaverFrameLimitStoredName(AKBatterySaverFrameLimit limit);
/// A stored value resolved to one of 0, 2, 5, 10. Anything else is 0 (off).
FOUNDATION_EXPORT NSInteger AKBatterySaverAFKMinutesFromStored(id _Nullable value);

/// What the submenu currently says. Validated on every read.
FOUNDATION_EXPORT AKBatterySaverFrameLimit AKBatterySaverStoredFrameLimit(void);
FOUNDATION_EXPORT NSInteger AKBatterySaverStoredAFKMinutes(void);

/// Write the selection. Validated before it is stored, so a caller cannot save a value the
/// readers would refuse.
FOUNDATION_EXPORT void AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit limit);
FOUNDATION_EXPORT void AKBatterySaverSetAFKMinutes(NSInteger minutes);

/// Copy the selection into the snapshot a starting guest reads. Called by the launcher
/// immediately before it starts the guest, and by nothing else.
FOUNDATION_EXPORT void AKBatterySaverCommitLaunchSnapshot(void);

/// What this guest was started with. Off and 0 when no snapshot was ever written, which is
/// also what a fixture that never ran the launcher sees.
FOUNDATION_EXPORT AKBatterySaverFrameLimit AKBatterySaverLaunchFrameLimit(void);
FOUNDATION_EXPORT NSInteger AKBatterySaverLaunchAFKMinutes(void);

#pragma mark - Resolution

/// The outcome of the policy: whether a cap applies now, and at what rate.
typedef struct AKBatterySaverFramePolicy {
    /// NO means the game's own presentation call is used unchanged.
    BOOL capped;
    /// The cap in frames per second. 0 while `capped` is NO.
    double framesPerSecond;
} AKBatterySaverFramePolicy;

/// The rule, on its own, with every input named. No device, no defaults database and no
/// clock, so a corpus of inputs can be checked without one.
///
///   Automatic  - 60 FPS on external power, 30 FPS on battery.
///   30 / 60    - that rate.
///   any cap    - Low Power Mode, or a Serious/Critical thermal state, lowers a rate above
///                30 FPS to 30 FPS. Off stays Off.
///   dimmed     - the AFK dim is in force: a fixed 10 FPS, whatever else says. The game is
///                not being looked at, and the panel does not need to be redrawn for it.
FOUNDATION_EXPORT AKBatterySaverFramePolicy AKBatterySaverFramePolicyMake(AKBatterySaverFrameLimit limit,
                                                                         BOOL externalPower,
                                                                         BOOL lowPowerMode,
                                                                         NSProcessInfoThermalState thermal,
                                                                         BOOL dimmed);

/// The same rule, reading the live device: the launch snapshot, the charger, Low Power Mode
/// and the thermal state. `dimmed` is the AppKit adapter's idle state.
FOUNDATION_EXPORT AKBatterySaverFramePolicy AKBatterySaverResolvedPolicy(BOOL dimmed);

/// Whether this device is on external power. Never changes the battery's own state: it
/// only reads it.
FOUNDATION_EXPORT BOOL AKBatterySaverDeviceHasExternalPower(void);

/// The interval a capped presentation must be held for, in seconds. 0 when the policy is
/// not capped.
FOUNDATION_EXPORT double AKBatterySaverFramePolicyInterval(AKBatterySaverFramePolicy policy);

#pragma mark - What the three images tell each other

/// AppKit adapter -> everyone. Posted on the main queue when the idle coordinator dims or
/// wakes. userInfo carries AKBatterySaverDimmedKey.
FOUNDATION_EXPORT NSNotificationName const AKBatterySaverDimDidChangeNotification;   // "AKBatterySaverDimDidChange"
FOUNDATION_EXPORT NSString *const AKBatterySaverDimmedKey;                           // "dimmed"

/// Launcher -> AppKit adapter. Posted when an input source the host cannot see itself
/// (a controller button, the controller touchpad relay) shows activity.
FOUNDATION_EXPORT NSNotificationName const AKBatterySaverActivityNotification;       // "AKBatterySaverActivity"
/// Diagnostic only: "controller", "controllerTouchpad". Never a device identifier.
FOUNDATION_EXPORT NSString *const AKBatterySaverActivitySourceKey;                   // "source"

NS_ASSUME_NONNULL_END
