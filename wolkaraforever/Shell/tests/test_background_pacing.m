#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

// Inactive Metal submission, measured on the hook the guest's renderer goes
// through.
//
// Backgrounding must not add a throttle to the guest's render loop. The game runs
// timers and networking from that loop, so a draw-path sleep disconnects a live
// session. This fixture drives a real CAMetalLayer through the lifecycle edge and
// proves the adapter leaves it alone.
//
// What it can and cannot see: an off-screen layer may hand out no drawable at
// all, so the fixture counts nils and reports them instead of pretending they are
// frames. The pacing decision happens before the drawable is asked for, so the
// timing measured here is the timing the guest would get.

// No header of its own: the adapter installs it from its constructor, and this is
// the same entry point, so the fixture can prove a second install does nothing.
extern void AKInstallMetalBackgroundPacing(void);

static double Now(void) { return NSProcessInfo.processInfo.systemUptime; }

static void Post(NSNotificationName name) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
}

// Acquisitions per second, the worst single call, and how many came back nil.
typedef struct { double perSecond, worstMilliseconds; unsigned calls, nils; } Rate;

static Rate Measure(CAMetalLayer *layer, double seconds) {
    Rate rate = {0, 0, 0, 0};
    double began = Now(), ended = began + seconds;
    while (Now() < ended) {
        double before = Now();
        @autoreleasepool { id<CAMetalDrawable> drawable = [layer nextDrawable]; if (!drawable) rate.nils++; }
        double took = (Now() - before) * 1000.0;
        if (took > rate.worstMilliseconds) rate.worstMilliseconds = took;
        rate.calls++;
    }
    rate.perSecond = rate.calls / (Now() - began);
    return rate;
}

static void Require(BOOL value, NSString *message) {
    if (value) return;
    fprintf(stdout, "FAIL: %s\n", message.UTF8String);
    fflush(stdout);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        fprintf(stdout, "device=%s\n", device ? device.name.UTF8String : "none");
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = device;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.drawableSize = CGSizeMake(64, 64);
        layer.framebufferOnly = YES;

        // The retained adapter entry point is deliberately inert. Calling it twice
        // must not interpose or otherwise change drawable acquisition.
        AKInstallMetalBackgroundPacing();
        AKInstallMetalBackgroundPacing();

        Rate active = Measure(layer, 1.0);
        printf("active: %.1f acquisitions/s, slowest call %.1f ms, nil=%u\n", active.perSecond, active.worstMilliseconds, active.nils);
        Require(active.perSecond > 20, @"the app is active, so acquisition must not be paced");
        Require(active.worstMilliseconds < 100, @"an active acquisition waited like an inactive one");

        Post(UIApplicationWillResignActiveNotification);
        Rate inactive = Measure(layer, 1.0);
        printf("inactive: %.1f acquisitions/s, slowest call %.1f ms, nil=%u\n", inactive.perSecond, inactive.worstMilliseconds, inactive.nils);
        Require(inactive.perSecond > 20, @"backgrounding installed a guest-loop frame cap");
        Require(inactive.worstMilliseconds < 100, @"backgrounding inserted a drawable wait");

        // Foregrounding has no inherited draw-path wait.
        double before = Now();
        Post(UIApplicationDidBecomeActiveNotification);
        @autoreleasepool { (void)[layer nextDrawable]; }
        double firstFrame = (Now() - before) * 1000.0;
        printf("foreground: first acquisition after %.1f ms\n", firstFrame);
        Require(firstFrame < 60, @"the first frame after the app became active inherited the background wait");

        Rate resumed = Measure(layer, 1.0);
        printf("resumed: %.1f acquisitions/s, slowest call %.1f ms, nil=%u\n", resumed.perSecond, resumed.worstMilliseconds, resumed.nils);
        Require(resumed.perSecond > 20, @"acquisition did not return to the display's own rate");

        printf("PASS: %u active and %u background acquisitions stayed unpaced; the first frame after foregrounding took %.1f ms, and %u nil drawables were counted rather than assumed\n",
               active.calls, inactive.calls, firstFrame,
               active.nils + inactive.nils + resumed.nils);
    }
    return 0;
}
