#import "BatterySaverIdle.h"
#import <QuartzCore/QuartzCore.h>

// One second is fine: the shortest timeout is two minutes, and a session that appears to
// dim "about when I stopped" is exactly what this option promises. A display link here
// would wake the main thread 60 times a second for a decision that changes twice a session.
static const NSTimeInterval AKBatterySaverTickSeconds = 1.0;
// Dark enough that an OLED panel stops showing the game, light enough that a person can
// still see where they are. Never zero: the display is not switched off, because that is
// not this option's to do.
static const CGFloat AKBatterySaverDimAlpha = 0.62;

@implementation AKBatterySaverDimView
// It is a layer, not a control. Every touch goes to the game surface underneath, and the
// host decides whether that touch is delivered.
- (BOOL)pointInside:(CGPoint)point withEvent:(nullable UIEvent *)event {
    (void)point; (void)event;
    return NO;
}
@end

@interface AKBatterySaverIdle ()
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) AKBatterySaverDimView *dimView;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic) NSTimeInterval lastActivity;
@property (nonatomic) BOOL suspended;
@property (nonatomic, strong) NSMutableSet<NSString *> *heldReasons;
@property (nonatomic) BOOL reportedDimmed;   // reserved: the last value told to the app
@end

@implementation AKBatterySaverIdle {
    BOOL _dimmed;
}

- (instancetype)initWithHostView:(UIView *)hostView {
    if ((self = [super init])) {
        _hostView = hostView;
        _clock = ^{ return CACurrentMediaTime(); };
        _heldReasons = [NSMutableSet new];
        _timeoutMinutes = AKBatterySaverLaunchAFKMinutes();
        _dimView = [[AKBatterySaverDimView alloc] initWithFrame:hostView.bounds];
        _dimView.backgroundColor = UIColor.blackColor;
        _dimView.alpha = 0.0;
        _dimView.hidden = YES;
        _dimView.userInteractionEnabled = NO;
        // Above the game's own content layer and above the performance HUD (90000), below
        // the software pointer (100000) so the cursor stays findable.
        _dimView.layer.zPosition = 95000;
        _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [hostView addSubview:_dimView];
        _lastActivity = _clock();

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(appResigned:)
                       name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(appBackgrounded:)
                       name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(appActivated:)
                       name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(appResigned:)
                       name:UIApplicationWillTerminateNotification object:nil];
        [self restartTimerIfNeeded];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - The timeout

- (void)setTimeoutMinutes:(NSInteger)minutes {
    if (minutes != 2 && minutes != 5 && minutes != 10) minutes = 0;
    _timeoutMinutes = minutes;
    // Off means nothing can dim, so a session that is dimmed right now must come back.
    if (minutes == 0 && _dimmed) [self wake];
    _lastActivity = self.clock();
    [self restartTimerIfNeeded];
}

- (BOOL)isDimmed { return _dimmed; }

- (void)restartTimerIfNeeded {
    [_timer invalidate];
    _timer = nil;
    if (_timeoutMinutes == 0 || _suspended) return;
    __weak AKBatterySaverIdle *weakSelf = self;
    // Made unscheduled and then added once, to common modes: a timer scheduled in the
    // default mode alone stops while a menu is tracked or a sheet is dragged, and the
    // same timer added to two modes fires twice.
    _timer = [NSTimer timerWithTimeInterval:AKBatterySaverTickSeconds repeats:YES
                                      block:^(NSTimer *unused) {
        (void)unused;
        AKBatterySaverIdle *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf tickAt:strongSelf.clock()];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (BOOL)blocked {
    if (_suspended) return YES;
    if (_heldReasons.count) return YES;
    if (self.configurationActive && self.configurationActive()) return YES;
    UIApplication *application = UIApplication.sharedApplication;
    // Not frontmost, or a sheet of ours is up: not "idle", just not being played.
    if (application.applicationState != UIApplicationStateActive) return YES;
    return NO;
}

- (void)tickAt:(NSTimeInterval)now {
    if (_timeoutMinutes == 0) return;
    // Whatever the clock does, an input is still an input: a jump backwards must not dim.
    if (now < _lastActivity) _lastActivity = now;
    if ([self blocked]) {
        // Held input, the configuration UI, or the app being away: the countdown restarts
        // from now, so the moment the block lifts the user gets the whole timeout again.
        _lastActivity = now;
        return;
    }
    if (_dimmed) return;
    if (now - _lastActivity < _timeoutMinutes * 60.0) return;
    [self dim];
}

#pragma mark - Input

- (BOOL)input:(NSString *)source {
    (void)source;
    if (!NSThread.isMainThread) {
        __block BOOL woke = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ woke = [self input:source]; });
        return woke;
    }
    NSTimeInterval now = self.clock();
    _lastActivity = now;
    if (!_dimmed) return NO;
    // The first input after dimming only wakes. That is the whole point: the game does not
    // act on a hand reaching for the tablet.
    [self wake];
    return YES;
}

- (void)setHeld:(BOOL)held reason:(NSString *)reason {
    if (!reason.length) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setHeld:held reason:reason]; });
        return;
    }
    if (held) [_heldReasons addObject:reason];
    else [_heldReasons removeObject:reason];
    // Held input cannot dim, and releasing it starts the countdown again rather than
    // letting a session dim the instant a finger is lifted.
    _lastActivity = self.clock();
}

- (void)suspend {
    _suspended = YES;
    _lastActivity = self.clock();
    if (_dimmed) [self wake];
    [self restartTimerIfNeeded];
}

- (void)resume {
    if (!_suspended) return;
    _suspended = NO;
    _lastActivity = self.clock();
    [self restartTimerIfNeeded];
}

- (void)appResigned:(NSNotification *)note {
    (void)note;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self suspend]; }); return; }
    [self suspend];
}
- (void)appBackgrounded:(NSNotification *)note { (void)note; [self appResigned:note]; }
- (void)appActivated:(NSNotification *)note {
    (void)note;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self resume]; }); return; }
    [self resume];
}

- (void)layoutDimView {
    UIView *host = self.hostView;
    if (!host || !self.dimView) return;
    self.dimView.frame = host.bounds;
}

#pragma mark - The dim itself

- (void)dim {
    if (_dimmed) return;
    _dimmed = YES;
    _dimView.hidden = NO;
    [UIView animateWithDuration:0.45 animations:^{ self.dimView.alpha = AKBatterySaverDimAlpha; }];
    [self reportDimmed:YES];
}

- (void)wake {
    if (!_dimmed) return;
    _dimmed = NO;
    [UIView animateWithDuration:0.20 animations:^{ self.dimView.alpha = 0.0; }
                     completion:^(BOOL finished) { (void)finished; if (!self->_dimmed) self.dimView.hidden = YES; }];
    // Every wake also restarts the countdown, or a session would dim again one tick later.
    _lastActivity = self.clock();
    [self reportDimmed:NO];
}

- (void)reportDimmed:(BOOL)dimmed {
    _reportedDimmed = dimmed;
    // The AppKit host wakes itself; the app's controller path and the Metal adapter read
    // this to know that the cap in force is the dim's 10 FPS and nothing else.
    [NSNotificationCenter.defaultCenter postNotificationName:AKBatterySaverDimDidChangeNotification
                                                      object:self
                                                    userInfo:@{ AKBatterySaverDimmedKey: @(dimmed) }];
}

- (AKBatterySaverFramePolicy)framePolicy {
    return AKBatterySaverResolvedPolicy(_dimmed);
}

@end
