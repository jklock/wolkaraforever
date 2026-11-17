// The frame limit: the launcher's row, the charger (Automatic), Low Power Mode and heat set the rate the game's frames
// are shown at, through the present itself - a frame presented through the command buffer is
// held on screen for at least 1/limit, so the drawable pool, not a sleep, slows the game's loop.
//
// A bare process in the simulator. A fake command buffer class records what the pacer turned each present
// into; a real CAMetalLayer and the simulator's own Metal device check that the pacer finds the class the
// game's buffers really are; the pacer's log lines are read back from this process's stderr.
//
//   test_frame_pacing
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <unistd.h>
#import "BatterySettings.h"
#import "FramePacing.h"

static int checks = 0, failures = 0;
static FILE *gReport;
#define CHECK(condition, ...) do { checks++; if (!(condition)) { failures++; \
    fprintf(gReport, "FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString alloc] initWithFormat:@__VA_ARGS__].UTF8String); } } while (0)

// What the pacer's AKLog lines said: stderr goes to a file this test reads back.
static NSString *gLogPath;
static NSUInteger gLogRead;
static NSString *NewLog(void) {
    fflush(stderr);
    NSData *data = [NSData dataWithContentsOfFile:gLogPath];
    NSString *all = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    NSString *fresh = all.length > gLogRead ? [all substringFromIndex:gLogRead] : @"";
    gLogRead = all.length;
    return fresh;
}

// A command buffer that records what reached it.
@interface AKFakeCommandBuffer : NSObject
@property NSMutableArray<NSString *> *calls;
- (void)presentDrawable:(id)drawable;
- (void)presentDrawable:(id)drawable afterMinimumDuration:(CFTimeInterval)duration;
- (void)presentDrawable:(id)drawable atTime:(CFTimeInterval)time;
@end
@implementation AKFakeCommandBuffer
- (instancetype)init { if ((self = [super init])) _calls = [NSMutableArray array]; return self; }
- (void)presentDrawable:(id)drawable { (void)drawable; [_calls addObject:@"plain"]; }
- (void)presentDrawable:(id)drawable afterMinimumDuration:(CFTimeInterval)duration { (void)drawable; [_calls addObject:[NSString stringWithFormat:@"after %.4f", duration]]; }
- (void)presentDrawable:(id)drawable atTime:(CFTimeInterval)time { (void)drawable; [_calls addObject:[NSString stringWithFormat:@"at %.1f", time]]; }
@end


// The duration the pacer asks for at `rate`: one millisecond short of 1/rate, so a frame is shown for exactly
// the whole number of 120 Hz refreshes the rate means and rounding never adds one more.
static NSString *After(NSInteger rate) { return [NSString stringWithFormat:@"after %.4f", 1.0 / rate - 0.001]; }

static void the_policy(void) {
    // Automatic is 30 on battery and 60 plugged in (charging or full); a power source iOS cannot name is 60.
    AKFrameLimitDecision d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourcePlugged, NO, NSProcessInfoThermalStateNominal, NO);
    CHECK(d.rate == 60 && d.reason == AKFrameLimitReasonSetting, "Automatic plugged in is 60: %ld", (long)d.rate);
    d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourceBattery, NO, NSProcessInfoThermalStateNominal, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonSetting, "Automatic on battery is 30: %ld", (long)d.rate);
    d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourceUnknown, NO, NSProcessInfoThermalStateNominal, NO);
    CHECK(d.rate == 60 && d.reason == AKFrameLimitReasonSetting, "Automatic with the power source unknown is 60: %ld", (long)d.rate);
    // UIDeviceBatteryState: 0 unknown, 1 unplugged, 2 charging, 3 full; anything else is unknown.
    CHECK(AKPowerSourceForBatteryState(UIDeviceBatteryStateUnknown) == AKPowerSourceUnknown, "unknown");
    CHECK(AKPowerSourceForBatteryState(UIDeviceBatteryStateUnplugged) == AKPowerSourceBattery, "unplugged is on battery");
    CHECK(AKPowerSourceForBatteryState(UIDeviceBatteryStateCharging) == AKPowerSourcePlugged, "charging is plugged in");
    CHECK(AKPowerSourceForBatteryState(UIDeviceBatteryStateFull) == AKPowerSourcePlugged, "full is plugged in");
    CHECK(AKPowerSourceForBatteryState(7) == AKPowerSourceUnknown && AKPowerSourceForBatteryState(-1) == AKPowerSourceUnknown, "a value iOS never gives is unknown");
    // A manual choice is the choice, on battery or not.
    for (NSNumber *choice in @[@30, @60]) {
        d = AKFrameLimitDecide(choice.integerValue, AKPowerSourceBattery, NO, NSProcessInfoThermalStateNominal, NO);
        CHECK(d.rate == choice.integerValue && d.reason == AKFrameLimitReasonSetting, "%@ stays %@ on battery: %ld", choice, choice, (long)d.rate);
    }
    // Low Power Mode and heat stay on top: Automatic plugged in still drops to 30; on battery it is 30 already.
    d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourcePlugged, YES, NSProcessInfoThermalStateNominal, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonLowPower, "plugged in + Low Power Mode: 30: %ld", (long)d.rate);
    d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourcePlugged, NO, NSProcessInfoThermalStateSerious, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonThermal, "plugged in + Serious: 30: %ld", (long)d.rate);
    d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourceBattery, YES, NSProcessInfoThermalStateSerious, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonSetting, "on battery it is 30 already: the setting's: %ld", (long)d.rate);
    d = AKFrameLimitDecide(AKFrameLimitAutomatic, AKPowerSourceBattery, NO, NSProcessInfoThermalStateNominal, YES);
    CHECK(d.rate == 10 && d.reason == AKFrameLimitReasonIdle, "the AFK saver under Automatic on battery: %ld", (long)d.rate);
    CHECK(AKFrameLimitRateForChoice(AKFrameLimitAutomatic, AKPowerSourceBattery) == 30
          && AKFrameLimitRateForChoice(AKFrameLimitAutomatic, AKPowerSourcePlugged) == 60
          && AKFrameLimitRateForChoice(60, AKPowerSourceBattery) == 60, "the rate a choice means");
    // 120 is not offered (on the iPad it never presented above 60, for 43 % more CPU): anything that still asks for it
    // (a stale caller) gets a 60th, never the panel's rate.
    CHECK(AKFrameLimitRateForChoice(120, AKPowerSourceBattery) == 60 && AKFrameLimitRateForChoice(120, AKPowerSourcePlugged) == 60, "a 120 is 60");
    // 40 is not offered: the iPad showed it at 30, its presents landing on a 60 Hz grid.
    CHECK([AKFrameLimitChoices() isEqualToArray:(@[@0, @30, @60])], "the row: Automatic, 30, 60: %@", AKFrameLimitChoices());
    for (NSNumber *choice in @[@30, @60]) {
        d = AKFrameLimitDecide(choice.integerValue, AKPowerSourcePlugged, NO, NSProcessInfoThermalStateFair, NO);
        CHECK(d.rate == choice.integerValue && d.reason == AKFrameLimitReasonSetting, "%@ is itself at Fair: %ld", choice, (long)d.rate);
    }
    d = AKFrameLimitDecide(60, AKPowerSourcePlugged, YES, NSProcessInfoThermalStateNominal, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonLowPower, "Low Power Mode lowers 60 to 30: %ld", (long)d.rate);
    d = AKFrameLimitDecide(60, AKPowerSourcePlugged, NO, NSProcessInfoThermalStateSerious, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonThermal, "Serious lowers 60 to 30: %ld", (long)d.rate);
    d = AKFrameLimitDecide(60, AKPowerSourcePlugged, NO, NSProcessInfoThermalStateCritical, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonThermal, "Critical too");
    d = AKFrameLimitDecide(30, AKPowerSourcePlugged, YES, NSProcessInfoThermalStateSerious, NO);
    CHECK(d.rate == 30 && d.reason == AKFrameLimitReasonSetting, "a chosen 30 stays the setting's");
    d = AKFrameLimitDecide(60, AKPowerSourcePlugged, YES, NSProcessInfoThermalStateNominal, YES);
    CHECK(d.rate == 10 && d.reason == AKFrameLimitReasonIdle, "the AFK saver wins over Low Power Mode: %ld", (long)d.rate);
}

static void the_stored_values(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"test_frame_pacing"];
    [defaults removePersistentDomainForName:@"test_frame_pacing"];
    CHECK(AKFrameLimitChoice(defaults) == AKFrameLimitAutomatic, "nothing stored is Automatic");
    CHECK(AKAFKSaverMinutes(defaults) == 5, "nothing stored is 5 minutes");
    [defaults setInteger:30 forKey:AKFrameLimitDefaultsKey];
    [defaults setInteger:0 forKey:AKAFKSaverDefaultsKey];
    CHECK(AKFrameLimitChoice(defaults) == 30 && AKAFKSaverMinutes(defaults) == 0, "30 and Off read back");
    // A stored 40 reads as what the iPad really showed for it: 30, never Automatic's 60.
    [defaults setInteger:40 forKey:AKFrameLimitDefaultsKey];
    CHECK(AKFrameLimitChoice(defaults) == 30, "a stored 40 reads as 30: %ld", (long)AKFrameLimitChoice(defaults));
    // A stored 120 reads as 60, what the iPad really presented for it: never uncapped, never Automatic.
    [defaults setInteger:120 forKey:AKFrameLimitDefaultsKey];
    CHECK(AKFrameLimitChoice(defaults) == 60, "a stored 120 reads as 60: %ld", (long)AKFrameLimitChoice(defaults));
    [defaults setInteger:45 forKey:AKFrameLimitDefaultsKey];
    [defaults setInteger:7 forKey:AKAFKSaverDefaultsKey];
    CHECK(AKFrameLimitChoice(defaults) == AKFrameLimitAutomatic, "a rate not offered is Automatic, never uncapped");
    CHECK(AKAFKSaverMinutes(defaults) == 5, "minutes not offered are the default");
    [defaults setObject:@"30" forKey:AKFrameLimitDefaultsKey];
    CHECK(AKFrameLimitChoice(defaults) == AKFrameLimitAutomatic, "a string is not a choice");
    [defaults removePersistentDomainForName:@"test_frame_pacing"];
}

static void presents_are_held_for_the_limit(void) {
    AKFramePacingInstallOnCommandBufferClass(AKFakeCommandBuffer.class);
    AKFramePacingInstallOnCommandBufferClass(AKFakeCommandBuffer.class);   // twice is once
    CHECK(AKFramePacingIsInstalledOnClass(AKFakeCommandBuffer.class), "installed on the class");
    AKFakeCommandBuffer *buffer = [AKFakeCommandBuffer new];
    NSObject *drawable = [NSObject new];
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);   // Automatic plugged in: 60 (the charger's own test is below)
    NewLog();

    AKFramePacingUpdate(AKFrameLimitAutomatic, NO, NSProcessInfoThermalStateNominal);
    [buffer presentDrawable:drawable];
    CHECK([buffer.calls.lastObject isEqual:After(60)], "Automatic: held for a 60th: %@", buffer.calls.lastObject);
    CHECK(AKFramePacingCurrentRate() == 60, "rate 60");

    AKFramePacingUpdate(30, NO, NSProcessInfoThermalStateNominal);
    NSString *log = NewLog();
    [buffer presentDrawable:drawable];
    CHECK([buffer.calls.lastObject isEqual:After(30)], "30: %@", buffer.calls.lastObject);
    CHECK([log containsString:@"frame limit: 30 fps (setting: 30)"], "logged: %@", log);

    // The game's own minimum duration: the longer of the two.
    AKFramePacingUpdate(60, NO, NSProcessInfoThermalStateNominal);
    [buffer presentDrawable:drawable afterMinimumDuration:0.05];
    CHECK([buffer.calls.lastObject isEqual:@"after 0.0500"], "the game's longer wait stays: %@", buffer.calls.lastObject);
    [buffer presentDrawable:drawable afterMinimumDuration:0.005];
    CHECK([buffer.calls.lastObject isEqual:After(60)], "a shorter one is raised to the limit: %@", buffer.calls.lastObject);
    // A present at a time the game chose is the game's: untouched.
    [buffer presentDrawable:drawable atTime:12.5];
    CHECK([buffer.calls.lastObject isEqual:@"at 12.5"], "atTime untouched: %@", buffer.calls.lastObject);

    // 120 is not offered: a caller that still passes it is held to a 60th, never left unlimited.
    AKFramePacingUpdate(120, NO, NSProcessInfoThermalStateNominal);
    [buffer presentDrawable:drawable];
    CHECK([buffer.calls.lastObject isEqual:After(60)] && AKFramePacingCurrentRate() == 60, "a 120 is held for a 60th: %@", buffer.calls.lastObject);
    CHECK(AKFramePacingMinimumDuration() > 0, "a minimum at 120");

    // Low Power Mode and heat: 30 for as long as they last, the setting again when they clear.
    AKFramePacingUpdate(60, YES, NSProcessInfoThermalStateNominal);
    log = NewLog();
    [buffer presentDrawable:drawable];
    CHECK([buffer.calls.lastObject isEqual:After(30)] && AKFramePacingCurrentRate() == 30, "Low Power Mode: 30: %@", buffer.calls.lastObject);
    CHECK([log containsString:@"frame limit: 30 fps (Low Power Mode)"], "logged: %@", log);
    AKFramePacingUpdate(60, NO, NSProcessInfoThermalStateSerious);
    log = NewLog();
    CHECK(AKFramePacingCurrentRate() == 30 && [log containsString:@"frame limit: 30 fps (thermal state serious or above)"], "Serious: %@", log);
    AKFramePacingUpdate(60, NO, NSProcessInfoThermalStateSerious);
    CHECK(NewLog().length == 0, "the same state again logs nothing");
    AKFramePacingUpdate(60, NO, NSProcessInfoThermalStateFair);
    log = NewLog();
    [buffer presentDrawable:drawable];
    CHECK([buffer.calls.lastObject isEqual:After(60)], "cooled to Fair: back to the setting: %@", buffer.calls.lastObject);
    CHECK([log containsString:@"frame limit: 60 fps (setting: 60)"], "logged: %@", log);

    // The AFK saver: 10 while dimmed, whatever the setting; the setting again after.
    AKFramePacingSetIdle(true);
    log = NewLog();
    [buffer presentDrawable:drawable];
    CHECK([buffer.calls.lastObject isEqual:After(10)], "idle: a 10th: %@", buffer.calls.lastObject);
    CHECK([log containsString:@"frame limit: 10 fps (AFK saver)"], "logged: %@", log);
    AKFramePacingUpdate(60, YES, NSProcessInfoThermalStateNominal);
    CHECK(AKFramePacingCurrentRate() == 10, "still 10 with Low Power Mode on top");
    AKFramePacingSetIdle(false);
    CHECK(AKFramePacingCurrentRate() == 30, "awake with Low Power Mode on: 30");
    AKFramePacingUpdate(AKFrameLimitAutomatic, NO, NSProcessInfoThermalStateNominal);
    CHECK(AKFramePacingCurrentRate() == 60, "and 60 when it clears");
}

// What the adapter's load asked of UIDevice. The simulator ignores battery monitoring (it reads NO whatever is set, and
// the state stays unknown), so the setter is watched instead: this constructor runs before the adapter's because
// test_battery_ui.sh links this file first (Mach-O runs an image's constructors in link order).
static int gMonitoringSetYes = 0;
static void (*gOriginalSetMonitoring)(id, SEL, BOOL);
static void AKWatchedSetMonitoring(id device, SEL selector, BOOL on) {
    if (on) gMonitoringSetYes++;
    gOriginalSetMonitoring(device, selector, on);
}
__attribute__((constructor)) static void AKWatchBatteryMonitoring(void) {
    Method method = class_getInstanceMethod(UIDevice.class, @selector(setBatteryMonitoringEnabled:));
    gOriginalSetMonitoring = (void *)method_setImplementation(method, (IMP)AKWatchedSetMonitoring);
}

// Automatic follows the charger as the game runs - 30 on battery, 60 plugged in (charging or full), 60 when iOS cannot
// say - and says why in the log. A manual choice never moves with it.
static void automatic_follows_the_charger(void) {
    AKFakeCommandBuffer *buffer = [AKFakeCommandBuffer new];
    NSObject *drawable = [NSObject new];
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
    AKFramePacingUpdate(AKFrameLimitAutomatic, NO, NSProcessInfoThermalStateNominal);
    NewLog();
    AKFramePacingSetPowerSource(AKPowerSourceBattery);
    NSString *log = NewLog();
    [buffer presentDrawable:drawable];
    CHECK(AKFramePacingCurrentRate() == 30 && [buffer.calls.lastObject isEqual:After(30)], "unplugged: 30: %@", buffer.calls.lastObject);
    CHECK([log containsString:@"frame limit: 30 fps (Automatic, on battery)"], "logged: %@", log);
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
    log = NewLog();
    [buffer presentDrawable:drawable];
    CHECK(AKFramePacingCurrentRate() == 60 && [buffer.calls.lastObject isEqual:After(60)], "plugged in: 60: %@", buffer.calls.lastObject);
    CHECK([log containsString:@"frame limit: 60 fps (Automatic, plugged in)"], "logged: %@", log);
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
    CHECK(NewLog().length == 0, "charging to full is still plugged in: nothing new to say");
    AKFramePacingSetPowerSource(AKPowerSourceUnknown);
    log = NewLog();
    CHECK(AKFramePacingCurrentRate() == 60 && [log containsString:@"frame limit: 60 fps (Automatic, power source unknown)"], "unknown: 60: %@", log);
    // Low Power Mode on top: plugged in it lowers 60 to 30; on battery Automatic is 30 already.
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
    AKFramePacingUpdate(AKFrameLimitAutomatic, YES, NSProcessInfoThermalStateNominal);
    log = NewLog();
    CHECK(AKFramePacingCurrentRate() == 30 && [log containsString:@"frame limit: 30 fps (Low Power Mode)"], "plugged in + Low Power Mode: %@", log);
    AKFramePacingSetPowerSource(AKPowerSourceBattery);
    log = NewLog();
    CHECK(AKFramePacingCurrentRate() == 30 && [log containsString:@"frame limit: 30 fps (Automatic, on battery)"], "unplugged under Low Power Mode: %@", log);
    AKFramePacingUpdate(AKFrameLimitAutomatic, NO, NSProcessInfoThermalStateNominal);
    CHECK(AKFramePacingCurrentRate() == 30, "Low Power Mode off, still on battery: 30");
    // A manual choice is the choice: unplugging changes nothing and says nothing.
    AKFramePacingUpdate(60, NO, NSProcessInfoThermalStateNominal);
    NewLog();
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
    AKFramePacingSetPowerSource(AKPowerSourceBattery);
    CHECK(AKFramePacingCurrentRate() == 60 && NewLog().length == 0, "a chosen 60 on battery stays 60, silently");
    AKFramePacingUpdate(30, NO, NSProcessInfoThermalStateNominal);
    CHECK(AKFramePacingCurrentRate() == 30, "a chosen 30 plugged in stays 30");
    AKFramePacingUpdate(AKFrameLimitAutomatic, NO, NSProcessInfoThermalStateNominal);
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
}

// The wiring on the iPad: the adapter turns on battery monitoring at load and re-reads UIDevice's battery state on each
// UIDeviceBatteryStateDidChangeNotification (on the main queue), so the charger applies live.
static void battery_notifications_reread_the_power_source(void) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);   // the load's main-queue half
    CHECK(gMonitoringSetYes >= 1, "the adapter's load turned battery monitoring on: %d", gMonitoringSetYes);
    AKFramePacingUpdate(AKFrameLimitAutomatic, NO, NSProcessInfoThermalStateNominal);
    AKFramePacingSetPowerSource(AKPowerSourceBattery);
    AKPowerSource real = AKPowerSourceForBatteryState(UIDevice.currentDevice.batteryState);
    [NSNotificationCenter.defaultCenter postNotificationName:UIDeviceBatteryStateDidChangeNotification object:UIDevice.currentDevice];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    NSInteger expected = AKFrameLimitDecide(AKFrameLimitAutomatic, real, NSProcessInfo.processInfo.isLowPowerModeEnabled,
                                            NSProcessInfo.processInfo.thermalState, NO).rate;
    CHECK(AKFramePacingCurrentRate() == expected, "battery notification: %ld, expected %ld (UIDevice says %ld)",
          (long)AKFramePacingCurrentRate(), (long)expected, (long)UIDevice.currentDevice.batteryState);
    printf("NOTE this simulator's battery state: %ld\n", (long)UIDevice.currentDevice.batteryState);
    AKFramePacingSetPowerSource(AKPowerSourcePlugged);
}

// The pacer follows the iPad: a power or thermal notification re-reads the row and the process's state.
static void notifications_reread_the_state(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:30 forKey:AKFrameLimitDefaultsKey];
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:NSProcessInfo.processInfo];
    BOOL lowPower = NSProcessInfo.processInfo.isLowPowerModeEnabled;
    NSInteger thermal = NSProcessInfo.processInfo.thermalState;
    NSInteger expected = AKFrameLimitDecide(30, AKPowerSourcePlugged, lowPower, thermal, NO).rate;
    CHECK(AKFramePacingCurrentRate() == expected, "power notification: %ld, expected %ld (low power %d, thermal %ld)",
          (long)AKFramePacingCurrentRate(), (long)expected, lowPower, (long)thermal);
    [defaults setInteger:120 forKey:AKFrameLimitDefaultsKey];   // a stored 120 reads as 60
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoThermalStateDidChangeNotification object:NSProcessInfo.processInfo];
    expected = AKFrameLimitDecide(60, AKPowerSourcePlugged, lowPower, thermal, NO).rate;
    CHECK(AKFramePacingCurrentRate() == expected, "thermal notification: %ld, expected %ld", (long)AKFramePacingCurrentRate(), (long)expected);
    [defaults removeObjectForKey:AKFrameLimitDefaultsKey];
    AKFramePacingRefresh();
}

// The real thing, as far as a simulator goes: the game asks its CAMetalLayer for a drawable, and the pacer
// finds the class the device's command buffers are and paces it.
static void the_real_command_buffer_class_is_found(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { printf("NOTE no Metal device in this simulator; the real-class check is skipped\n"); return; }
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.drawableSize = CGSizeMake(64, 64);
    id<MTLCommandQueue> queue = [device newCommandQueue];
    Class cls = object_getClass([queue commandBuffer]);
    NewLog();
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    CHECK(drawable != nil, "a drawable");
    CHECK(AKFramePacingIsInstalledOnClass(cls), "the pacer is on %@ after the first drawable", NSStringFromClass(cls));
    NSString *log = NewLog();
    NSString *line = [NSString stringWithFormat:@"frame limit: presents through %@ are paced", NSStringFromClass(cls)];
    CHECK([log containsString:line], "logged: %@", log);
    // A frame through it still presents and completes.
    id<MTLCommandBuffer> buffer = [queue commandBuffer];
    [buffer presentDrawable:drawable];
    [buffer commit];
    [buffer waitUntilCompleted];
    CHECK(buffer.status == MTLCommandBufferStatusCompleted, "the paced present completed: %ld %@", (long)buffer.status, buffer.error);
    // The simulator's drawables have no minimum-duration present (its SDK does not declare one), so there the
    // present stays plain and how long a frame is held is the iPad's check (the pacer's "the game drew" line).
    if (![(id)drawable respondsToSelector:NSSelectorFromString(@"presentAfterMinimumDuration:")])
        printf("NOTE this simulator's drawables have no minimum-duration present: frame timing is checked on the iPad\n");
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        gReport = fdopen(dup(STDOUT_FILENO), "w");
        setvbuf(gReport, NULL, _IONBF, 0);
        gLogPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"frame-pacing-%d.log", getpid()]];
        if (!freopen(gLogPath.fileSystemRepresentation, "w", stderr)) { fprintf(gReport, "cannot capture stderr\n"); return 2; }
        setvbuf(stderr, NULL, _IONBF, 0);
        void (*tests[])(void) = {the_policy, the_stored_values, presents_are_held_for_the_limit, automatic_follows_the_charger,
            battery_notifications_reread_the_power_source, notifications_reread_the_state, the_real_command_buffer_class_is_found};
        const char *names[] = {"the_policy", "the_stored_values", "presents_are_held_for_the_limit", "automatic_follows_the_charger",
            "battery_notifications_reread_the_power_source", "notifications_reread_the_state", "the_real_command_buffer_class_is_found"};
        for (size_t i = 0; i < sizeof tests / sizeof *tests; i++) {
            int before = failures;
            tests[i]();
            fprintf(gReport, "%s %s\n", failures == before ? "PASS" : "FAIL", names[i]);
        }
        fprintf(gReport, "FRAME_PACING_%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
        return failures ? 1 : 0;
    }
}
