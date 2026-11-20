// The AFK coordinator's rules, with a clock the fixture owns. No app, no scene, no game:
// the coordinator only needs a surface to put its layer over.
//
// This is the only way the timeout can be tested rather than described - a ten-minute wait
// per case is not a test. Everything else is real: a real UIView host, the real UIKit
// notifications for backgrounding, and the real policy for what the cap is before and after
// the dim.
//
// Run in the simulator: wolkaraforever/tools/test_battery_saver_idle.sh
#import "BatterySaverIdle.h"
#include <assert.h>

static BOOL sConfiguration;
static NSInteger sDimNotifications;
static BOOL sLastDimNotification;

static void NoteDim(NSNotification *note) {
    sDimNotifications++;
    sLastDimNotification = [note.userInfo[AKBatterySaverDimmedKey] boolValue];
}

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[AKBatterySaverFrameLimitDefaultsKey, AKBatterySaverAFKMinutesDefaultsKey,
                             AKBatterySaverLaunchFrameLimitDefaultsKey, AKBatterySaverLaunchAFKMinutesDefaultsKey])
        [defaults removeObjectForKey:key];
    [NSNotificationCenter.defaultCenter addObserverForName:AKBatterySaverDimDidChangeNotification
                                                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        NoteDim(note);
    }];

    // The host the layer is installed over: the same shape the adapter gives it.
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];

    // --- Off is the default, and Off never dims however long nothing happens.
    __block double now = 1000.0;
    AKBatterySaverIdle *idle = [[AKBatterySaverIdle alloc] initWithHostView:host];
    idle.clock = ^{ return now; };
    assert(idle.timeoutMinutes == 0);
    now += 60.0 * 60.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);

    // --- A two-minute timeout dims at two minutes and not a second before.
    idle.timeoutMinutes = 2;
    idle.configurationActive = ^BOOL { return sConfiguration; };
    now += 1.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    now += 119.0 - 1.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    // Nothing is looked at, but the game is still being played: the layer appears exactly
    // when the timeout is reached.
    now += 1.0;
    [idle tickAt:now];
    assert(idle.isDimmed);

    // --- While dimmed the session is at the dim's fixed rate, not at the selection.
    AKBatterySaverFramePolicy dimmedPolicy = idle.framePolicy;
    assert(dimmedPolicy.capped && dimmedPolicy.framesPerSecond == AKBatterySaverDimFramesPerSecond);

    // --- The first input after the dim only wakes: it is consumed, and the next one is
    // delivered. Every source the host reports behaves the same way.
    for (NSString *source in @[@"touch", @"key", @"mouse", @"controller", @"controllerTouchpad"]) {
        idle.timeoutMinutes = 0;             // start from a clean, woken session
        idle.timeoutMinutes = 2;
        now = idle.clock();
        // Dim it again, then consume one input from this source.
        now += 120.0;
        [idle tickAt:now];
        assert(idle.isDimmed);
        assert([idle input:source]);          // woke: the game must not see it
        assert(!idle.isDimmed);
        assert(![idle input:source]);         // the next one is the game's
    }

    // --- A wake restores the selection, not the dim's rate. 30 FPS here because the
    // snapshot says 30.
    AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
    AKBatterySaverCommitLaunchSnapshot();
    assert(idle.framePolicy.capped && idle.framePolicy.framesPerSecond == 30.0);
    now += 120.0;
    [idle tickAt:now];
    assert(idle.isDimmed && idle.framePolicy.framesPerSecond == 10.0);
    assert([idle input:@"touch"]);
    assert(idle.framePolicy.framesPerSecond == 30.0);

    // --- Held input never dims, and the countdown starts again when it is released. This
    // is the case a screenshot cannot show: a controller trigger held while the player
    // watches the screen, and an on-screen stick pushed with a thumb.
    idle.timeoutMinutes = 2;
    [idle setHeld:YES reason:@"touch"];
    now += 600.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    [idle setHeld:NO reason:@"touch"];
    now += 119.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    now += 1.0;
    [idle tickAt:now];
    assert(idle.isDimmed);
    assert([idle input:@"touch"]);

    // --- Two reasons at once: releasing one is not releasing all.
    [idle setHeld:YES reason:@"touch"];
    [idle setHeld:YES reason:@"controllerTouchpad"];
    [idle setHeld:NO reason:@"touch"];
    now += 600.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    [idle setHeld:NO reason:@"controllerTouchpad"];
    now += 120.0;
    [idle tickAt:now];
    assert(idle.isDimmed);
    assert([idle input:@"controllerTouchpad"]);

    // --- The touch controls' configuration UI is open: not idle, just being configured.
    sConfiguration = YES;
    now += 600.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    sConfiguration = NO;
    now += 119.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    now += 1.0;
    [idle tickAt:now];
    assert(idle.isDimmed);

    // --- Background: waking a session on the way out, and not counting while away. The two
    // notifications are the ones the adapter's own app lifecycle posts.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    assert(!idle.isDimmed);
    now += 600.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    now += 119.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);
    now += 1.0;
    [idle tickAt:now];
    assert(idle.isDimmed);
    // Backgrounding while dimmed brings the picture back rather than leaving a black
    // screen behind the next app.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    assert(!idle.isDimmed);

    // --- The app is told every time the state changes, with the state, so the controller
    // path and the Metal adapter never have to guess.
    assert(sDimNotifications >= 8);
    assert(!sLastDimNotification);

    // --- Turning the option off while dimmed restores the session immediately.
    idle.timeoutMinutes = 2;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    now += 120.0;
    [idle tickAt:now];
    assert(idle.isDimmed);
    idle.timeoutMinutes = 0;
    assert(!idle.isDimmed);

    // --- A clock that jumps backwards must not dim: "idle" is a duration, not a difference.
    idle.timeoutMinutes = 2;
    now -= 10000.0;
    [idle tickAt:now];
    assert(!idle.isDimmed);

    // The layer is one view over the surface, and it never takes an input of its own.
    NSInteger layers = 0;
    for (UIView *view in host.subviews) if ([view isKindOfClass:AKBatterySaverDimView.class]) layers++;
    assert(layers == 1);
    UIView *dim = nil;
    for (UIView *view in host.subviews) if ([view isKindOfClass:AKBatterySaverDimView.class]) dim = view;
    assert(!dim.userInteractionEnabled);
    assert(![dim pointInside:CGPointMake(10, 10) withEvent:nil]);
    assert(dim.layer.zPosition > 90000 && dim.layer.zPosition < 100000);

    puts("battery saver idle: timeout, held input, every wake source, first-input suppression, configuration UI, background/foreground, touchpad handoff and cap restoration: PASS");
} }
