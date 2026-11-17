// The AFK saver (16 Nov 2026): after the row's minutes with no input during a game the screen dims and frames drop to
// 10 a second; the next touch wakes it and is not passed on. A bare UIKit process on a fixture clock: events are made
// here and handed to the saver as the application would, and what it sent the frame pacer is recorded.
//
//   test_idle_saver
#import <UIKit/UIKit.h>
#include <unistd.h>
#import "IdleSaver.h"
#import "BatterySettings.h"
#import "AKHostLocalization.h"

static int checks = 0, failures = 0;
static FILE *gReport;
#define CHECK(condition, ...) do { checks++; if (!(condition)) { failures++; \
    fprintf(gReport, "FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString alloc] initWithFormat:@__VA_ARGS__].UTF8String); } } while (0)

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

// Events as the application has them.
@interface FixtureTouch : UITouch
@property UITouchPhase fixturePhase;
@end
@implementation FixtureTouch
- (UITouchPhase)phase { return self.fixturePhase; }
- (UITouchType)type { return UITouchTypeDirect; }
@end
@interface FixtureTouchEvent : UIEvent
@property NSSet<UITouch *> *fixtureTouches;
@end
@implementation FixtureTouchEvent
- (UIEventType)type { return UIEventTypeTouches; }
- (NSSet<UITouch *> *)allTouches { return self.fixtureTouches; }
@end
@interface FixturePress : UIPress
@property UIPressPhase fixturePhase;
@end
@implementation FixturePress
- (UIPressPhase)phase { return self.fixturePhase; }
@end
@interface FixturePressEvent : UIPressesEvent
@property NSSet<UIPress *> *fixturePresses;
@end
@implementation FixturePressEvent
- (UIEventType)type { return UIEventTypePresses; }
- (NSSet<UIPress *> *)allPresses { return self.fixturePresses; }
@end
@interface FixtureHoverEvent : UIEvent
@end
@implementation FixtureHoverEvent
- (UIEventType)type { return UIEventTypeHover; }
- (NSSet<UITouch *> *)allTouches { return [NSSet set]; }
@end

/// A saver on a clock the test moves, a controller stamp the test sets, and what reached the frame pacer.
@interface Rig : NSObject
@property AKIdleSaver *saver;
@property NSTimeInterval now;
@property double stamp;
@property NSMutableArray<NSNumber *> *caps;
@end
@implementation Rig
- (instancetype)initWithMinutes:(NSInteger)minutes {
    if ((self = [super init])) {
        _saver = [AKIdleSaver new];
        _caps = [NSMutableArray array];
        _now = 1000;
        __weak Rig *weak = self;
        _saver.clock = ^NSTimeInterval { return weak.now; };
        _saver.controllerStamp = ^double { return weak.stamp; };
        _saver.capSender = ^(BOOL idle) { [weak.caps addObject:@(idle)]; };
        _saver.minutes = minutes;
        _saver.appActive = YES;
        [_saver begin];
    }
    return self;
}
- (void)advance:(NSTimeInterval)seconds { _now += seconds; [_saver tick]; }
- (BOOL)touch:(FixtureTouch *)t phase:(UITouchPhase)phase {
    t.fixturePhase = phase;
    FixtureTouchEvent *event = [FixtureTouchEvent new]; event.fixtureTouches = [NSSet setWithObject:t];
    return [_saver handleEvent:event];
}
- (BOOL)touches:(NSArray<FixtureTouch *> *)touches {
    FixtureTouchEvent *event = [FixtureTouchEvent new]; event.fixtureTouches = [NSSet setWithArray:touches];
    return [_saver handleEvent:event];
}
/// A whole tap: down and up. YES if any part of it was held back.
- (BOOL)tap {
    FixtureTouch *t = [FixtureTouch new];
    BOOL down = [self touch:t phase:UITouchPhaseBegan];
    BOOL up = [self touch:t phase:UITouchPhaseEnded];
    return down || up;
}
- (BOOL)press:(FixturePress *)p phase:(UIPressPhase)phase {
    p.fixturePhase = phase;
    FixturePressEvent *event = [FixturePressEvent new]; event.fixturePresses = [NSSet setWithObject:p];
    return [_saver handleEvent:event];
}
/// Five minutes and one second with nothing: dimmed.
- (void)goIdle { [self advance:_saver.minutes * 60 + 1]; }
@end

static void dims_after_the_minutes(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    NewLog();
    [rig advance:299];
    CHECK(!rig.saver.dimmed && rig.caps.count == 0, "4:59 with nothing: awake");
    [rig advance:1];
    CHECK(rig.saver.dimmed, "5:00: dimmed");
    CHECK([rig.caps isEqual:@[@YES]], "10 frames a second asked for: %@", rig.caps);
    UIView *dim = rig.saver.dimView;
    CGFloat white = 1, alpha = 0;
    [dim.backgroundColor getWhite:&white alpha:&alpha];
    CHECK(!dim.hidden && white < 0.01 && fabs(alpha - 0.7) < 0.01, "a 70%% black layer: hidden %d white %.2f alpha %.2f", dim.hidden, white, alpha);
    CHECK(!dim.userInteractionEnabled, "the layer takes no touch itself");
    UILabel *label = nil;
    for (UIView *view in dim.subviews) if ([view isKindOfClass:UILabel.class]) label = (UILabel *)view;
    CHECK(label && [label.text isEqual:AKHostLocalized(@"touch.afk.wake")] && ![label.text isEqual:@"touch.afk.wake"], "says how to wake it: %@", label.text);
    NSString *log = NewLog();
    CHECK([log containsString:@"AFK saver: on after 5 min with no input"], "logged: %@", log);
    [rig advance:600];
    CHECK(rig.saver.dimmed && rig.caps.count == 1, "stays dimmed, asked once");
}

static void input_puts_it_off(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    [rig advance:200];
    CHECK(![rig tap], "an awake tap goes to the game");
    [rig advance:200];
    CHECK(!rig.saver.dimmed, "400 s in, 200 s after the tap: awake");
    [rig advance:101];
    CHECK(rig.saver.dimmed, "5 min after the tap: dimmed");
    rig = [[Rig alloc] initWithMinutes:2];
    [rig advance:100];
    FixturePress *key = [FixturePress new];
    CHECK(![rig press:key phase:UIPressPhaseBegan] && ![rig press:key phase:UIPressPhaseEnded], "an awake key goes to the game");
    [rig advance:100];
    CHECK(!rig.saver.dimmed, "a key counts");
    [rig advance:21];
    CHECK(rig.saver.dimmed, "2 min after the key: dimmed");
    rig = [[Rig alloc] initWithMinutes:10];
    [rig advance:500];
    CHECK(![rig.saver handleEvent:[FixtureHoverEvent new]], "an awake pointer move goes through");
    [rig advance:500];
    CHECK(!rig.saver.dimmed, "the pointer counts");
    [rig advance:101];
    CHECK(rig.saver.dimmed, "10 min after it: dimmed");
}

static void the_first_touch_only_wakes(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    [rig goIdle];
    NewLog();
    FixtureTouch *finger = [FixtureTouch new];
    CHECK([rig touch:finger phase:UITouchPhaseBegan], "the waking touch is held back");
    CHECK(!rig.saver.dimmed && rig.saver.dimView.hidden, "awake at once, the layer gone");
    CHECK([rig.caps isEqual:(@[@YES, @NO])], "frames back: %@", rig.caps);
    NSString *log = NewLog();
    CHECK([log containsString:@"AFK saver: off (a touch)"], "logged: %@", log);
    CHECK([rig touch:finger phase:UITouchPhaseMoved], "its move is held back too");
    // A second finger while the waking one is still down is part of the same wake.
    FixtureTouch *second = [FixtureTouch new];
    second.fixturePhase = UITouchPhaseBegan; finger.fixturePhase = UITouchPhaseStationary;
    CHECK([rig touches:(@[finger, second])], "a second finger during the wake is held back");
    second.fixturePhase = UITouchPhaseEnded;
    CHECK([rig touches:(@[finger, second])], "its lift too");
    CHECK([rig touch:finger phase:UITouchPhaseEnded], "the waking lift is held back");
    CHECK(![rig tap], "the next touch is the game's");
    CHECK(!rig.saver.dimmed, "still awake");
    // ...and the count starts again from the wake.
    [rig advance:299];
    CHECK(!rig.saver.dimmed, "awake for the minutes again");
    [rig advance:2];
    CHECK(rig.saver.dimmed, "then dims again");
}

static void a_key_or_the_pointer_wakes(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    [rig goIdle];
    NewLog();
    FixturePress *key = [FixturePress new];
    CHECK([rig press:key phase:UIPressPhaseBegan], "the waking key is held back");
    CHECK(!rig.saver.dimmed, "awake");
    CHECK([NewLog() containsString:@"AFK saver: off (a key)"], "logged");
    CHECK([rig press:key phase:UIPressPhaseEnded], "and its release");
    FixturePress *next = [FixturePress new];
    CHECK(![rig press:next phase:UIPressPhaseBegan] && ![rig press:next phase:UIPressPhaseEnded], "the next key is the game's");
    [rig goIdle];
    CHECK(rig.saver.dimmed, "dimmed again");
    CHECK([rig.saver handleEvent:[FixtureHoverEvent new]], "a pointer move wakes and is held back");
    CHECK(!rig.saver.dimmed && [NewLog() containsString:@"AFK saver: off (the pointer)"], "awake");
}

static void a_controller_puts_it_off_and_wakes_it(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    [rig advance:200];
    rig.stamp = 1;     // the controller reported a button
    // The saver looks at the controllers when its timer fires (no event reaches it from them): seen at 1400, the
    // minutes count from there.
    [rig advance:200];
    CHECK(!rig.saver.dimmed, "a controller counts as input");
    [rig advance:299];
    CHECK(!rig.saver.dimmed, "quiet for less than the minutes since it was seen (at %.0f)", rig.now);
    [rig advance:2];
    CHECK(rig.saver.dimmed, "then dimmed (at %.0f)", rig.now);
    NewLog();
    rig.stamp = 2;
    [rig advance:0.5];
    CHECK(!rig.saver.dimmed && [rig.caps.lastObject isEqual:@NO], "a controller wakes it (its input is the game's)");
    CHECK([NewLog() containsString:@"AFK saver: off (a controller)"], "logged");
}

static void never_while_a_finger_or_key_is_down(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    FixtureTouch *held = [FixtureTouch new];
    CHECK(![rig touch:held phase:UITouchPhaseBegan], "a finger goes down");
    [rig advance:900];
    CHECK(!rig.saver.dimmed, "15 min with a finger resting: awake");
    CHECK(![rig touch:held phase:UITouchPhaseEnded], "its lift is the game's");
    [rig advance:299];
    CHECK(!rig.saver.dimmed, "awake until the minutes from the lift");
    [rig advance:2];
    CHECK(rig.saver.dimmed, "then dimmed");
    rig = [[Rig alloc] initWithMinutes:5];
    FixturePress *key = [FixturePress new];
    [rig press:key phase:UIPressPhaseBegan];
    [rig advance:900];
    CHECK(!rig.saver.dimmed, "a key held down: awake (its release would be lost)");
    CHECK(![rig press:key phase:UIPressPhaseEnded], "the release is the game's");
    [rig advance:301];
    CHECK(rig.saver.dimmed, "then dimmed");
    // A touch the system cancelled is up too.
    rig = [[Rig alloc] initWithMinutes:5];
    FixtureTouch *cancelled = [FixtureTouch new];
    [rig touch:cancelled phase:UITouchPhaseBegan];
    [rig touch:cancelled phase:UITouchPhaseCancelled];
    [rig advance:301];
    CHECK(rig.saver.dimmed, "a cancelled touch is not held");
}

static void off_and_the_rows_choices(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:0];
    [rig advance:36000];
    CHECK(!rig.saver.dimmed && rig.caps.count == 0, "Off: never dims");
    CHECK(![rig tap], "and touches are the game's");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:AKAFKSaverDefaultsKey];
    CHECK([AKIdleSaver new].minutes == 5, "no row choice: 5 min");
    for (NSNumber *minutes in AKAFKSaverChoices()) {
        [defaults setInteger:minutes.integerValue forKey:AKAFKSaverDefaultsKey];
        CHECK([AKIdleSaver new].minutes == minutes.integerValue, "the row's %@", minutes);
    }
    [defaults removeObjectForKey:AKAFKSaverDefaultsKey];
}

static void the_app_away(void) {
    Rig *rig = [[Rig alloc] initWithMinutes:5];
    [rig advance:100];
    rig.saver.appActive = NO;
    [rig advance:3600];
    CHECK(!rig.saver.dimmed, "away for an hour: nothing dims");
    rig.saver.appActive = YES;
    [rig advance:299];
    CHECK(!rig.saver.dimmed, "back: the minutes count from the return");
    [rig advance:2];
    CHECK(rig.saver.dimmed, "then dims");
    NewLog();
    rig.saver.appActive = NO;
    CHECK(rig.saver.dimmed, "going away leaves it as it is");
    rig.saver.appActive = YES;
    CHECK(!rig.saver.dimmed && [rig.caps.lastObject isEqual:@NO], "coming back wakes it");
    CHECK([NewLog() containsString:@"AFK saver: off (the app came back)"], "logged");
    CHECK(![rig tap], "and the first touch after is the game's");
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        gReport = fdopen(dup(STDOUT_FILENO), "w");
        setvbuf(gReport, NULL, _IONBF, 0);
        gLogPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"idle-saver-%d.log", getpid()]];
        if (!freopen(gLogPath.fileSystemRepresentation, "w", stderr)) { fprintf(gReport, "cannot capture stderr\n"); return 2; }
        setvbuf(stderr, NULL, _IONBF, 0);
        void (*tests[])(void) = {dims_after_the_minutes, input_puts_it_off, the_first_touch_only_wakes, a_key_or_the_pointer_wakes,
            a_controller_puts_it_off_and_wakes_it, never_while_a_finger_or_key_is_down, off_and_the_rows_choices, the_app_away};
        const char *names[] = {"dims_after_the_minutes", "input_puts_it_off", "the_first_touch_only_wakes", "a_key_or_the_pointer_wakes",
            "a_controller_puts_it_off_and_wakes_it", "never_while_a_finger_or_key_is_down", "off_and_the_rows_choices", "the_app_away"};
        for (size_t i = 0; i < sizeof tests / sizeof *tests; i++) {
            int before = failures;
            tests[i]();
            fprintf(gReport, "%s %s\n", failures == before ? "PASS" : "FAIL", names[i]);
        }
        fprintf(gReport, "IDLE_SAVER_%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
        return failures ? 1 : 0;
    }
}
