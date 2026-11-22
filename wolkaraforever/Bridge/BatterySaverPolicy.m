#import "BatterySaverPolicy.h"

// The launcher and both adapters are iOS. The policy fixture runs on the Mac, where the
// charger rule is exercised through AKBatterySaverFramePolicyMake and no UIKit is needed.
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#define AK_BATTERY_SAVER_HAS_UIKIT 1
#endif

NSString *const AKBatterySaverEnabledDefaultsKey = @"WolkaraForeverBatterySaverEnabledV1";
NSString *const AKBatterySaverFrameLimitDefaultsKey = @"WolkaraForeverBatterySaverFrameLimitV1";
NSString *const AKBatterySaverAFKMinutesDefaultsKey = @"WolkaraForeverBatterySaverAFKMinutesV1";
NSString *const AKBatterySaverLaunchEnabledDefaultsKey = @"WolkaraForeverBatterySaverLaunchEnabledV1";
NSString *const AKBatterySaverLaunchFrameLimitDefaultsKey = @"WolkaraForeverBatterySaverLaunchFrameLimitV1";
NSString *const AKBatterySaverLaunchAFKMinutesDefaultsKey = @"WolkaraForeverBatterySaverLaunchAFKMinutesV1";
// One-time marker, so the migration below runs once and a later deliberate "Off" stays off.
static NSString *const AKBatterySaverModeMigratedKey = @"WolkaraForeverBatterySaverModeMigratedV1";

NSString *const AKBatterySaverFrameLimitOffName = @"off";
NSString *const AKBatterySaverFrameLimitAutomaticName = @"auto";
NSString *const AKBatterySaverFrameLimit30Name = @"30";
NSString *const AKBatterySaverFrameLimit60Name = @"60";

const double AKBatterySaverDimFramesPerSecond = 10.0;

NSNotificationName const AKBatterySaverDimDidChangeNotification = @"AKBatterySaverDimDidChange";
NSString *const AKBatterySaverDimmedKey = @"dimmed";
NSNotificationName const AKBatterySaverActivityNotification = @"AKBatterySaverActivity";
NSString *const AKBatterySaverActivitySourceKey = @"source";

#pragma mark - Reading and writing the stored choice

AKBatterySaverFrameLimit AKBatterySaverFrameLimitFromStored(id value) {
    if (![value isKindOfClass:NSString.class]) return AKBatterySaverFrameLimitOff;
    NSString *text = [(NSString *)value lowercaseString];
    if ([text isEqual:AKBatterySaverFrameLimitAutomaticName]) return AKBatterySaverFrameLimitAutomatic;
    if ([text isEqual:AKBatterySaverFrameLimit30Name]) return AKBatterySaverFrameLimit30;
    if ([text isEqual:AKBatterySaverFrameLimit60Name]) return AKBatterySaverFrameLimit60;
    // "off", a spelling this build does not know, and an old hand edit all mean the same
    // thing: no cap. Guessing a neighbouring value would switch on a cap the user never
    // chose.
    return AKBatterySaverFrameLimitOff;
}

NSString *AKBatterySaverFrameLimitStoredName(AKBatterySaverFrameLimit limit) {
    switch (limit) {
        case AKBatterySaverFrameLimitAutomatic: return AKBatterySaverFrameLimitAutomaticName;
        case AKBatterySaverFrameLimit30: return AKBatterySaverFrameLimit30Name;
        case AKBatterySaverFrameLimit60: return AKBatterySaverFrameLimit60Name;
        case AKBatterySaverFrameLimitOff: break;
    }
    return AKBatterySaverFrameLimitOffName;
}

NSInteger AKBatterySaverAFKMinutesFromStored(id value) {
    if (![value isKindOfClass:NSNumber.class]) return 0;
    // A boolean arrives as an NSNumber too, and `true` must not become a one-minute
    // timeout: only the four numbers the submenu offers are accepted.
    NSInteger minutes = [(NSNumber *)value integerValue];
    return (minutes == 2 || minutes == 5 || minutes == 10) ? minutes : 0;
}

AKBatterySaverFrameLimit AKBatterySaverStoredFrameLimit(void) {
    return AKBatterySaverFrameLimitFromStored(
        [NSUserDefaults.standardUserDefaults objectForKey:AKBatterySaverFrameLimitDefaultsKey]);
}

BOOL AKBatterySaverStoredEnabled(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // The two choices existed before the master switch did. An installation that had already
    // selected a frame limit or an AFK timeout asked for battery saving, and must not lose that
    // when the submenu moves behind a switch it has never been told about. An installation that
    // changed neither starts in full performance - the default this feature is meant to have.
    if (![defaults boolForKey:AKBatterySaverModeMigratedKey]) {
        BOOL asked = AKBatterySaverStoredFrameLimit() != AKBatterySaverFrameLimitOff ||
                     AKBatterySaverStoredAFKMinutes() != 0;
        if (asked) [defaults setBool:YES forKey:AKBatterySaverEnabledDefaultsKey];
        [defaults setBool:YES forKey:AKBatterySaverModeMigratedKey];
    }
    return [defaults boolForKey:AKBatterySaverEnabledDefaultsKey];
}

void AKBatterySaverSetEnabled(BOOL enabled) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // Marking the migration done here is what makes the choice stick: without it, a person who
    // switched the mode off while a frame limit was still stored would find it back on at the
    // next read.
    [defaults setBool:YES forKey:AKBatterySaverModeMigratedKey];
    [defaults setBool:enabled forKey:AKBatterySaverEnabledDefaultsKey];
}

NSInteger AKBatterySaverStoredAFKMinutes(void) {
    return AKBatterySaverAFKMinutesFromStored(
        [NSUserDefaults.standardUserDefaults objectForKey:AKBatterySaverAFKMinutesDefaultsKey]);
}

void AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit limit) {
    // Normalised on the way in, so the stored spelling is always one of the four.
    if (limit < AKBatterySaverFrameLimitOff || limit > AKBatterySaverFrameLimit60)
        limit = AKBatterySaverFrameLimitOff;
    [NSUserDefaults.standardUserDefaults setObject:AKBatterySaverFrameLimitStoredName(limit)
                                           forKey:AKBatterySaverFrameLimitDefaultsKey];
}

void AKBatterySaverSetAFKMinutes(NSInteger minutes) {
    if (minutes != 2 && minutes != 5 && minutes != 10) minutes = 0;
    [NSUserDefaults.standardUserDefaults setInteger:minutes forKey:AKBatterySaverAFKMinutesDefaultsKey];
}

void AKBatterySaverCommitLaunchSnapshot(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:AKBatterySaverStoredEnabled() forKey:AKBatterySaverLaunchEnabledDefaultsKey];
    [defaults setObject:AKBatterySaverFrameLimitStoredName(AKBatterySaverStoredFrameLimit())
                 forKey:AKBatterySaverLaunchFrameLimitDefaultsKey];
    [defaults setInteger:AKBatterySaverStoredAFKMinutes() forKey:AKBatterySaverLaunchAFKMinutesDefaultsKey];
}

BOOL AKBatterySaverLaunchEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:AKBatterySaverLaunchEnabledDefaultsKey];
}

AKBatterySaverFrameLimit AKBatterySaverLaunchFrameLimit(void) {
    return AKBatterySaverFrameLimitFromStored(
        [NSUserDefaults.standardUserDefaults objectForKey:AKBatterySaverLaunchFrameLimitDefaultsKey]);
}

NSInteger AKBatterySaverLaunchAFKMinutes(void) {
    return AKBatterySaverAFKMinutesFromStored(
        [NSUserDefaults.standardUserDefaults objectForKey:AKBatterySaverLaunchAFKMinutesDefaultsKey]);
}

#pragma mark - Resolution

AKBatterySaverFramePolicy AKBatterySaverFramePolicyMake(BOOL enabled,
                                                       AKBatterySaverFrameLimit limit,
                                                       BOOL externalPower,
                                                       BOOL lowPowerMode,
                                                       NSProcessInfoThermalState thermal,
                                                       BOOL dimmed) {
    AKBatterySaverFramePolicy off = { NO, 0.0 };
    // The master switch is first, and it outranks the dim as well. Off means full performance:
    // the game's own presentation call, untouched, and nothing that settles the panel when the
    // player walks away. That is the whole meaning of the setting, so no other argument can
    // reintroduce a cap.
    if (!enabled) return off;
    // The AFK dim outranks everything the two choices say. The two controls are separate:
    // a person can leave the frame limit alone and still ask for the screen to settle when
    // nobody is playing, and a dimmed session is then held at a fixed low rate whatever the
    // selection says. Waking restores the selection.
    if (dimmed) {
        AKBatterySaverFramePolicy dim = { YES, AKBatterySaverDimFramesPerSecond };
        return dim;
    }
    // Nothing asked for, nothing to do: Off is transparent whether or not the device is hot,
    // on battery, or in Low Power Mode.
    if (limit == AKBatterySaverFrameLimitOff) return off;
    double fps = 30.0;
    switch (limit) {
        case AKBatterySaverFrameLimitAutomatic: fps = externalPower ? 60.0 : 30.0; break;
        case AKBatterySaverFrameLimit60: fps = 60.0; break;
        case AKBatterySaverFrameLimit30: fps = 30.0; break;
        case AKBatterySaverFrameLimitOff: return off;
    }
    // Low Power Mode is the user telling the whole device to spend less. A Serious or
    // Critical thermal state is the device saying the same thing with more authority.
    // Neither raises a rate: 30 stays 30.
    BOOL constrained = lowPowerMode || thermal == NSProcessInfoThermalStateSerious ||
                       thermal == NSProcessInfoThermalStateCritical;
    if (constrained && fps > 30.0) fps = 30.0;
    AKBatterySaverFramePolicy policy = { YES, fps };
    return policy;
}

BOOL AKBatterySaverDeviceHasExternalPower(void) {
#ifdef AK_BATTERY_SAVER_HAS_UIKIT
    // `batteryState` reads Unknown until monitoring is on, and Unknown would quietly mean "on
    // battery" for Automatic - the safe direction for a cap, but the wrong answer for a player
    // on a charger. Enabling monitoring is a subscription to the system's own state changes, not
    // a change to the device: no brightness, no idle timer, no session, nothing persisted.
    static dispatch_once_t once;
    dispatch_once(&once, ^{ UIDevice.currentDevice.batteryMonitoringEnabled = YES; });
    UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
#else
    // No battery to read: the Mac fixture and any other host are always on power.
    return YES;
#endif
}

AKBatterySaverFramePolicy AKBatterySaverResolvedPolicy(BOOL dimmed) {
    return AKBatterySaverFramePolicyMake(AKBatterySaverLaunchEnabled(),
                                         AKBatterySaverLaunchFrameLimit(),
                                         AKBatterySaverDeviceHasExternalPower(),
                                         NSProcessInfo.processInfo.isLowPowerModeEnabled,
                                         NSProcessInfo.processInfo.thermalState,
                                         dimmed);
}

double AKBatterySaverFramePolicyInterval(AKBatterySaverFramePolicy policy) {
    if (!policy.capped || !(policy.framesPerSecond > 0.0)) return 0.0;
    return 1.0 / policy.framesPerSecond;
}
