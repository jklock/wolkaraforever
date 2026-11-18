#import "InterfaceMode.h"
#import <UIKit/UIKit.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>

NSString *const AKInterfaceModeDefaultsKey = @"WolkaraForeverInterfaceModeV1";
NSString *const AKInterfaceModeIPadOS = @"ipados";
NSString *const AKInterfaceModeIOS = @"ios";
NSString *const AKInterfaceModeIOSDuo = @"iosduo";
NSString *const AKInterfaceModeIPadTouch = @"ipadtouch";
NSString *const AKInterfaceModeAuto = @"auto";
NSString *const AKTouchCrashGuardDefaultsKey = @"WolkaraForeverTouchUncleanStarts";

/// Read on every call rather than cached: the launcher writes the key before a
/// guest starts, and a fixture writes it between two guests in one process, so a
/// cached copy would make the second read answer for the first.
static NSString *AKInterfaceModeStored(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:AKInterfaceModeDefaultsKey];
    return [value isKindOfClass:NSString.class] ? [(NSString *)value lowercaseString] : nil;
}

/// The device's own class, and the only thing "auto" reads: a tablet (and anything else) is
/// iPadOS, a phone is iOS, and the Duo is its own name so the selector can show it. Not a screen
/// size, not a gamepad preference, and not an add-on: the hardware, exactly.
static BOOL AKInterfaceModeHardwareIsDuo(void) {
#if TARGET_OS_SIMULATOR
    NSString *name = NSProcessInfo.processInfo.environment[@"SIMULATOR_DEVICE_NAME"];
    return [name isKindOfClass:NSString.class] && [name containsString:@"Duo"];
#else
    struct utsname system;
    if (uname(&system) != 0) return NO;
    return strcmp(system.machine, "iPhone19,4") == 0;
#endif
}

static NSString *AKInterfaceModeHardwareName(void) {
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return AKInterfaceModeIPadOS;
    return AKInterfaceModeHardwareIsDuo() ? AKInterfaceModeIOSDuo : AKInterfaceModeIOS;
}

BOOL AKInterfaceModeIsMobile(void) {
    NSString *stored = AKInterfaceModeStored();
    if ([stored isEqual:AKInterfaceModeIOS] || [stored isEqual:AKInterfaceModeIOSDuo] ||
        [stored isEqual:AKInterfaceModeIPadTouch]) return YES;
    if ([stored isEqual:AKInterfaceModeAuto]) return ![AKInterfaceModeHardwareName() isEqual:AKInterfaceModeIPadOS];
    // "ipados", nothing at all, or something a hand edit invented: the interface every
    // installation had. Adding "auto" therefore changes no existing installation.
    return NO;
}

BOOL AKInterfaceModeIsTouchPlay(void) {
    return [AKInterfaceModeStored() isEqual:AKInterfaceModeIPadTouch];
}

BOOL AKInterfaceModeIsAutomatic(void) {
    return [AKInterfaceModeStored() isEqual:AKInterfaceModeAuto];
}

NSString *AKInterfaceModeAutomaticName(void) {
    return AKInterfaceModeHardwareName();
}

NSString *AKInterfaceModeName(void) {
    NSString *stored = AKInterfaceModeStored();
    if ([stored isEqual:AKInterfaceModeIOS]) return AKInterfaceModeIOS;
    if ([stored isEqual:AKInterfaceModeIOSDuo]) return AKInterfaceModeIOSDuo;
    if ([stored isEqual:AKInterfaceModeIPadTouch]) return AKInterfaceModeIPadTouch;
    if ([stored isEqual:AKInterfaceModeAuto]) return AKInterfaceModeHardwareName();
    return AKInterfaceModeIPadOS;
}

NSString *AKInterfaceModeStoredName(void) {
    NSString *stored = AKInterfaceModeStored();
    if ([stored isEqual:AKInterfaceModeIOS] || [stored isEqual:AKInterfaceModeIOSDuo] ||
        [stored isEqual:AKInterfaceModeIPadTouch] || [stored isEqual:AKInterfaceModeAuto]) return stored;
    return AKInterfaceModeIPadOS;
}

#pragma mark Crash fallback

// Two unclean starts in a row, and no more: the first could be anything, the second is a pattern.
static const NSInteger AKTouchCrashGuardLimit = 2;

/// The count, never negative, and zero for anything that is not a number.
static NSInteger AKTouchCrashGuardCount(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:AKTouchCrashGuardDefaultsKey];
    return [value isKindOfClass:NSNumber.class] ? MAX(0, [(NSNumber *)value integerValue]) : 0;
}

/// The count lives in the persistent domain, and is written through at once: the process this is
/// counting may be gone a moment later.
static void AKTouchCrashGuardStore(NSInteger count) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (count > 0) [defaults setInteger:count forKey:AKTouchCrashGuardDefaultsKey];
    else [defaults removeObjectForKey:AKTouchCrashGuardDefaultsKey];
    [defaults synchronize];
}

void AKTouchCrashGuardWillStart(void) {
    if (!AKInterfaceModeIsTouchPlay()) return;
    @synchronized (AKTouchCrashGuardDefaultsKey) { AKTouchCrashGuardStore(AKTouchCrashGuardCount() + 1); }
}

/// Takes one start back off the count (never below zero): this session's own, when it is put away
/// or never began. An earlier unclean start stays on record.
static void AKTouchCrashGuardTakeBack(void) {
    if (!AKInterfaceModeIsTouchPlay()) return;
    @synchronized (AKTouchCrashGuardDefaultsKey) { AKTouchCrashGuardStore(MAX(0, AKTouchCrashGuardCount() - 1)); }
}

void AKTouchCrashGuardDidExitCleanly(void) {
    if (!AKInterfaceModeIsTouchPlay()) return;
    AKTouchCrashGuardStore(0);
}

BOOL AKTouchCrashGuardShouldFallBack(void) {
    return AKInterfaceModeIsTouchPlay() && AKTouchCrashGuardCount() >= AKTouchCrashGuardLimit;
}

BOOL AKTouchCrashGuardApplyFallback(void) {
    if (!AKTouchCrashGuardShouldFallBack()) return NO;
    [NSUserDefaults.standardUserDefaults setObject:AKInterfaceModeIPadOS forKey:AKInterfaceModeDefaultsKey];
    AKTouchCrashGuardStore(0);
    return YES;
}

#pragma mark Crash fallback: the session

/// Whether a game session is on, and whether it is currently counted (it is not while the app is in
/// the background). Atomics: the exit paths run on whatever thread the guest leaves from.
static _Atomic BOOL AKCrashSessionActive, AKCrashSessionArmed, AKCrashHandlerInstalled;

void AKTouchCrashGuardExitHandler(void) {
    // Only a session still on is ended by an orderly exit; one that was abandoned (it never started)
    // has already been taken back, and the exit that follows its closing page must not undo that.
    atomic_store(&AKCrashSessionArmed, NO);
    if (atomic_exchange(&AKCrashSessionActive, NO)) AKTouchCrashGuardDidExitCleanly();
}

BOOL AKTouchCrashGuardExitHandlerInstalled(void) {
    return atomic_load(&AKCrashHandlerInstalled);
}

void AKTouchCrashGuardBeginSession(void) {
    // Every other interface mode: nothing is counted, and no exit handler or observer is installed.
    if (!AKInterfaceModeIsTouchPlay()) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Every orderly exit: exit() from the guest, from the game's own Quit through the host, from
        // the closing page. Not a crash, a signal or a kill - those leave the count up, which is
        // the whole signal.
        atexit(AKTouchCrashGuardExitHandler);
        atomic_store(&AKCrashHandlerInstalled, YES);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                        usingBlock:^(__unused NSNotification *note) {
            if (atomic_load(&AKCrashSessionActive) && atomic_exchange(&AKCrashSessionArmed, NO)) AKTouchCrashGuardTakeBack();
        }];
        [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil
                        usingBlock:^(__unused NSNotification *note) {
            if (!atomic_load(&AKCrashSessionActive) || atomic_load(&AKCrashSessionArmed) || !AKInterfaceModeIsTouchPlay()) return;
            AKTouchCrashGuardWillStart();
            atomic_store(&AKCrashSessionArmed, YES);
        }];
    });
    AKTouchCrashGuardWillStart();
    atomic_store(&AKCrashSessionActive, YES);
    atomic_store(&AKCrashSessionArmed, YES);
}

void AKTouchCrashGuardEndSession(void) {
    atomic_store(&AKCrashSessionActive, NO);
    atomic_store(&AKCrashSessionArmed, NO);
    AKTouchCrashGuardDidExitCleanly();
}

void AKTouchCrashGuardAbandonSession(void) {
    atomic_store(&AKCrashSessionActive, NO);
    if (atomic_exchange(&AKCrashSessionArmed, NO)) AKTouchCrashGuardTakeBack();
}
