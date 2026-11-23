// The Battery Saver rules, on their own. Foundation only: no game, no Metal, no simulator.
//
// What is checked here is the whole contract the launcher, the Metal adapter and the AppKit
// adapter share - what a stored value means, what the four selections resolve to on a
// charger or in Low Power Mode, that the dim outranks them, and that a running session
// keeps the choice it was started with when the submenu changes underneath it.
#import <Foundation/Foundation.h>
// Through the prepared tree's layout, like every other test of layer code: this suite is built
// there too, so the header it tests is the one the app compiles against.
#import "../launcher/WoW/BatterySaverPolicy.h"
#include <assert.h>

static void ClearStored(void) {
    for (NSString *key in @[AKBatterySaverEnabledDefaultsKey,
                             AKBatterySaverFrameLimitDefaultsKey, AKBatterySaverAFKMinutesDefaultsKey,
                             AKBatterySaverLaunchEnabledDefaultsKey,
                             AKBatterySaverLaunchFrameLimitDefaultsKey, AKBatterySaverLaunchAFKMinutesDefaultsKey])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

int main(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        ClearStored();

        // --- The master switch is the first decision. Absent means off, and off is full
        // performance, which is what an installation that never opened the submenu gets.
        assert(!AKBatterySaverStoredEnabled());
        assert(!AKBatterySaverLaunchEnabled());

        // --- Nothing chosen, nothing capped. This is what every existing installation does,
        // and it is the state the default has to reproduce exactly: no delay, no changed call.
        assert(AKBatterySaverStoredFrameLimit() == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverStoredAFKMinutes() == 0);
        AKBatterySaverFramePolicy off = AKBatterySaverResolvedPolicy(NO);
        assert(!off.capped);
        assert(AKBatterySaverFramePolicyInterval(off) == 0.0);
        // Off is Off even in Low Power Mode.
        assert(!AKBatterySaverFramePolicyMake(YES, AKBatterySaverFrameLimitOff, NO, YES, NO).capped);
        // The master switch outranks every other input: no cap, and no dim either. A session
        // that opted into nothing must not settle when the player walks away.
        assert(!AKBatterySaverFramePolicyMake(NO, AKBatterySaverFrameLimit60, YES, NO, NO).capped);
        assert(!AKBatterySaverFramePolicyMake(NO, AKBatterySaverFrameLimitAutomatic, NO, NO, YES).capped);
        assert(AKBatterySaverFramePolicyInterval(AKBatterySaverFramePolicyMake(
            NO, AKBatterySaverFrameLimit30, YES, NO, NO)) == 0.0);

        // --- Every stored spelling this build offers, and every one it does not.
        assert(AKBatterySaverFrameLimitFromStored(@"off") == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverFrameLimitFromStored(@"auto") == AKBatterySaverFrameLimitAutomatic);
        assert(AKBatterySaverFrameLimitFromStored(@"AUTO") == AKBatterySaverFrameLimitAutomatic);
        assert(AKBatterySaverFrameLimitFromStored(@"30") == AKBatterySaverFrameLimit30);
        assert(AKBatterySaverFrameLimitFromStored(@"60") == AKBatterySaverFrameLimit60);
        // Legacy, hand-edited and nonsensical values resolve safely to Off rather than to a
        // neighbouring rate.
        assert(AKBatterySaverFrameLimitFromStored(@"120") == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverFrameLimitFromStored(@"on") == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverFrameLimitFromStored(@"") == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverFrameLimitFromStored(nil) == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverFrameLimitFromStored(@(30)) == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverFrameLimitFromStored(@[@30]) == AKBatterySaverFrameLimitOff);
        assert([AKBatterySaverFrameLimitStoredName(AKBatterySaverFrameLimitAutomatic) isEqual:@"auto"]);
        assert([AKBatterySaverFrameLimitStoredName(AKBatterySaverFrameLimit30) isEqual:@"30"]);
        assert([AKBatterySaverFrameLimitStoredName(AKBatterySaverFrameLimit60) isEqual:@"60"]);
        assert([AKBatterySaverFrameLimitStoredName(AKBatterySaverFrameLimitOff) isEqual:@"off"]);

        // Minutes: only the three timeouts the submenu offers, plus off.
        assert(AKBatterySaverAFKMinutesFromStored(@2) == 2);
        assert(AKBatterySaverAFKMinutesFromStored(@5) == 5);
        assert(AKBatterySaverAFKMinutesFromStored(@10) == 10);
        assert(AKBatterySaverAFKMinutesFromStored(@0) == 0);
        assert(AKBatterySaverAFKMinutesFromStored(@3) == 0);
        assert(AKBatterySaverAFKMinutesFromStored(@(-5)) == 0);
        assert(AKBatterySaverAFKMinutesFromStored(nil) == 0);
        assert(AKBatterySaverAFKMinutesFromStored(@"5") == 0);
        // A boolean is an NSNumber too: `true` must not mean a one-minute AFK timer.
        assert(AKBatterySaverAFKMinutesFromStored(@YES) == 0);

        // --- Writing normalises, so what a reader finds is always one of the four/four.
        AKBatterySaverSetAFKMinutes(3);
        assert(AKBatterySaverStoredAFKMinutes() == 0);
        AKBatterySaverSetAFKMinutes(5);
        assert(AKBatterySaverStoredAFKMinutes() == 5);
        AKBatterySaverSetFrameLimit((AKBatterySaverFrameLimit)99);
        assert(AKBatterySaverStoredFrameLimit() == AKBatterySaverFrameLimitOff);
        AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit60);
        assert(AKBatterySaverStoredFrameLimit() == AKBatterySaverFrameLimit60);

        // --- Automatic means the charger decides: 60 FPS on power, 30 on battery.
        AKBatterySaverSetEnabled(YES);
        assert(AKBatterySaverStoredEnabled());
        AKBatterySaverFramePolicy plugged = AKBatterySaverFramePolicyMake(
            YES, AKBatterySaverFrameLimitAutomatic, YES, NO, NO);
        assert(plugged.capped && plugged.framesPerSecond == 60.0);
        AKBatterySaverFramePolicy unplugged = AKBatterySaverFramePolicyMake(
            YES, AKBatterySaverFrameLimitAutomatic, NO, NO, NO);
        assert(unplugged.capped && unplugged.framesPerSecond == 30.0);

        // --- Low Power Mode lowers a rate above 30 to 30 and never raises one. Device
        // temperature is not an input at all: the policy cannot see it, which is the point -
        // a hot iPad does not quietly change the pacing the player chose.
        assert(AKBatterySaverFramePolicyMake(YES, AKBatterySaverFrameLimitAutomatic, YES, YES, NO).framesPerSecond == 30.0);
        assert(AKBatterySaverFramePolicyMake(YES, AKBatterySaverFrameLimit60, YES, YES, NO).framesPerSecond == 30.0);
        assert(AKBatterySaverFramePolicyMake(YES, AKBatterySaverFrameLimit60, YES, NO, NO).framesPerSecond == 60.0);
        assert(AKBatterySaverFramePolicyMake(YES, AKBatterySaverFrameLimit30, YES, YES, NO).framesPerSecond == 30.0);

        // --- The AFK dim outranks the selection: a fixed 10 FPS, whatever was chosen, and it
        // applies even with the frame limit Off - the two controls are separate decisions.
        AKBatterySaverFramePolicy dimmed = AKBatterySaverFramePolicyMake(
            YES, AKBatterySaverFrameLimit60, YES, NO, YES);
        assert(dimmed.capped && dimmed.framesPerSecond == AKBatterySaverDimFramesPerSecond);
        assert(AKBatterySaverFramePolicyMake(YES, AKBatterySaverFrameLimit30, NO, YES, YES).framesPerSecond == 10.0);
        AKBatterySaverFramePolicy dimmedOff = AKBatterySaverFramePolicyMake(
            YES, AKBatterySaverFrameLimitOff, YES, NO, YES);
        assert(dimmedOff.capped && dimmedOff.framesPerSecond == AKBatterySaverDimFramesPerSecond);

        // --- The interval a presentation is held for: 1/60, 1/30, 1/10; nothing when Off.
        assert(fabs(AKBatterySaverFramePolicyInterval(plugged) - 1.0 / 60.0) < 1e-9);
        assert(fabs(AKBatterySaverFramePolicyInterval(unplugged) - 1.0 / 30.0) < 1e-9);
        assert(fabs(AKBatterySaverFramePolicyInterval(dimmed) - 1.0 / 10.0) < 1e-9);
        assert(AKBatterySaverFramePolicyInterval(off) == 0.0);

        // --- Next-launch snapshot: the guest reads what was committed, not what the submenu
        // says now, and a session started before a change keeps its own choice.
        assert(AKBatterySaverLaunchFrameLimit() == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverLaunchAFKMinutes() == 0);
        assert(!AKBatterySaverLaunchEnabled());
        AKBatterySaverSetEnabled(YES);
        AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimitAutomatic);
        AKBatterySaverSetAFKMinutes(10);
        AKBatterySaverCommitLaunchSnapshot();
        assert(AKBatterySaverLaunchEnabled());
        assert(AKBatterySaverLaunchFrameLimit() == AKBatterySaverFrameLimitAutomatic);
        assert(AKBatterySaverLaunchAFKMinutes() == 10);
        // The user changes the submenu while the game runs.
        AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimitOff);
        AKBatterySaverSetAFKMinutes(0);
        assert(AKBatterySaverLaunchFrameLimit() == AKBatterySaverFrameLimitAutomatic);
        assert(AKBatterySaverLaunchAFKMinutes() == 10);
        // The next launch picks the new choice up, including turning the mode off.
        AKBatterySaverSetEnabled(NO);
        AKBatterySaverCommitLaunchSnapshot();
        assert(!AKBatterySaverLaunchEnabled());
        assert(AKBatterySaverLaunchFrameLimit() == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverLaunchAFKMinutes() == 0);

        // --- A snapshot a hand edit has broken is Off, exactly like a missing one.
        [defaults setObject:@"sometimes" forKey:AKBatterySaverLaunchFrameLimitDefaultsKey];
        [defaults setObject:@6 forKey:AKBatterySaverLaunchAFKMinutesDefaultsKey];
        assert(AKBatterySaverLaunchFrameLimit() == AKBatterySaverFrameLimitOff);
        assert(AKBatterySaverLaunchAFKMinutes() == 0);

        ClearStored();
        printf("test_battery_saver_policy: PASS\n");
    }
    return 0;
}
