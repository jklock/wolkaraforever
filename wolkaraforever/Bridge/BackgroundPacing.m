#import <Foundation/Foundation.h>
#import "AKSupport.h"

// Do not couple the guest's runtime loop to UIKit visibility. The old hook slept
// in -nextDrawable while backgrounded; the game drives timers and networking from
// that loop, so the deliberate 5 FPS cap starved its connection after a minute.
// iPadOS remains responsible for lifecycle scheduling; this layer must not add a
// second throttle on the render path.
void AKInstallMetalBackgroundPacing(void) {
    AKLog(@"background pacing: no guest-loop throttle is installed");
}

// The symbol remains for the adapter and the focused lifecycle test. It no longer
// interposes CAMetalLayer or observes lifecycle notifications.
__attribute__((constructor)) static void AKBackgroundPacingLoad(void) {
    AKInstallMetalBackgroundPacing();
}
