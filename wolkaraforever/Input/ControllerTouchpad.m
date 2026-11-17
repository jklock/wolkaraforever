#import "ControllerTouchpad.h"
#include <math.h>

NSString *const AKControllerTouchpadPointerDefaultsKey = @"WolkaraForeverControllerTouchpadPointer";
NSString *const AKControllerTouchpadSpeedDefaultsKey = @"WolkaraForeverControllerTouchpadSpeed";
NSNotificationName const AKControllerTouchpadPointerNotification = @"AKControllerTouchpadPointer";
NSString *const AKControllerTouchpadFingersKey = @"fingers";
NSString *const AKControllerTouchpadXKey = @"x";
NSString *const AKControllerTouchpadYKey = @"y";
NSString *const AKControllerTouchpadTimeKey = @"time";
NSString *const AKControllerTouchpadClickKey = @"click";
NSString *const AKControllerTouchpadResetKey = @"reset";

// Points per unit of Game Controller's -1...1 range, horizontally. At Normal a full sweep across
// the pad (two units) moves the pointer 800 points: most of an iPad's width, all of an iPhone's.
static double AKControllerTouchpadScale(AKControllerTouchpadSpeed speed) {
    switch (speed) {
        case AKControllerTouchpadSpeedSlow: return 240;
        case AKControllerTouchpadSpeedFast: return 640;
        case AKControllerTouchpadSpeedNormal: break;
    }
    return 400;
}
// Height over width of the pad's surface; see the header.
static const double AKControllerTouchpadAspect = 0.5;

CGPoint AKControllerTouchpadPoint(double x, double y, AKControllerTouchpadSpeed speed) {
    double scale = AKControllerTouchpadScale(speed);
    if (!isfinite(x) || !isfinite(y)) return CGPointMake(NAN, NAN);
    return CGPointMake(x * scale, -y * scale * AKControllerTouchpadAspect);
}

static AKControllerTouchpadSpeed AKControllerTouchpadClampSpeed(NSInteger value) {
    return value < AKControllerTouchpadSpeedSlow || value > AKControllerTouchpadSpeedFast
        ? AKControllerTouchpadSpeedNormal : (AKControllerTouchpadSpeed)value;
}

@implementation AKControllerTouchpadRelay {
    // Guarded by @synchronized(self): written from GameController's threads, read on main.
    BOOL _down[2];
    double _x[2], _y[2];
    BOOL _pending;
    // Which batch of touch reports a pending delivery belongs to. A click closes the batch: the
    // movement before it is delivered with it, and anything after it starts a new one, so a
    // finger lifted after a click can never be delivered ahead of that click.
    NSUInteger _generation;
    BOOL _enabled;
    AKControllerTouchpadSpeed _speed;
    NSUInteger _delivered, _coalesced;
}

+ (instancetype)shared {
    static AKControllerTouchpadRelay *relay;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ relay = [AKControllerTouchpadRelay new]; });
    return relay;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _enabled = [defaults boolForKey:AKControllerTouchpadPointerDefaultsKey];
        NSNumber *speed = [defaults objectForKey:AKControllerTouchpadSpeedDefaultsKey];
        _speed = [speed isKindOfClass:NSNumber.class] ? AKControllerTouchpadClampSpeed(speed.integerValue)
                                                      : AKControllerTouchpadSpeedNormal;
    }
    return self;
}

- (BOOL)enabled { @synchronized (self) { return _enabled; } }
- (void)setEnabled:(BOOL)enabled {
    BOOL was;
    @synchronized (self) { was = _enabled; _enabled = enabled; }
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:AKControllerTouchpadPointerDefaultsKey];
    // A finger or a click still held when the switch goes off must not stay held in the game.
    if (was && !enabled) [self deliverReset];
}

- (AKControllerTouchpadSpeed)speed { @synchronized (self) { return _speed; } }
- (void)setSpeed:(AKControllerTouchpadSpeed)speed {
    speed = AKControllerTouchpadClampSpeed(speed);
    @synchronized (self) { _speed = speed; }
    [NSUserDefaults.standardUserDefaults setInteger:speed forKey:AKControllerTouchpadSpeedDefaultsKey];
}

- (NSUInteger)deliveredCount { @synchronized (self) { return _delivered; } }
- (NSUInteger)coalescedCount { @synchronized (self) { return _coalesced; } }
- (void)resetCounters { @synchronized (self) { _delivered = 0; _coalesced = 0; } }

- (void)touch:(NSUInteger)index down:(BOOL)down x:(double)x y:(double)y {
    if (index > 1) return;
    BOOL schedule;
    NSUInteger generation;
    @synchronized (self) {
        if (!_enabled) return;
        _down[index] = down;
        if (isfinite(x) && isfinite(y)) { _x[index] = x; _y[index] = y; }
        schedule = !_pending;
        if (schedule) _pending = YES; else _coalesced += 1;
        generation = _generation;
    }
    if (!schedule) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self deliverTouchesOf:generation]; });
}

// Under the lock: the number of fingers down and where their centre is, in points.
- (NSDictionary *)touchSnapshot {
    unsigned fingers = 0;
    double x = 0, y = 0;
    for (unsigned index = 0; index < 2; index++) {
        if (!_down[index]) continue;
        x += _x[index]; y += _y[index]; fingers++;
    }
    if (fingers) { x /= fingers; y /= fingers; }
    CGPoint point = AKControllerTouchpadPoint(x, y, _speed);
    return @{AKControllerTouchpadFingersKey: @(fingers),
             AKControllerTouchpadXKey: @(point.x), AKControllerTouchpadYKey: @(point.y)};
}

- (void)post:(NSDictionary *)info {
    if (info[AKControllerTouchpadFingersKey]) {
        NSMutableDictionary *timed = [info mutableCopy];
        timed[AKControllerTouchpadTimeKey] = @(NSProcessInfo.processInfo.systemUptime);
        info = timed;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:AKControllerTouchpadPointerNotification
                                                      object:self userInfo:info];
}

// Main queue. The latest state, once - unless a click already delivered this batch.
- (void)deliverTouchesOf:(NSUInteger)generation {
    NSDictionary *info;
    @synchronized (self) {
        if (generation != _generation) return;
        _pending = NO;
        if (!_enabled) return;
        info = [self touchSnapshot];
        _delivered += 1;
    }
    [self post:info];
}

- (void)click:(BOOL)pressed {
    NSDictionary *movement = nil;
    @synchronized (self) {
        if (!_enabled) return;
        // Close the batch here, on the reporting thread, so the state the click is measured
        // against is the state when it happened.
        if (_pending) { movement = [self touchSnapshot]; _pending = NO; }
        _generation += 1;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self) {
            if (!self->_enabled) return;
            self->_delivered += movement ? 2 : 1;
        }
        if (movement) [self post:movement];
        [self post:@{AKControllerTouchpadClickKey: @(pressed)}];
    });
}

- (void)reset {
    @synchronized (self) { if (!_enabled) return; }
    [self deliverReset];
}

- (void)deliverReset {
    @synchronized (self) {
        // Nothing queued before the reset is worth delivering after it: every finger is lifted.
        _down[0] = _down[1] = NO;
        _pending = NO;
        _generation += 1;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (self) { self->_delivered += 1; }
        [self post:@{AKControllerTouchpadResetKey: @YES}];
    });
}

@end
