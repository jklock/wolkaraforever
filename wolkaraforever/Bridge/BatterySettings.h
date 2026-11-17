// The battery settings the launcher writes and the adapters read. Without them the game ran as fast as the
// 120 Hz panel let it, and an iPad put down mid-game stayed lit and drew at full rate until it was flat.
//
// One header, three binaries: the launcher (its rows), the Metal adapter (the frame limit) and the
// AppKit adapter (the AFK saver). It is header-only on purpose - static inline functions and
// literal keys, no class and no exported symbol - so the copies compiled into each image can never
// collide in the one process that loads all three, and "Automatic" cannot mean two things.
//
// Frame limit: Automatic, 30 or 60 frames a second. Automatic follows the charger while the game runs: 30 on
// battery, 60 plugged in (UIDevice's battery state charging or full), 60 when iOS cannot say (unknown). The ones
// offered divide the 120 Hz panel evenly, so each frame is shown for a whole number of refreshes and nothing
// judders. 40 and 120 are not offered, and a stored 40 or 120 (a hand edit, or a build that offered them) reads as
// what the iPad really showed. Measured on an iPad Pro 11-inch (M5), 17 Nov 2026: "40" gave 30.0 fps, because while
// the game plays the presents land on a 60 Hz grid, where a 24 ms frame waits for the second refresh (33.3 ms);
// "120" gave 60.0 fps, with no frame on a 120 Hz-only refresh, for 43 % more CPU than 60. So 40 reads as 30 and
// 120 as 60.
// Low Power Mode, or the iPad's thermal state at Serious or above, lowers any of them to 30 for as
// long as it lasts; the AFK saver lowers it to 10 while the screen is dimmed. The lowest wins.
//
// AFK saver: after this many minutes with no touch, key or controller input during a game, the
// screen is dimmed and frames drop to 10 a second; the next touch wakes it. Off, 2, 5 or 10; 5 by
// default. The session itself is kept: the screen never locks during a game, as before.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The stored choice: an integer. Absent or 0 is Automatic.
static NSString *const AKFrameLimitDefaultsKey = @"WolkaraForeverFrameLimitV1";
// The stored minutes: an integer. Absent is the default (5); 0 is Off.
static NSString *const AKAFKSaverDefaultsKey = @"WolkaraForeverAFKSaverMinutesV1";

static const NSInteger AKFrameLimitAutomatic = 0;
// Automatic's rates: on battery, and plugged in or unknown.
static const NSInteger AKFrameLimitAutomaticBatteryRate = 30;
static const NSInteger AKFrameLimitAutomaticRate = 60;
static const NSInteger AKFrameLimitPowerRate = 30;     // Low Power Mode or thermal Serious+
static const NSInteger AKFrameLimitIdleRate = 10;      // the AFK saver's dimmed screen
static const NSInteger AKFrameLimitPanelRate = 120;    // the panel's own maximum; never a choice, only the pacer's state before its first decision
static const NSInteger AKAFKSaverDefaultMinutes = 5;

// The rows' choices, in the order the sheets list them.
static inline NSArray<NSNumber *> *AKFrameLimitChoices(void) { return @[@0, @30, @60]; }
// A stored 40 (not offered: the iPad shows it at 30) reads as 30.
static const NSInteger AKFrameLimitRetired40 = 40;
// A stored 120 (not offered: the iPad shows it at 60) reads as 60.
static const NSInteger AKFrameLimitRetired120 = 120;
static inline NSArray<NSNumber *> *AKAFKSaverChoices(void) { return @[@0, @2, @5, @10]; }

// The stored frame-limit choice; anything not offered (a hand edit, a later build's value) reads as
// Automatic, so a bad value can never mean "uncapped". A stored 40 reads as 30, a stored 120 as 60.
static inline NSInteger AKFrameLimitChoice(NSUserDefaults *defaults) {
    id value = [defaults objectForKey:AKFrameLimitDefaultsKey];
    if (![value isKindOfClass:NSNumber.class]) return AKFrameLimitAutomatic;
    NSInteger choice = [value integerValue];
    if (choice == AKFrameLimitRetired40) return 30;
    if (choice == AKFrameLimitRetired120) return 60;
    return [AKFrameLimitChoices() containsObject:@(choice)] ? choice : AKFrameLimitAutomatic;
}
// Where the iPad's power comes from, for Automatic. UIDevice's battery state is read by the adapter that
// paces frames; this header stays free of UIKit, so the states are its raw values.
typedef NS_ENUM(NSInteger, AKPowerSource) {
    AKPowerSourceUnknown,   // UIDeviceBatteryStateUnknown (or monitoring not on yet): Automatic is 60
    AKPowerSourceBattery,   // UIDeviceBatteryStateUnplugged
    AKPowerSourcePlugged,   // UIDeviceBatteryStateCharging or UIDeviceBatteryStateFull
};
static inline AKPowerSource AKPowerSourceForBatteryState(NSInteger batteryState) {
    switch (batteryState) {
        case 1: return AKPowerSourceBattery;               // UIDeviceBatteryStateUnplugged
        case 2: case 3: return AKPowerSourcePlugged;       // UIDeviceBatteryStateCharging, UIDeviceBatteryStateFull
        default: return AKPowerSourceUnknown;
    }
}
// The frames a second a choice means where the power comes from `power` (only Automatic asks). A 120 that a
// caller still passes is a 60th: never the panel's rate, so nothing can leave the game unlimited.
static inline NSInteger AKFrameLimitRateForChoice(NSInteger choice, AKPowerSource power) {
    if (choice == AKFrameLimitRetired120) return 60;
    if (choice != AKFrameLimitAutomatic) return choice;
    return power == AKPowerSourceBattery ? AKFrameLimitAutomaticBatteryRate : AKFrameLimitAutomaticRate;
}
// The stored AFK minutes; absent or not offered is the default, 0 is Off.
static inline NSInteger AKAFKSaverMinutes(NSUserDefaults *defaults) {
    id value = [defaults objectForKey:AKAFKSaverDefaultsKey];
    if (![value isKindOfClass:NSNumber.class]) return AKAFKSaverDefaultMinutes;
    NSInteger minutes = [value integerValue];
    return [AKAFKSaverChoices() containsObject:@(minutes)] ? minutes : AKAFKSaverDefaultMinutes;
}

// Why the limit in force is what it is: the log line's words.
typedef NS_ENUM(NSInteger, AKFrameLimitReason) {
    AKFrameLimitReasonSetting,      // the launcher's row (Automatic or a number)
    AKFrameLimitReasonLowPower,     // Low Power Mode is on
    AKFrameLimitReasonThermal,      // thermal state Serious or Critical
    AKFrameLimitReasonIdle,         // the AFK saver has dimmed the screen
};
typedef struct {
    NSInteger rate;                 // frames a second
    AKFrameLimitReason reason;
} AKFrameLimitDecision;

// The limit in force, from the row's choice and the iPad's state. A pure function: the frame pacer
// and its test both call it. `thermalState` is NSProcessInfoThermalState's value. Low Power Mode, heat and the AFK
// saver only ever lower the rate, so on battery under Automatic (30 already) they change nothing.
static inline AKFrameLimitDecision AKFrameLimitDecide(NSInteger choice, AKPowerSource power, BOOL lowPower, NSInteger thermalState, BOOL idle) {
    AKFrameLimitDecision decision = { AKFrameLimitRateForChoice(choice, power), AKFrameLimitReasonSetting };
    BOOL hot = thermalState >= (NSInteger)NSProcessInfoThermalStateSerious;
    if ((lowPower || hot) && AKFrameLimitPowerRate < decision.rate)
        decision = (AKFrameLimitDecision){ AKFrameLimitPowerRate, lowPower ? AKFrameLimitReasonLowPower : AKFrameLimitReasonThermal };
    if (idle && AKFrameLimitIdleRate < decision.rate)
        decision = (AKFrameLimitDecision){ AKFrameLimitIdleRate, AKFrameLimitReasonIdle };
    return decision;
}
// Automatic's words for the log: "Automatic, on battery" and the like.
static inline NSString *AKPowerSourceText(AKPowerSource power) {
    switch (power) {
        case AKPowerSourceBattery: return @"on battery";
        case AKPowerSourcePlugged: return @"plugged in";
        case AKPowerSourceUnknown: break;
    }
    return @"power source unknown";
}
static inline NSString *AKFrameLimitReasonText(AKFrameLimitReason reason) {
    switch (reason) {
        case AKFrameLimitReasonLowPower: return @"Low Power Mode";
        case AKFrameLimitReasonThermal: return @"thermal state serious or above";
        case AKFrameLimitReasonIdle: return @"AFK saver";
        case AKFrameLimitReasonSetting: break;
    }
    return @"setting";
}

NS_ASSUME_NONNULL_END
