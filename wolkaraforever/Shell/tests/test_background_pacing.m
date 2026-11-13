#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

// Inactive Metal submission, measured on the hook the guest's renderer goes
// through.
//
// The product's answer to "the guest keeps rendering while another app is in
// front" is a cap inside -[CAMetalLayer nextDrawable]: while the app is inactive
// a frame is allowed every 200 ms, the wait is taken in 5 ms slices so a
// foregrounding cannot be inherited as a hitch, and the first drawable after the
// app is active again is reported. This fixture drives that same method, on a
// real CAMetalLayer, with the same notifications the app receives, and measures
// what the cap does rather than what it is written to do.
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

        // The adapter installs the hook from its own constructor; installing it
        // again must not wrap the method a second time, which would cap frames
        // twice and slow the guest down while it is visible.
        AKInstallMetalBackgroundPacing();
        AKInstallMetalBackgroundPacing();

        Rate active = Measure(layer, 1.0);
        printf("active: %.1f acquisitions/s, slowest call %.1f ms, nil=%u\n", active.perSecond, active.worstMilliseconds, active.nils);
        Require(active.perSecond > 20, @"the app is active, so acquisition must not be paced");
        Require(active.worstMilliseconds < 100, @"an active acquisition waited like an inactive one");

        Post(UIApplicationWillResignActiveNotification);
        Rate inactive = Measure(layer, 2.0);
        printf("inactive: %.1f acquisitions/s, slowest call %.1f ms, nil=%u\n", inactive.perSecond, inactive.worstMilliseconds, inactive.nils);
        // 200 ms per frame is 5/s; allow the bounds a scheduling slice can move
        // it by, and refuse both "not capped at all" and "no frame at all".
        Require(inactive.perSecond <= 12, @"an inactive acquisition was not paced");
        Require(inactive.calls >= 4, @"an inactive session acquired almost nothing");
        Require(inactive.worstMilliseconds < 300, @"an inactive acquisition waited longer than its own interval");

        // The wait is taken in slices so this is not a 200 ms sleep the return to
        // the foreground has to sit through.
        double before = Now();
        Post(UIApplicationDidBecomeActiveNotification);
        @autoreleasepool { (void)[layer nextDrawable]; }
        double firstFrame = (Now() - before) * 1000.0;
        printf("foreground: first acquisition after %.1f ms\n", firstFrame);
        Require(firstFrame < 60, @"the first frame after the app became active inherited the background wait");

        Rate resumed = Measure(layer, 1.0);
        printf("resumed: %.1f acquisitions/s, slowest call %.1f ms, nil=%u\n", resumed.perSecond, resumed.worstMilliseconds, resumed.nils);
        Require(resumed.perSecond > 20, @"acquisition did not return to the display's own rate");

        printf("PASS: %u acquisitions at full rate, %u paced at %.1f/s with a slowest call of %.1f ms, "
               "the first frame after foregrounding took %.1f ms, and %u nil drawables were counted rather than assumed\n",
               active.calls, inactive.calls, inactive.perSecond, inactive.worstMilliseconds, firstFrame,
               active.nils + inactive.nils + resumed.nils);
    }
    return 0;
}
