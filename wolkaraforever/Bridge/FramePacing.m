#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <stdatomic.h>
#import "AKSupport.h"
#import "BatterySettings.h"
#import "FramePacing.h"

// The frame limit (FramePacing.h says how; BatterySettings.h says what; Automatic follows the charger). Without it
// the game runs as fast as the 120 Hz panel lets it: the host tells it the screen is 120 Hz, its vsync is on and its
// own FPS cap is off by default, so in light scenes and menus it drew close to 120 frames a second. Battery is the
// reason, so the limit applies in every interface mode.
//
// Why the present, and not a sleep or a display link. The guest draws from its own loop and waits only on
// -nextDrawable; a display link's frame-rate range only paces work done in its callback, which the guest
// has none of (DisplayRate.m), and dropping presents would still pay for every frame drawn. Sleeping the
// render thread before -nextDrawable (what BackgroundPacing.m does while another app is in front) lands
// frames off the panel's refreshes and judders. A present given a minimum duration is held on screen for
// that long, in step with the refreshes, and the drawables it holds are what make the game's next
// -nextDrawable wait: the panel, the GPU and the game's CPU work all drop to the limit together.
//
// The game's own maxFPS settings are left alone: the host writes no game setting at start, and a player's
// own cap in the game's options still applies on top of this one.

// A frame at `rate` is asked to stay up a millisecond less than 1/rate, so it is shown for exactly the
// whole number of refreshes the rate means: 1/60 on the nose could round up to a third 120 Hz refresh.
// The rates offered (30, 60) are whole numbers of refreshes on a 60 Hz grid as well as a 120 Hz one:
// while the game plays, the iPad presents on a 60 Hz grid (iPad Pro M5, 17 Nov 2026: "40" asked for 24 ms and got
// 33.3 ms, 30 fps), so 40 is not offered; 120 never presented above 60 either, so it is not offered.
#define AKFramePacingMargin 0.001
// How long after a change the drawables are counted, for the "the game drew N a second" line.
#define AKFramePacingMeasureSeconds 5.0

static os_unfair_lock s_lock = OS_UNFAIR_LOCK_INIT;
static NSInteger s_choice = AKFrameLimitAutomatic, s_thermal = 0;
static BOOL s_lowPower = NO, s_idle = NO, s_decided = NO;
static AKPowerSource s_powerSource = AKPowerSourceUnknown;
static AKFrameLimitDecision s_last;
static NSInteger s_lastChoice = -1;
static _Atomic(double) s_minimum = 0;
static atomic_long s_rate = AKFrameLimitPanelRate;
static _Atomic(double) s_measureStart = 0;
static atomic_uint s_measureCount = 0;
static NSMutableSet<NSValue *> *s_installed;

// "setting: 30", "Automatic, on battery", "Automatic, plugged in", "Low Power Mode"...
static NSString *AKFrameLimitDescription(AKFrameLimitDecision decision, NSInteger choice, AKPowerSource power) {
    NSString *why = decision.reason != AKFrameLimitReasonSetting ? AKFrameLimitReasonText(decision.reason)
        : choice != AKFrameLimitAutomatic ? [NSString stringWithFormat:@"setting: %ld", (long)choice]
        : [NSString stringWithFormat:@"Automatic, %@", AKPowerSourceText(power)];
    return [NSString stringWithFormat:@"frame limit: %ld fps (%@)", (long)decision.rate, why];
}

// With the lock held: the decision from the inputs, applied and logged when it changed.
static void AKFramePacingApplyLocked(void) {
    NSInteger choice = s_choice;
    // Under Automatic the last choice remembers the power source too, so "Automatic, on battery" -> "Automatic, plugged
    // in" is said even when Low Power Mode keeps the rate at 30 (a manual choice ignores the charger: nothing to say).
    NSInteger remembered = choice * 10 + (choice == AKFrameLimitAutomatic ? s_powerSource : 0);
    AKFrameLimitDecision decision = AKFrameLimitDecide(choice, s_powerSource, s_lowPower, s_thermal, s_idle);
    if (s_decided && decision.rate == s_last.rate && decision.reason == s_last.reason && remembered == s_lastChoice) return;
    s_decided = YES; s_last = decision; s_lastChoice = remembered;
    double minimum = 1.0 / decision.rate - AKFramePacingMargin;
    atomic_store(&s_minimum, minimum);
    atomic_store(&s_rate, decision.rate);
    AKLog(@"%@", AKFrameLimitDescription(decision, choice, s_powerSource));
    // Count what the game really draws for a few seconds: the device's evidence that the limit took.
    atomic_store(&s_measureCount, 0);
    atomic_store(&s_measureStart, CACurrentMediaTime());
}

void AKFramePacingUpdate(NSInteger choice, BOOL lowPower, NSInteger thermalState) {
    os_unfair_lock_lock(&s_lock);
    s_choice = choice; s_lowPower = lowPower; s_thermal = thermalState;
    AKFramePacingApplyLocked();
    os_unfair_lock_unlock(&s_lock);
}
void AKFramePacingSetIdle(bool idle) {
    os_unfair_lock_lock(&s_lock);
    s_idle = idle;
    AKFramePacingApplyLocked();
    os_unfair_lock_unlock(&s_lock);
}
void AKFramePacingSetPowerSource(NSInteger source) {
    os_unfair_lock_lock(&s_lock);
    s_powerSource = (AKPowerSource)source;
    AKFramePacingApplyLocked();
    os_unfair_lock_unlock(&s_lock);
}
void AKFramePacingRefresh(void) {
    NSProcessInfo *process = NSProcessInfo.processInfo;
    AKFramePacingUpdate(AKFrameLimitChoice(NSUserDefaults.standardUserDefaults), process.isLowPowerModeEnabled, process.thermalState);
}
NSInteger AKFramePacingCurrentRate(void) { return atomic_load(&s_rate); }
BOOL AKFramePacingIsIdle(void) {
    os_unfair_lock_lock(&s_lock);
    BOOL idle = s_idle;
    os_unfair_lock_unlock(&s_lock);
    return idle;
}

double AKFramePacingMinimumDuration(void) { return atomic_load(&s_minimum); }

BOOL AKFramePacingIsInstalledOnClass(Class cls) {
    os_unfair_lock_lock(&s_lock);
    BOOL installed = cls && [s_installed containsObject:[NSValue valueWithPointer:(__bridge const void *)cls]];
    os_unfair_lock_unlock(&s_lock);
    return installed;
}
// Each class gets its own replacement, holding that class's original methods: a later hook on the same class
// (the performance overlay's, Presentation.m) wraps this one, and this one calls what it replaced.
void AKFramePacingInstallOnCommandBufferClass(Class cls) {
    if (!cls) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)cls];
    os_unfair_lock_lock(&s_lock);
    if (!s_installed) s_installed = [NSMutableSet set];
    BOOL already = [s_installed containsObject:key];
    if (!already) [s_installed addObject:key];
    os_unfair_lock_unlock(&s_lock);
    if (already) return;
    SEL plainSelector = @selector(presentDrawable:), afterSelector = @selector(presentDrawable:afterMinimumDuration:);
    Method plain = class_getInstanceMethod(cls, plainSelector), after = class_getInstanceMethod(cls, afterSelector);
    typedef void (*AKPlainPresent)(id, SEL, id);
    typedef void (*AKAfterPresent)(id, SEL, id, CFTimeInterval);
    if (!plain) {
        AKLog(@"frame limit: %@ has no present; its frames are not limited", NSStringFromClass(cls));
        return;
    }
    AKPlainPresent originalPlain = (AKPlainPresent)method_getImplementation(plain);
    if (!after) {
        // A buffer without the convenience (the simulator's): what it stands for, by hand - the drawable's own
        // minimum-duration present once the buffer is scheduled, as Metal documents -presentDrawable: itself. The
        // simulator's drawables have no such present either, so there a frame is presented plainly.
        if (![cls instancesRespondToSelector:@selector(addScheduledHandler:)]) {
            AKLog(@"frame limit: %@ cannot be paced; its frames are not limited", NSStringFromClass(cls));
            return;
        }
        // Sent by name: the simulator's SDK does not declare the drawable's method.
        SEL drawableAfter = NSSelectorFromString(@"presentAfterMinimumDuration:");
        IMP pacedPlain = imp_implementationWithBlock(^(id<MTLCommandBuffer> buffer, id drawable) {
            double minimum = atomic_load(&s_minimum);
            if (minimum <= 0 || ![drawable respondsToSelector:drawableAfter]) { originalPlain(buffer, plainSelector, drawable); return; }
            [buffer addScheduledHandler:^(__unused id<MTLCommandBuffer> scheduled) {
                ((void (*)(id, SEL, CFTimeInterval))objc_msgSend)(drawable, drawableAfter, minimum);
            }];
        });
        class_replaceMethod(cls, plainSelector, pacedPlain, method_getTypeEncoding(plain));
        AKLog(@"frame limit: presents through %@ are paced (by the drawable's own minimum duration)", NSStringFromClass(cls));
        return;
    }
    AKAfterPresent originalAfter = (AKAfterPresent)method_getImplementation(after);
    IMP pacedPlain = imp_implementationWithBlock(^(id buffer, id drawable) {
        double minimum = atomic_load(&s_minimum);
        if (minimum > 0) originalAfter(buffer, afterSelector, drawable, minimum);
        else originalPlain(buffer, plainSelector, drawable);
    });
    // The game's own minimum, if it asks for one: the longer of the two.
    IMP pacedAfter = imp_implementationWithBlock(^(id buffer, id drawable, CFTimeInterval duration) {
        originalAfter(buffer, afterSelector, drawable, MAX(duration, atomic_load(&s_minimum)));
    });
    class_replaceMethod(cls, plainSelector, pacedPlain, method_getTypeEncoding(plain));
    class_replaceMethod(cls, afterSelector, pacedAfter, method_getTypeEncoding(after));
    AKLog(@"frame limit: presents through %@ are paced", NSStringFromClass(cls));
}

// The command buffer class is the device's, and the device is known at the first drawable: one throwaway
// queue and buffer name it (never committed), before the game presents its first frame.
static id<CAMetalDrawable> (*originalNextDrawable)(id, SEL);
static atomic_bool s_discovered = false;
static id<CAMetalDrawable> pacedNextDrawable(id layer, SEL selector) {
    id<CAMetalDrawable> drawable = originalNextDrawable(layer, selector);
    if (!atomic_load(&s_discovered)) {
        id<MTLDevice> device = ((CAMetalLayer *)layer).device;
        id<MTLCommandQueue> queue = device ? [device newCommandQueue] : nil;
        if (queue && !atomic_exchange(&s_discovered, true)) {
            AKFramePacingInstallOnCommandBufferClass(object_getClass([queue commandBuffer]));
            AKFramePacingInstallOnCommandBufferClass(object_getClass([queue commandBufferWithUnretainedReferences]));
        }
    }
    double start = atomic_load(&s_measureStart);
    if (start > 0) {
        unsigned count = atomic_fetch_add(&s_measureCount, 1) + 1;
        double elapsed = CACurrentMediaTime() - start;
        if (elapsed >= AKFramePacingMeasureSeconds && atomic_compare_exchange_strong(&s_measureStart, &start, 0))
            AKLog(@"frame limit: the game drew %.1f frames a second over %.0f s (limit %ld)", count / elapsed, elapsed, (long)atomic_load(&s_rate));
    }
    return drawable;
}

// The charger, on the main thread as UIDevice wants: battery monitoring on (nothing turns it off), the state now,
// then each change as iOS announces it - Automatic applies it at once.
static void AKFramePacingWatchTheCharger(void) {
    UIDevice *device = UIDevice.currentDevice;
    device.batteryMonitoringEnabled = YES;
    AKFramePacingSetPowerSource(AKPowerSourceForBatteryState(device.batteryState));
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        AKFramePacingSetPowerSource(AKPowerSourceForBatteryState(UIDevice.currentDevice.batteryState));
    }];
}

static IMP replace(Class cls, SEL selector, IMP implementation) {
    Method method = class_getInstanceMethod(cls, selector); if (!method) return NULL;
    IMP original = method_getImplementation(method);
    class_replaceMethod(cls, selector, implementation, method_getTypeEncoding(method)); return original;
}

// Installed from the adapter's load, as BackgroundPacing.m is, and for the same reason: the guest loads the
// Metal adapter before it draws. Both replace -nextDrawable and each calls the one it replaced.
__attribute__((constructor)) static void AKFramePacingLoad(void) {
    originalNextDrawable = (void *)replace(CAMetalLayer.class, @selector(nextDrawable), (IMP)pacedNextDrawable);
    if (!originalNextDrawable) AKLog(@"frame limit: could not install; frames are not limited");
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification])
        [center addObserverForName:name object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKFramePacingRefresh(); }];
    // The charger before the first decision when the adapter loads on the main thread, so the first line already says
    // "on battery"; otherwise as soon as the main queue runs (until then Automatic is the unknown source's 60).
    if (NSThread.isMainThread) AKFramePacingWatchTheCharger();
    else dispatch_async(dispatch_get_main_queue(), ^{ AKFramePacingWatchTheCharger(); });
    AKFramePacingRefresh();
}

