// The Battery Saver frame cap, at the Metal presentation boundary it is implemented at.
//
// Every presentation path is driven for real - immediate, timed (atTime:) and
// minimum-duration - through a real CAMetalLayer and a real command queue, and the fixture
// measures what the adapter asked the system for, frame by frame:
//
//   - which presentation call it made, from the adapter's own counters;
//   - the minimum duration it asked to hold the previous drawable for, and
//   - the host time it asked each frame to be presented at.
//
// The host times are the measurement that matters here. The simulator presents offscreen and
// does not throttle, so a frame-completion interval says nothing about what a panel shows;
// the target sequence does. With a 30 FPS cap the adapter must ask for frames no closer
// together than 1/30 s whatever the guest asked for, and with the cap off it must ask for
// exactly the guest's own time and install no hook at all. Presented frames per second are
// measured on the device, from CAMetalDrawable.presentedTime; the accounting itself - ten
// presented timestamps 1/30 s apart are 30 presented FPS - is checked here.
//
// One process cannot be two configurations - the swizzles are installed once - so the runner
// starts this binary once per case:
//
//   test_metal_pacing off | immediate30 | immediate30-fallback | attime30 | minimum30 |
//                    minimum-longer
//
// The simulator's Metal implements timed presentation but not minimum-duration presentation,
// which the device SDK declares and the device implements. Where a case needs it and it is
// missing, the fixture adds it to the command buffer's own class as a double that records its
// duration and presents at the equivalent time. `immediate30-fallback` runs without it, which
// is the path a simulator session actually takes.
//
// Run in the simulator: wolkaraforever/tools/test_battery_saver_metal.sh
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "BatterySaverPolicy.h"
#include <assert.h>
#include <string.h>

extern void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device);
extern void AKMetalBatterySaverPacingCounts(uint64_t *immediate, uint64_t *extended,
                                            uint64_t *raised, uint64_t *kept, uint64_t *bypassed);
// The presented-frame accounting the HUD reads.
extern void AKRecordMetalFramePresented(double timestamp);
extern double AKMetalCurrentFPS(void);

typedef NS_ENUM(int, Path) {
    PathImmediate,
    PathAtTime,
    PathMinimum,
};

static SEL sMinimumDurationSelector;
static SEL sAtTimeSelector;
static IMP sMetalAtTime;                         // the real timed presentation, under both doubles
static NSMutableArray<NSNumber *> *sDurations;   // minimum durations the adapter asked for
static NSMutableArray<NSNumber *> *sTargets;     // host times the adapter asked to present at
static NSMutableArray<NSNumber *> *sRequested;   // what the fixture itself asked for
static CFTimeInterval sRequestedTime;
static CFTimeInterval sDoubleLast;

// Timed presentation: recorded, then made for real. The adapter swizzles this selector too, so
// what it ends in is this function, and what this function ends in is Metal.
static void RecordAtTime(id self, SEL _cmd, id<MTLDrawable> drawable, CFTimeInterval time) {
    [sTargets addObject:@(time)];
    [sRequested addObject:@(sRequestedTime)];
    ((void (*)(id, SEL, id<MTLDrawable>, CFTimeInterval))sMetalAtTime)(self, _cmd, drawable, time);
}

// What a minimum-duration presentation does is hold the previous drawable for at least
// `duration`, which is a timed presentation at the previous target plus that duration.
static void DoublePresentAfter(id self, SEL _cmd, id<MTLDrawable> drawable, CFTimeInterval duration) {
    (void)_cmd;
    [sDurations addObject:@(duration)];
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval target = MAX(now, sDoubleLast + duration);
    sDoubleLast = target;
    RecordAtTime(self, sAtTimeSelector, drawable, target);
}

static void InstallDoubles(id<MTLCommandBuffer> sample, BOOL withMinimumDouble) {
    Class cls = object_getClass(sample);
    sAtTimeSelector = @selector(presentDrawable:atTime:);
    sMinimumDurationSelector = NSSelectorFromString(@"presentDrawable:afterMinimumDuration:");
    sTargets = [NSMutableArray new];
    sRequested = [NSMutableArray new];
    Method atTime = class_getInstanceMethod(cls, sAtTimeSelector);
    sMetalAtTime = method_getImplementation(atTime);
    class_replaceMethod(cls, sAtTimeSelector, (IMP)RecordAtTime, method_getTypeEncoding(atTime));
    // The simulator's Metal has no minimum-duration presentation; the device's does. When it is
    // missing and this case needs it, the double stands in so the adapter's decision can still
    // be measured - including the duration it asked for.
    if (withMinimumDouble && ![sample respondsToSelector:sMinimumDurationSelector]) {
        sDurations = [NSMutableArray new];
        class_addMethod(cls, sMinimumDurationSelector, (IMP)DoublePresentAfter, "v@:@d");
        assert([sample respondsToSelector:sMinimumDurationSelector]);
    }
}

static void PresentAfterMinimum(id<MTLCommandBuffer> buffer, id<MTLDrawable> drawable, CFTimeInterval duration) {
    ((void (*)(id, SEL, id<MTLDrawable>, CFTimeInterval))objc_msgSend)(
        buffer, sMinimumDurationSelector, drawable, duration);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        for (NSString *key in @[AKBatterySaverEnabledDefaultsKey,
                                 AKBatterySaverFrameLimitDefaultsKey, AKBatterySaverAFKMinutesDefaultsKey,
                                 AKBatterySaverLaunchEnabledDefaultsKey,
                                 AKBatterySaverLaunchFrameLimitDefaultsKey, AKBatterySaverLaunchAFKMinutesDefaultsKey])
            [defaults removeObjectForKey:key];

        Path path = PathImmediate;
        BOOL capped = YES;
        BOOL withMinimumDouble = NO;
        BOOL longer = NO;
        BOOL lateRequests = NO;
        CFTimeInterval duration = 0.0;
        NSString *mode = [NSString stringWithUTF8String:argv[1]];
        if ([mode isEqual:@"off"]) {
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimitOff);
            capped = NO;
        } else if ([mode isEqual:@"immediate30"]) {
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
            withMinimumDouble = YES;
        } else if ([mode isEqual:@"immediate30-fallback"]) {
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
        } else if ([mode isEqual:@"attime30"]) {
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
            path = PathAtTime;
        } else if ([mode isEqual:@"attime30-late"]) {
            // A guest that has already timed a frame later than the cap, which is the case a
            // real game reaches whenever it runs behind. The frame is kept, and the *next* one
            // must still be a full interval after what was actually presented - not after the
            // target the kept frame skipped.
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
            path = PathAtTime;
            lateRequests = YES;
        } else if ([mode isEqual:@"minimum30"]) {
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
            path = PathMinimum;
            withMinimumDouble = YES;
            duration = 0.001;   // shorter than the cap: the adapter must raise it
        } else if ([mode isEqual:@"minimum-longer"]) {
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
            path = PathMinimum;
            withMinimumDouble = YES;
            duration = 0.2;     // the game asked for longer than the cap: it must be kept
            longer = YES;
        } else if ([mode isEqual:@"disabled"]) {
            // A frame limit is stored, but the master switch is off: nothing may be installed
            // and the game's own presentation call must be the one that runs.
            AKBatterySaverSetFrameLimit(AKBatterySaverFrameLimit30);
            capped = NO;
        } else {
            fprintf(stderr, "unknown mode %s\n", argv[1]);
            return 2;
        }
        // The snapshot is what the guest reads: taken before the adapter installs its hooks,
        // exactly as the launcher takes it before starting a guest. Every mode but "disabled"
        // also turns the master switch on - the limit alone is no longer enough to apply.
        if (![mode isEqual:@"disabled"]) AKBatterySaverSetEnabled(YES);
        AKBatterySaverCommitLaunchSnapshot();

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        assert(device != nil);
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = device;
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = YES;
        layer.frame = CGRectMake(0, 0, 64, 64);
        layer.drawableSize = CGSizeMake(64, 64);
        id<MTLCommandQueue> queue = [device newCommandQueue];
        assert(queue != nil);

        // Everything is installed before the adapter runs, because the adapter swizzles what the
        // class implements at the moment it is installed.
        id<MTLCommandBuffer> probe = [queue commandBuffer];
        Class bufferClass = object_getClass(probe);
        IMP immediateBefore = class_getMethodImplementation(bufferClass, @selector(presentDrawable:));
        InstallDoubles(probe, withMinimumDouble);
        AKInstallMetalPresentationDiagnostics(device);
        IMP immediateAfter = class_getMethodImplementation(bufferClass, @selector(presentDrawable:));

        const int frames = 45;
        for (int index = 0; index < frames; index++) {
            id<CAMetalDrawable> drawable = [layer nextDrawable];
            assert(drawable != nil);
            id<MTLCommandBuffer> buffer = [queue commandBuffer];
            assert(buffer != nil);
            sRequestedTime = CACurrentMediaTime();
            // Every seventh frame the guest asks for a time 50 ms after the last presentation,
            // which is later than the cap allows: that frame is kept at the guest's own time.
            if (lateRequests && (index % 7) == 3 && sTargets.count)
                sRequestedTime = sTargets.lastObject.doubleValue + 0.05;
            switch (path) {
                case PathImmediate: [buffer presentDrawable:drawable]; break;
                case PathAtTime: [buffer presentDrawable:drawable atTime:sRequestedTime]; break;
                case PathMinimum: PresentAfterMinimum(buffer, drawable, duration); break;
            }
            [buffer commit];
            [buffer waitUntilCompleted];
        }

        uint64_t immediate = 0, extended = 0, raised = 0, kept = 0, bypassed = 0;
        AKMetalBatterySaverPacingCounts(&immediate, &extended, &raised, &kept, &bypassed);
        printf("mode=%s immediate=%llu extended=%llu raised=%llu kept=%llu bypassed=%llu durations=%lu targets=%lu hook=%s\n",
               argv[1], (unsigned long long)immediate, (unsigned long long)extended,
               (unsigned long long)raised, (unsigned long long)kept, (unsigned long long)bypassed,
               (unsigned long)sDurations.count, (unsigned long)sTargets.count,
               immediateBefore == immediateAfter ? "not installed" : "installed");

        // 30 FPS is a frame every 33.333 ms, and no two frames closer than that.
        const double cappedInterval = 1.0 / 30.0;
        const double tolerance = 1e-6;

        // --- The accounting the HUD reads is presented frames, not acquired drawables: ten
        // presented timestamps 1/30 s apart are 30 presented FPS.
        double base = CACurrentMediaTime();
        for (int index = 0; index < 10; index++) AKRecordMetalFramePresented(base + index * cappedInterval);
        double measuredFPS = AKMetalCurrentFPS();
        assert(fabs(measuredFPS - 30.0) < 1.5);

        if (!capped) {
            // Off: no hook is installed at all, so the guest's immediate presentation reaches
            // Metal as an immediate presentation - not one timed call, not one duration, not
            // one counter. This is the transparency the whole option is judged on.
            assert(immediateBefore == immediateAfter);
            assert(immediate == 0 && extended == 0 && raised == 0 && kept == 0 && bypassed == 0);
            assert(sTargets.count == 0);
            assert(sDurations.count == 0);
            printf("off: no presentation hook installed; %d immediate presentations reached Metal unchanged\n", frames);
        } else if (path == PathImmediate && withMinimumDouble) {
            // Every immediate presentation became a minimum-duration one, held for exactly the
            // cap's interval.
            assert(immediateBefore != immediateAfter);
            assert(immediate == (uint64_t)frames);
            assert(sDurations.count == (NSUInteger)frames);
            for (NSNumber *each in sDurations) assert(fabs(each.doubleValue - cappedInterval) < tolerance);
            // The timed presentations behind the double follow the same cadence.
            for (NSUInteger index = 1; index < sTargets.count; index++)
                assert(sTargets[index].doubleValue - sTargets[index - 1].doubleValue >= cappedInterval - tolerance);
            printf("immediate30: %d immediate presentations became minimum-duration at %.1f ms\n",
                   frames, cappedInterval * 1000.0);
        } else if (path == PathImmediate) {
            // Without minimum-duration presentation the adapter uses timed presentation with the
            // same no-earlier-than target - the path a simulator session takes - and the targets
            // still form a 1/30 s cadence.
            assert(immediate == (uint64_t)frames);
            assert(sTargets.count == (NSUInteger)frames);
            for (NSUInteger index = 1; index < sTargets.count; index++)
                assert(sTargets[index].doubleValue - sTargets[index - 1].doubleValue >= cappedInterval - tolerance);
            printf("immediate30-fallback: %d immediate presentations became timed, no two targets closer than %.1f ms\n",
                   frames, cappedInterval * 1000.0);
        } else if (path == PathAtTime) {
            // atTime: keeps its meaning - the frame is presented at the guest's own time when that
            // is later than the cap allows - and is raised when it is earlier.
            assert(raised + kept == (uint64_t)frames);
            assert(raised > 0);
            if (lateRequests) assert(kept > 0);
            for (NSUInteger index = 0; index < sTargets.count; index++)
                assert(sTargets[index].doubleValue >= sRequested[index].doubleValue);
            for (NSUInteger index = 1; index < sTargets.count; index++)
                assert(sTargets[index].doubleValue - sTargets[index - 1].doubleValue >= cappedInterval - tolerance);
            printf("attime30: %llu frames raised to the no-earlier-than target, no two closer than %.1f ms\n",
                   (unsigned long long)raised, cappedInterval * 1000.0);
        } else if (!longer) {
            // A minimum duration shorter than the cap is raised to it.
            assert(extended == (uint64_t)frames);
            assert(sDurations.count == (NSUInteger)frames);
            for (NSNumber *each in sDurations) assert(fabs(each.doubleValue - cappedInterval) < tolerance);
            printf("minimum30: %llu short minimum durations raised to the cap\n", (unsigned long long)extended);
        } else {
            // A longer one belongs to the guest and is passed through unchanged.
            assert(kept == (uint64_t)frames);
            assert(extended == 0);
            assert(sDurations.count == (NSUInteger)frames);
            for (NSNumber *each in sDurations) assert(fabs(each.doubleValue - duration) < tolerance);
            printf("minimum-longer: %llu longer guest durations preserved (%.0f ms)\n",
                   (unsigned long long)kept, duration * 1000.0);
        }
        printf("test_metal_pacing %s: PASS (presented accounting %.1f FPS)\n", argv[1], measuredFPS);
    }
    return 0;
}
