#import "TouchWorldSignal.h"
#import "AKSupport.h"

const NSTimeInterval AKTouchPulseMaxSeconds = 0.35;
const NSTimeInterval AKTouchPulseGroupSeconds = 0.6;
const NSTimeInterval AKTouchPasswordSeconds = 0.5;
const NSTimeInterval AKTouchPasswordInWorldSeconds = 1.5;

@implementation AKTouchWorldSignal {
    AKTouchWorldState _state;
    BOOL _on;               // secure input is on now
    BOOL _longHandled;      // this "on" has already been taken for a password box
    BOOL _onInWorld;        // this "on" began while the player was in the world, a window open or not (it needs
                            // longer to be a box)
    NSTimeInterval _onAt;
    NSUInteger _pulses;     // pulses in the group still open
    NSTimeInterval _lastOff;
    NSTimeInterval (^_clock)(void);
}
@synthesize state = _state, clock = _clock;

- (instancetype)init {
    if ((self = [super init])) self.clock = nil;
    return self;
}
- (void)setClock:(NSTimeInterval (^)(void))clock {
    _clock = clock ?: ^NSTimeInterval { return NSProcessInfo.processInfo.systemUptime; };
}

- (BOOL)inWorld { return _state == AKTouchWorldIn; }
- (void)setState:(AKTouchWorldState)state {
    if (_state == state) return;
    _state = state;
    AKLog(@"touch world: %@", state == AKTouchWorldIn ? @"in the world (TouchPlay's buttons are live)"
                             : state == AKTouchWorldWindow ? @"a window is open (auto-run kept)"
                             : state == AKTouchWorldSheet ? @"a TouchPlay sheet is open (its chat strip is live)" : @"not in the world (plain touches)");
    if (self.changed) self.changed(state);
}
/// One entered, three is a game window, two is a sheet only with sheet=2; four or more left.
static AKTouchWorldState AKTouchWorldStateForPulses(NSUInteger pulses, BOOL sheetPulses) {
    if (pulses == 1) return AKTouchWorldIn;
    if (pulses == 3) return AKTouchWorldWindow;
    if (pulses == 2 && sheetPulses) return AKTouchWorldSheet;
    return AKTouchWorldOut;
}

/// Asks for a `tick` once the clock has run `delay` seconds (and a hair more, so the edge is behind it). Idle
/// ticks change nothing, so a test's own clock and the real timer never disagree about anything that matters.
- (void)tickAfter:(NSTimeInterval)delay {
    __weak AKTouchWorldSignal *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay + 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf tick]; });
}

/// How long this "on" has to last before it is a password box: 0.5 s outside the world, more than 1.5 s inside it
/// (a loading screen can stretch the add-on's pulse well past 0.5 s).
- (NSTimeInterval)boxSeconds { return _onInWorld ? AKTouchPasswordInWorldSeconds : AKTouchPasswordSeconds; }

- (void)tick {
    NSTimeInterval now = self.clock();
    if (_on) {
        // Secure input has been on for longer than any pulse (and, in the world, than a stretched one): the password box.
        if (!_longHandled && now - _onAt > [self boxSeconds]) {
            _longHandled = YES;
            _pulses = 0;
            [self setState:AKTouchWorldOut];
        }
        return;
    }
    // A group with nothing more coming: one pulse is "entered", three "a window is open", others "left".
    if (_pulses > 0 && now - _lastOff >= AKTouchPulseGroupSeconds) {
        NSUInteger pulses = _pulses;
        _pulses = 0;
        [self setState:AKTouchWorldStateForPulses(pulses, self.sheetPulses)];
    }
}

- (void)secureInputChanged:(BOOL)enabled {
    [self tick];    // whatever has run out is settled first, so an old group never swallows a new pulse
    NSTimeInterval now = self.clock();
    if (enabled) {
        if (_on) return;
        _on = YES; _onAt = now; _longHandled = NO; _onInWorld = _state != AKTouchWorldOut;
        [self tickAfter:[self boxSeconds]];
        return;
    }
    if (!_on) return;
    _on = NO;
    if (_longHandled) return;           // the password box ended; the world was already left
    if (now - _onAt < AKTouchPulseMaxSeconds) {
        _pulses++;
        _lastOff = now;
        [self tickAfter:AKTouchPulseGroupSeconds];
        return;
    }
    // In the world, neither a pulse nor longer than a box needs: a stretched pulse or a flash of a field, not the
    // password box. It is ignored - the player is still in the world and it starts no group.
    if (_onInWorld && now - _onAt <= [self boxSeconds]) return;
    // Neither a pulse nor a long box: still a box, not the add-on.
    _pulses = 0;
    [self setState:AKTouchWorldOut];
}
@end
