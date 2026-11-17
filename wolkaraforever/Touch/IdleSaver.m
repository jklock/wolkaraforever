#import "IdleSaver.h"
#import <GameController/GameController.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#import "AKSupport.h"
#import "AKHostLocalization.h"
#import "BatterySettings.h"

// The AFK saver (IdleSaver.h says what it does). Why it exists: during a game the screen never sleeps
// (idleTimerDisabled, Shell/main.m - a locked iPad lost the session), so an iPad put down mid-game stayed lit and
// drew at full rate until it went flat. The session is kept: dim and slow down, never lock.
//
// Cost while playing: one timestamp per event the application dispatches, and one timer per idle period (it fires
// at the deadline, and again later if input came in between). Only while dimmed does a half-second timer look at
// the controllers, the one input that does not pass through the application's events.

static const CGFloat AKIdleDimAlpha = 0.7;
static const NSTimeInterval AKIdleDimmedPoll = 0.5;

@implementation AKIdleSaver {
    NSTimeInterval _lastInput, _dimmedAt;
    double _lastStamp;
    // The waking input, held back to its end: the touches and presses that woke the screen (and any that join them).
    NSMutableSet<UITouch *> *_wakeTouches;
    NSMutableSet<UIPress *> *_wakePresses;
    // What is down now, outside a wake: nothing dims while a finger rests or a key is held.
    NSMutableSet<UITouch *> *_touchesDown;
    NSMutableSet<UIPress *> *_pressesDown;
    NSTimer *_timer;
    UIWindow *_window;
    UIView *_dimView;
}
@synthesize clock = _clock, controllerStamp = _controllerStamp, capSender = _capSender;

- (instancetype)init {
    if ((self = [super init])) {
        _minutes = AKAFKSaverMinutes(NSUserDefaults.standardUserDefaults);
        _appActive = YES;
        _wakeTouches = [NSMutableSet set]; _wakePresses = [NSMutableSet set];
        _touchesDown = [NSMutableSet set]; _pressesDown = [NSMutableSet set];
        self.clock = nil; self.controllerStamp = nil; self.capSender = nil;
        _lastStamp = self.controllerStamp();
        _lastInput = self.clock();
    }
    return self;
}

- (void)setClock:(NSTimeInterval (^)(void))clock {
    _clock = clock ?: ^NSTimeInterval { return NSProcessInfo.processInfo.systemUptime; };
}
- (void)setControllerStamp:(double (^)(void))stamp {
    _controllerStamp = stamp ?: ^double {
        double latest = 0;
        for (GCController *controller in GCController.controllers)
            latest = MAX(latest, controller.physicalInputProfile.lastEventTimestamp);
        GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
        if (keyboard) latest = MAX(latest, keyboard.keyboardInput.lastEventTimestamp);
        for (GCMouse *mouse in GCMouse.mice) latest = MAX(latest, mouse.mouseInput.lastEventTimestamp);
        return latest;
    };
    _lastStamp = _controllerStamp();
}
- (void)setCapSender:(void (^)(BOOL))sender {
    _capSender = sender ?: ^(BOOL idle) {
        // The Metal adapter's frame limit, by name: this adapter does not link that one.
        static void (*setIdle)(bool);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ setIdle = (void (*)(bool))dlsym(RTLD_DEFAULT, "AKFramePacingSetIdle"); });
        if (setIdle) setIdle(idle);
    };
}

- (void)begin {
    _lastInput = self.clock();
    _lastStamp = self.controllerStamp();
    [self schedule];
}

#pragma mark Input

- (void)noteInput { _lastInput = self.clock(); }

static BOOL AKPhaseIsDown(NSInteger phase, BOOL touch) {
    if (touch) return phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled;
    return phase != UIPressPhaseEnded && phase != UIPressPhaseCancelled;
}

- (BOOL)handleEvent:(UIEvent *)event {
    switch (event.type) {
        case UIEventTypeTouches: return [self handleTouches:event.allTouches];
        case UIEventTypePresses:
            return [event isKindOfClass:UIPressesEvent.class] ? [self handlePresses:((UIPressesEvent *)event).allPresses] : NO;
        case UIEventTypeHover:
        case UIEventTypeScroll:
        case UIEventTypeTransform:
            if (_dimmed) { [self wake:@"the pointer"]; return YES; }
            [self noteInput];
            return NO;
        default:
            return NO;
    }
}

- (BOOL)handleTouches:(NSSet<UITouch *> *)touches {
    [self noteInput];
    // A touch event carries every finger that is down: one no longer among them was lost without an end.
    [_wakeTouches intersectSet:touches];
    [_touchesDown intersectSet:touches];
    BOOL began = NO;
    for (UITouch *touch in touches) if (touch.phase == UITouchPhaseBegan) began = YES;
    if (_dimmed && began) {
        [self wake:@"a touch"];
        // Every finger down now is the waking touch's, held back to its lift.
        for (UITouch *touch in touches) if (AKPhaseIsDown(touch.phase, YES)) [_wakeTouches addObject:touch];
        [_touchesDown minusSet:_wakeTouches];
        return YES;
    }
    if (_wakeTouches.count) {
        // Still the waking gesture: a finger that joins it is part of it; each leaves at its lift.
        BOOL ours = YES;
        for (UITouch *touch in touches) {
            if (touch.phase == UITouchPhaseBegan) [_wakeTouches addObject:touch];
            else if (touch.phase != UITouchPhaseStationary && ![_wakeTouches containsObject:touch]) ours = NO;
        }
        for (UITouch *touch in touches) if (!AKPhaseIsDown(touch.phase, YES)) [_wakeTouches removeObject:touch];
        if (ours) return YES;
    }
    for (UITouch *touch in touches) {
        if (AKPhaseIsDown(touch.phase, YES)) { if (![_wakeTouches containsObject:touch]) [_touchesDown addObject:touch]; }
        else [_touchesDown removeObject:touch];
    }
    return NO;
}

- (BOOL)handlePresses:(NSSet<UIPress *> *)presses {
    [self noteInput];
    BOOL began = NO;
    for (UIPress *press in presses) if (press.phase == UIPressPhaseBegan) began = YES;
    if (_dimmed && began) {
        [self wake:@"a key"];
        for (UIPress *press in presses) if (AKPhaseIsDown(press.phase, NO)) [_wakePresses addObject:press];
        [_pressesDown minusSet:_wakePresses];
        return YES;
    }
    if (_wakePresses.count) {
        BOOL ours = YES;
        for (UIPress *press in presses)
            if (press.phase != UIPressPhaseStationary && ![_wakePresses containsObject:press]) ours = NO;
        for (UIPress *press in presses) if (!AKPhaseIsDown(press.phase, NO)) [_wakePresses removeObject:press];
        if (ours) return YES;
    }
    for (UIPress *press in presses) {
        if (AKPhaseIsDown(press.phase, NO)) [_pressesDown addObject:press];
        else [_pressesDown removeObject:press];
    }
    return NO;
}

- (void)setAppActive:(BOOL)active {
    if (_appActive == active) return;
    _appActive = active;
    // Away, the system cancels what was down; back, the person is here.
    if (!active) {
        for (NSMutableSet *set in @[_touchesDown, _pressesDown, _wakeTouches, _wakePresses]) [set removeAllObjects];
        [self schedule];
        return;
    }
    [self noteInput];
    _lastStamp = self.controllerStamp();
    if (_dimmed) [self wake:@"the app came back"];
    [self schedule];
}
- (void)setMinutes:(NSInteger)minutes {
    _minutes = MAX(0, minutes);
    if (_minutes == 0 && _dimmed) [self wake:@"switched off"];
    [self schedule];
}

#pragma mark Time

- (void)tick {
    NSTimeInterval now = self.clock();
    double stamp = self.controllerStamp();
    BOOL controller = stamp != _lastStamp;
    _lastStamp = stamp;
    if (_dimmed) {
        if (controller) [self wake:@"a controller"];
    } else {
        if (controller || _touchesDown.count || _pressesDown.count || _wakeTouches.count || _wakePresses.count) _lastInput = now;
        if (_minutes > 0 && _appActive && now - _lastInput >= _minutes * 60.0) [self dim];
    }
    [self schedule];
}

// One timer at a time: at the deadline while awake (it finds the input since and moves on), every half second while
// dimmed (for the controllers), none while off or away.
- (void)schedule {
    [_timer invalidate]; _timer = nil;
    if (_minutes <= 0 || !_appActive) return;
    NSTimeInterval wait = _dimmed ? AKIdleDimmedPoll : MAX(1.0, _lastInput + _minutes * 60.0 - self.clock());
    __weak AKIdleSaver *weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:wait repeats:NO block:^(NSTimer *timer) { (void)timer; [weakSelf tick]; }];
    // The guest's own loop runs the default mode; common modes include it.
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

#pragma mark The dimmed screen

- (UIView *)dimView {
    if (_dimView) return _dimView;
    _dimView = [UIView new];
    _dimView.accessibilityIdentifier = @"wolkaraforever.afkSaver";
    _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:AKIdleDimAlpha];
    _dimView.userInteractionEnabled = NO;
    _dimView.hidden = YES;
    _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UILabel *label = [UILabel new];
    label.text = AKHostLocalized(@"touch.afk.wake");
    label.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [_dimView addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:_dimView.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:_dimView.centerYAnchor],
    ]];
    return _dimView;
}
// Its own window over the game's, at alert level: above the game and the app's controls, below the system's.
- (void)showDimView {
    UIView *dim = self.dimView;
    if (!_window) {
        UIWindowScene *scene = nil;
        UIApplication *application = UIApplication.sharedApplication;
        for (UIScene *each in application.connectedScenes)
            if ([each isKindOfClass:UIWindowScene.class] && (!scene || each.activationState == UISceneActivationStateForegroundActive))
                scene = (UIWindowScene *)each;
        if (scene) {
            _window = [[UIWindow alloc] initWithWindowScene:scene];
            _window.windowLevel = UIWindowLevelAlert + 1;
            _window.userInteractionEnabled = NO;
            _window.backgroundColor = UIColor.clearColor;
            dim.frame = _window.bounds;
            [_window addSubview:dim];
        }
    }
    dim.hidden = NO;
    _window.hidden = NO;
}
- (void)hideDimView {
    _dimView.hidden = YES;
    _window.hidden = YES;
}

- (void)dim {
    if (_dimmed) return;
    _dimmed = YES;
    _dimmedAt = self.clock();
    [self showDimView];
    self.capSender(YES);
    AKLog(@"AFK saver: on after %ld min with no input (screen dimmed, %ld fps; the game stays connected)",
          (long)_minutes, (long)AKFrameLimitIdleRate);
}
- (void)wake:(NSString *)why {
    if (!_dimmed) return;
    _dimmed = NO;
    [self hideDimView];
    self.capSender(NO);
    [self noteInput];
    AKLog(@"AFK saver: off (%@) after %.0f s dimmed", why, self.clock() - _dimmedAt);
    [self schedule];
}

#pragma mark The game's saver

static AKIdleSaver *s_shared;
+ (instancetype)shared { return s_shared; }

static void (*originalSendEvent)(id, SEL, UIEvent *);
static void AKIdleSendEvent(id application, SEL selector, UIEvent *event) {
    if (s_shared && [s_shared handleEvent:event]) return;
    originalSendEvent(application, selector, event);
}

+ (void)installForGame {
    UIApplication *application = UIApplication.sharedApplication;
    if (!application || s_shared) return;
    s_shared = [AKIdleSaver new];
    s_shared.appActive = application.applicationState == UIApplicationStateActive;
    if (s_shared.minutes <= 0) {
        AKLog(@"AFK saver: off (the launcher's row)");
    } else {
        // Every event the application dispatches passes here first: the one place a waking touch can be held back
        // from both the game's view and the app's own controls.
        Class cls = object_getClass(application);
        Method method = class_getInstanceMethod(cls, @selector(sendEvent:));
        originalSendEvent = (void *)method_getImplementation(method);
        class_replaceMethod(cls, @selector(sendEvent:), (IMP)AKIdleSendEvent, method_getTypeEncoding(method));
        AKLog(@"AFK saver: dims after %ld min with no input", (long)s_shared.minutes);
    }
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
        usingBlock:^(__unused NSNotification *note) { s_shared.appActive = YES; }];
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
        usingBlock:^(__unused NSNotification *note) { s_shared.appActive = NO; }];
    [s_shared begin];
}
@end

// The guest loads this adapter when the game starts, so its load is the session's start. The application object is
// the launcher's, already running; UIKit is touched on the main queue.
__attribute__((constructor)) static void AKIdleSaverLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [AKIdleSaver installForGame]; });
}
