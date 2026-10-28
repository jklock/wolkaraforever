// Ask Core Animation for the 60 Hz the game is trying to hit, and record what it
// actually gives this display link.
//
// Why this exists. The renderer needs to request the 30/60 Hz priority Apple gives
// games, and the adapter needs to record the scheduling interval it receives. A
// display-link interval alone is not proof of the guest's present cadence; that is
// measured separately from CAMetalDrawable.presentedTime.
//
// Apple's rule for this case: "the system provides games with special priority to 30Hz
// and 60Hz refresh rates to ensure optimal performance. To access this special
// prioritization, your game needs to set a preferredFrameRateRange with a
// CAFrameRateRange structure using one or both of those values." (Optimizing iPhone
// and iPad apps to support ProMotion displays.) It also says the rate is not ours to
// force - "you can't force a ProMotion display to show your content at any specific
// rate" - so this is a request, and the log below is how we learn whether it was
// granted.
//
// Nothing in either tree claimed a frame rate before this: the only CADisplayLink was
// the performance HUD's, at 4-30 Hz preferred 10, which is a diagnostic overlay and not
// a claim on the panel.
//
// The measurement matters as much as the request. Once per second this logs the
// interval Core Animation schedules for this link and the interval of its callbacks.
// Compare it with the independent Metal present distribution; do not present either
// value as proof of the other.
//
// This is capture-only, not a production pacing mechanism.  The guest does not
// render from this callback, so a passive link cannot improve its frame time and
// must not add main-thread wakeups during ordinary play.  Opt in explicitly with
// --measure-display-rate when correlating this link with Metal presentation data.

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "AKSupport.h"

// The rate a game should ask for: both values Apple gives priority to, preferring 60.
#define AKDisplayRateMinimum 30.0
#define AKDisplayRateMaximum 60.0
#define AKDisplayRatePreferred 60.0

static CADisplayLink *s_link;
static double s_lastTimestamp;
static double s_intervalTotal;
static double s_intervalMin;
static double s_intervalMax;
static unsigned s_ticks;
static double s_nextReport;
static double s_deadlineTotal;      // targetTimestamp - timestamp, the asked-for interval

static void Report(void) {
    if (!s_ticks) {
        AKLog(@"display rate: no display link callbacks in the last second (the run loop is not being served)");
        return;
    }
    double mean = s_intervalTotal / s_ticks;
    double target = s_ticks ? s_deadlineTotal / s_ticks : 0.0;
    // Apple defines targetTimestamp - timestamp as the display link's actual frame
    // duration.  It is still a property of this link, not a CAMetalDrawable present.
    AKLog(@"display link rate: target %.2fms (%.1f Hz), callback mean %.2fms min %.2f max %.2f, callbacks=%u thermal=%d lowpower=%d",
          target * 1000.0, target > 0 ? 1.0 / target : 0.0,
          mean * 1000.0, s_intervalMin * 1000.0, s_intervalMax * 1000.0, s_ticks,
          (int)NSProcessInfo.processInfo.thermalState,
          (int)NSProcessInfo.processInfo.isLowPowerModeEnabled);
    s_intervalTotal = s_intervalMin = s_intervalMax = s_deadlineTotal = 0.0;
    s_ticks = 0;
}

static void Tick(CADisplayLink *link) {
    double now = link.timestamp;
    if (s_lastTimestamp > 0 && now > s_lastTimestamp) {
        double interval = now - s_lastTimestamp;
        s_intervalTotal += interval;
        if (s_intervalMin == 0 || interval < s_intervalMin) s_intervalMin = interval;
        if (interval > s_intervalMax) s_intervalMax = interval;
        s_deadlineTotal += link.targetTimestamp - link.timestamp;
    }
    s_lastTimestamp = now;
    s_ticks++;
    if (now >= s_nextReport) {
        Report();
        s_nextReport = now + 1.0;
    }
}

@interface AKDisplayRateTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end

@implementation AKDisplayRateTarget
- (void)tick:(CADisplayLink *)link { Tick(link); }
@end

static AKDisplayRateTarget *s_target;

static void AKDisplayRateInstall(void) {
    if (s_link || !NSThread.isMainThread) return;
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--measure-display-rate"]) return;
    s_target = [AKDisplayRateTarget new];
    s_link = [CADisplayLink displayLinkWithTarget:s_target selector:@selector(tick:)];
    if (!s_link) {
        AKLog(@"display rate: could not create a display link; the panel rate is unclaimed");
        return;
    }
    if (@available(iOS 15.0, *)) {
        s_link.preferredFrameRateRange = CAFrameRateRangeMake(AKDisplayRateMinimum,
                                                              AKDisplayRateMaximum,
                                                              AKDisplayRatePreferred);
    } else {
        s_link.preferredFramesPerSecond = (NSInteger)AKDisplayRatePreferred;
    }
    [s_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    AKLog(@"display rate: asked for %.0f-%.0f Hz, preferring %.0f (screen maximum %ld)",
          AKDisplayRateMinimum, AKDisplayRateMaximum, AKDisplayRatePreferred,
          (long)UIScreen.mainScreen.maximumFramesPerSecond);
}

// The adapter is loaded before the guest draws. A display link must be created on
// the main thread, so the diagnostic constructor installs only when the explicit
// capture argument is present.
__attribute__((constructor)) static void AKDisplayRateLoad(void) {
    if (NSThread.isMainThread) AKDisplayRateInstall();
    else dispatch_async(dispatch_get_main_queue(), ^ { AKDisplayRateInstall(); });
}
