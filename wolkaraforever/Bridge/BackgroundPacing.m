#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "AKSupport.h"

// A guest that keeps rendering while its window is off screen burns a whole core,
// and iPadOS kills a background app that exceeds its CPU budget (report 202,
// "cpu_resource") after two or three minutes. That is what ended sessions the
// moment the user switched to another app, even with the audio background mode
// keeping the process alive.
//
// The guest paces itself on the drawable - CAMetalLayer hands out a few at a time
// and nextDrawable waits for one - so capping frames here slows the guest's whole
// loop, network and timers included, instead of stopping it: the game stays
// connected and stays alive while another app is in front. Frames return to the
// display's own rate as soon as the app is active again, and nothing is capped
// while it is.
#define AKBackgroundFrameInterval 0.2
#define AKBackgroundWakeSlice 0.005

static id<CAMetalDrawable> (*originalNextDrawable)(id,SEL);
static _Atomic(double) lastAcquired;
static atomic_bool throttling;
static _Atomic(double) foregroundAt;
static atomic_bool foregroundDrawablePending;

static IMP replace(Class cls,SEL selector,IMP implementation) {
    Method method=class_getInstanceMethod(cls,selector); if(!method) return NULL;
    IMP original=method_getImplementation(method);
    class_replaceMethod(cls,selector,implementation,method_getTypeEncoding(method)); return original;
}
static id<CAMetalDrawable> pacedNextDrawable(id layer,SEL selector) {
    // This is deliberately an atomic read rather than UIApplication state on
    // every guest frame. Notifications change it at the same lifecycle edges
    // as the old query, and foregrounding clears the deadline before rendering
    // resumes, so return to the game never inherits a background sleep.
    BOOL hidden=atomic_load(&throttling);
    if(hidden) {
        double wait=AKBackgroundFrameInterval-(NSProcessInfo.processInfo.systemUptime-atomic_load(&lastAcquired));
        // Do not sleep for the full 200 ms interval in one call: foregrounding
        // can happen while this thread is asleep, which otherwise turns the
        // first returning frame into a visible hitch. Check lifecycle state at
        // bounded intervals and abandon the background deadline immediately.
        double deadline=NSProcessInfo.processInfo.systemUptime+MAX(0,wait);
        while(atomic_load(&throttling)) {
            double remaining=deadline-NSProcessInfo.processInfo.systemUptime;
            if(remaining<=0) break;
            [NSThread sleepForTimeInterval:MIN(remaining,AKBackgroundWakeSlice)];
        }
    }
    id<CAMetalDrawable> drawable=originalNextDrawable(layer,selector);
    atomic_store(&lastAcquired,NSProcessInfo.processInfo.systemUptime);
    if(atomic_exchange(&foregroundDrawablePending,false)) {
        double resumeMs=(NSProcessInfo.processInfo.systemUptime-atomic_load(&foregroundAt))*1000.0;
        AKLog(@"background pacing: foreground first drawable after %.1fms",resumeMs);
    }
    return drawable;
}
static void AKSetBackgroundPacing(BOOL hidden) {
    BOOL previous=atomic_exchange(&throttling,hidden);
    if(previous==hidden) return;
    // A stale timestamp would otherwise make the first foreground frame wait.
    atomic_store(&lastAcquired,0);
    if(hidden) AKLog(@"background pacing: frames capped to %.0f/s while another app is in front",1.0/AKBackgroundFrameInterval);
    else {
        atomic_store(&foregroundAt,NSProcessInfo.processInfo.systemUptime);
        atomic_store(&foregroundDrawablePending,true);
        AKLog(@"background pacing: frames at the display's own rate again");
    }
}
static void AKInstallBackgroundLifecycleObservers(void) {
    UIApplication *application=UIApplication.sharedApplication;
    atomic_init(&throttling,application.applicationState!=UIApplicationStateActive);
    atomic_init(&lastAcquired,0);
    atomic_init(&foregroundAt,0);
    atomic_init(&foregroundDrawablePending,false);
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKSetBackgroundPacing(YES); }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKSetBackgroundPacing(YES); }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { AKSetBackgroundPacing(NO); }];
}
void AKInstallMetalBackgroundPacing(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        AKInstallBackgroundLifecycleObservers();
        originalNextDrawable=(void *)replace(CAMetalLayer.class,@selector(nextDrawable),(IMP)pacedNextDrawable);
        if(!originalNextDrawable) AKLog(@"background pacing could not install");
    });
}

// Installed from here, not from a call site: this file is compiled into the Metal
// adapter, which the guest loads before it draws anything, and the platform's own
// files are used as they are. Loading the adapter is therefore the earliest and the
// only place this needs to happen, and the install is idempotent.
__attribute__((constructor)) static void AKBackgroundPacingLoad(void) {
    AKInstallMetalBackgroundPacing();
}
