// The in-world gate (ruling A24): the TouchPlay add-on tells the app the player is in the world with secure-input
// pulses (one short pulse entering, two leaving, three a window open in the world - ruling A32), and the login screen's password box is secure input held for
// seconds. A fixture clock drives the recogniser; nothing here waits.
//
//   test_touch_world
#import <Foundation/Foundation.h>
#import "TouchWorldSignal.h"
#import "TouchTextBridge.h"

static int checks = 0, failures = 0;
#define CHECK(condition, ...) do { checks++; if (!(condition)) { failures++; \
    fprintf(gReport, "FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString alloc] initWithFormat:@__VA_ARGS__].UTF8String); } } while (0)
static FILE *gReport;

/// A recogniser on a clock the test moves, and what it announced.
@interface Rig : NSObject
@property AKTouchWorldSignal *signal;
@property NSTimeInterval now;
@property NSMutableArray<NSNumber *> *announced;   // each change's new state (AKTouchWorldState)
@end
@implementation Rig
- (instancetype)init {
    if ((self = [super init])) {
        _signal = [AKTouchWorldSignal new];
        _announced = [NSMutableArray array];
        __weak Rig *weak = self;
        _signal.clock = ^NSTimeInterval { return weak.now; };
        _signal.changed = ^(AKTouchWorldState state) { [weak.announced addObject:@(state)]; };
        _now = 1000;
    }
    return self;
}
/// Moves the clock and lets the recogniser settle (a timer does this on a device).
- (void)advance:(NSTimeInterval)seconds { _now += seconds; [_signal tick]; }
- (void)on { [_signal secureInputChanged:YES]; }
- (void)off { [_signal secureInputChanged:NO]; }
/// A pulse: on, `length` later off.
- (void)pulse:(NSTimeInterval)length { [self on]; [self advance:length]; [self off]; }
/// What the add-on sends entering the world.
- (void)entering { [self pulse:0.15]; [self advance:1.0]; }
/// What the add-on sends leaving: two pulses with a 0.15 s gap.
- (void)leaving { [self pulses:2]; }
/// What the add-on sends when a window opens in the world (ruling A32): three pulses.
- (void)windowOpens { [self pulses:3]; }
/// `count` pulses of 0.15 s with 0.15 s gaps, then the group settles.
- (void)pulses:(NSUInteger)count {
    for (NSUInteger i = 0; i < count; i++) { if (i) [self advance:0.15]; [self pulse:0.15]; }
    [self advance:1.0];
}
@end

static void game_start_is_not_in_the_world(void) {
    Rig *rig = [Rig new];
    CHECK(!rig.signal.inWorld, "a game start is out of the world");
    [rig advance:5];
    CHECK(!rig.signal.inWorld && rig.announced.count == 0, "and stays so with no signal");
}

static void single_pulse_enters_the_world(void) {
    Rig *rig = [Rig new];
    [rig pulse:0.15];
    // Not decided yet: a second pulse may be coming (that would be leaving).
    CHECK(!rig.signal.inWorld, "right after the pulse the group is still open");
    [rig advance:0.5];
    CHECK(!rig.signal.inWorld, "0.5 s after it: still open (the group window is 0.6 s)");
    [rig advance:0.15];
    CHECK(rig.signal.inWorld, "one pulse: entered the world");
    CHECK([rig.announced isEqualToArray:@[@(AKTouchWorldIn)]], "announced once: %@", rig.announced);
}

static void double_pulse_leaves_the_world(void) {
    Rig *rig = [Rig new];
    [rig entering];
    CHECK(rig.signal.inWorld, "in the world first");
    [rig.announced removeAllObjects];
    [rig leaving];
    CHECK(!rig.signal.inWorld, "two pulses: left the world");
    CHECK([rig.announced isEqualToArray:@[@(AKTouchWorldOut)]], "announced once: %@", rig.announced);
}

static void double_pulse_never_flashes_in_the_world(void) {
    // Out of the world, a double pulse is two pulses in one group: it must not be read as one entering.
    Rig *rig = [Rig new];
    [rig leaving];
    CHECK(!rig.signal.inWorld && rig.announced.count == 0, "never in the world, never announced: %@", rig.announced);
}

static void pulses_in_the_group_window_are_one_group(void) {
    Rig *rig = [Rig new];
    [rig entering];
    [rig.announced removeAllObjects];
    // The second pulse starts 0.55 s after the first ended: inside the 0.6 s window, so the two are one group.
    [rig pulse:0.2];
    [rig advance:0.55];
    [rig pulse:0.2];
    [rig advance:1];
    CHECK(!rig.signal.inWorld, "0.55 s apart: one group of two, left");
    // 0.65 s apart: two groups of one each, both entering.
    [rig pulse:0.2];
    [rig advance:0.65];
    CHECK(rig.signal.inWorld, "the first single resolved on its own (entered)");
    [rig pulse:0.2];
    [rig advance:1];
    CHECK(rig.signal.inWorld, "0.65 s apart: two singles, still in the world");
}

static void reload_while_in_the_world_stays(void) {
    Rig *rig = [Rig new];
    [rig entering];
    [rig.announced removeAllObjects];
    [rig entering];     // /reload: another single pulse
    CHECK(rig.signal.inWorld && rig.announced.count == 0, "still in, nothing announced: %@", rig.announced);
}

static void three_pulses_a_window_is_open(void) {
    // Ruling A32: three pulses are a window open while still in the world - not live, but not out of the world either.
    Rig *rig = [Rig new];
    [rig entering];
    [rig.announced removeAllObjects];
    [rig windowOpens];
    CHECK(!rig.signal.inWorld && rig.signal.state == AKTouchWorldWindow, "three pulses: a window is open (state %ld)", (long)rig.signal.state);
    CHECK([rig.announced isEqualToArray:@[@(AKTouchWorldWindow)]], "announced once: %@", rig.announced);
    // One pulse after it: back to the world.
    [rig entering];
    CHECK(rig.signal.inWorld && rig.signal.state == AKTouchWorldIn, "one pulse after the window: in the world");
    // Window again, then two: out of the world.
    [rig windowOpens];
    [rig leaving];
    CHECK(rig.signal.state == AKTouchWorldOut, "two pulses from the window state: out of the world");
    CHECK([rig.announced isEqualToArray:(@[@(AKTouchWorldWindow), @(AKTouchWorldIn), @(AKTouchWorldWindow), @(AKTouchWorldOut)])],
          "announced in order: %@", rig.announced);
    // A second window pulse group while one is open changes nothing.
    [rig entering]; [rig windowOpens];
    [rig.announced removeAllObjects];
    [rig windowOpens];
    CHECK(rig.signal.state == AKTouchWorldWindow && rig.announced.count == 0, "window again while open: nothing: %@", rig.announced);
}

static void four_or_more_pulses_leave(void) {
    // A recogniser group of 4 or more is no ruling's: the safe reading, out of the world.
    for (NSUInteger count = 4; count <= 6; count++) {
        Rig *rig = [Rig new];
        [rig entering];
        [rig pulses:count];
        CHECK(rig.signal.state == AKTouchWorldOut, "%lu pulses: out of the world (state %ld)", (unsigned long)count, (long)rig.signal.state);
        Rig *window = [Rig new];
        [window entering]; [window windowOpens];
        [window pulses:count];
        CHECK(window.signal.state == AKTouchWorldOut, "%lu pulses from the window state: out of the world", (unsigned long)count);
    }
}

static void window_state_is_still_the_world_for_a_password_box(void) {
    // With a window open the player is still in the world (ruling A27's 1.5 s): a stretched pulse or a field's flash is
    // ignored, only more than 1.5 s is a password box.
    Rig *rig = [Rig new];
    [rig entering]; [rig windowOpens];
    [rig.announced removeAllObjects];
    [rig pulse:0.9];
    [rig advance:1];
    CHECK(rig.signal.state == AKTouchWorldWindow && rig.announced.count == 0, "0.9 s on with a window open is ignored: %@", rig.announced);
    [rig on];
    [rig advance:1.6];
    CHECK(rig.signal.state == AKTouchWorldOut, "more than 1.5 s with a window open: a password box");
    [rig off];
}

static void long_secure_on_is_a_password_box(void) {
    // Out of the world (the login screen): longer than 0.5 s is a box.
    Rig *rig = [Rig new];
    [rig on];
    [rig advance:0.4];
    CHECK(!rig.signal.inWorld, "out of the world to begin with");
    [rig advance:0.15];
    CHECK(!rig.signal.inWorld && rig.announced.count == 0, "still out, nothing announced (it was never in): %@", rig.announced);
    [rig advance:3];
    [rig off];
    [rig advance:2];
    CHECK(!rig.signal.inWorld && rig.announced.count == 0, "its off is no pulse: still out: %@", rig.announced);
    // In the world, ruling A27: only more than 1.5 s is a box.
    [rig entering];
    [rig.announced removeAllObjects];
    [rig on];
    [rig advance:1.4];
    CHECK(rig.signal.inWorld, "in the world, 1.4 s on is not yet decided");
    [rig advance:0.2];
    CHECK(!rig.signal.inWorld, "in the world, on for more than 1.5 s: a password box, out of the world");
    CHECK([rig.announced isEqualToArray:@[@(AKTouchWorldOut)]], "announced: %@", rig.announced);
    [rig advance:3];
    [rig off];
    [rig advance:2];
    CHECK(!rig.signal.inWorld && rig.announced.count == 1, "its off is no pulse: still out, nothing more: %@", rig.announced);
}

static void long_secure_on_seen_only_at_its_off(void) {
    // No timer ran (the main thread was busy): the off itself says how long it was.
    Rig *rig = [Rig new];
    [rig entering];
    [rig on];
    rig.now += 2.0;
    [rig off];
    CHECK(!rig.signal.inWorld, "in the world, on for 2 s, seen only at its off: out of the world");
    [rig advance:2];
    CHECK(!rig.signal.inWorld, "and that off started no group");
}

static void in_between_is_a_box_out_of_the_world_and_nothing_in_it(void) {
    // Out of the world: longer than a pulse is not the add-on's, and it starts no group.
    Rig *rig = [Rig new];
    [rig pulse:0.4];
    [rig advance:1];
    CHECK(!rig.signal.inWorld && rig.announced.count == 0, "out of the world, 0.4 s on and off is no pulse: %@", rig.announced);
    // In the world, ruling A27: a secure input that is neither a pulse nor longer than 1.5 s (a pulse a loading screen
    // stretched, a game dialog's field flashing) is ignored: still in the world, nothing announced.
    [rig entering];
    [rig.announced removeAllObjects];
    for (NSNumber *length in @[@0.4, @0.5, @0.9, @1.5]) {
        [rig pulse:length.doubleValue];
        [rig advance:1];
        CHECK(rig.signal.inWorld && rig.announced.count == 0, "in the world, %.1f s on and off is ignored: %@", length.doubleValue, rig.announced);
    }
    // ...and it does not turn into a pulse of a group either: a real single pulse after it still enters, two still leave.
    [rig leaving];
    CHECK(!rig.signal.inWorld, "two pulses after them still leave");
}

static void box_then_login_then_pulse(void) {
    // The whole story: login screen, password box, character select, the world, leaving, the world again.
    Rig *rig = [Rig new];
    CHECK(!rig.signal.inWorld, "login screen");
    [rig on]; [rig advance:6]; [rig off]; [rig advance:1];
    CHECK(!rig.signal.inWorld, "password box");
    [rig entering];
    CHECK(rig.signal.inWorld, "entered");
    [rig leaving];
    CHECK(!rig.signal.inWorld, "left");
    [rig entering];
    CHECK(rig.signal.inWorld, "back");
    CHECK([rig.announced isEqualToArray:(@[@(AKTouchWorldIn), @(AKTouchWorldOut), @(AKTouchWorldIn)])], "announced in order: %@", rig.announced);
}

static void repeated_events_are_ignored(void) {
    Rig *rig = [Rig new];
    [rig off];                          // an off with nothing on
    [rig advance:1];
    CHECK(!rig.signal.inWorld, "a stray off is nothing");
    [rig on]; [rig advance:0.05]; [rig on]; [rig advance:0.1]; [rig off]; [rig off]; [rig advance:1];
    CHECK(rig.signal.inWorld, "a doubled on and off is still one pulse (counted from the first on)");
}

static void debounce_is_the_pulse_limit(void) {
    CHECK(AKTouchPasswordDebounceSeconds == AKTouchPulseMaxSeconds, "the password debounce %.2f is the pulse limit %.2f",
          AKTouchPasswordDebounceSeconds, AKTouchPulseMaxSeconds);
    CHECK(AKTouchPulseMaxSeconds == 0.35 && AKTouchPulseGroupSeconds == 0.6 && AKTouchPasswordSeconds == 0.5, "the ruling's numbers");
    // Ruling A27: in the world a secure input is a password box only after 1.5 s, for the signal and the keyboard alike.
    CHECK(AKTouchPasswordInWorldSeconds == 1.5 && AKTouchPasswordInWorldDebounceSeconds == AKTouchPasswordInWorldSeconds,
          "the in-world numbers: %.2f, %.2f", AKTouchPasswordInWorldSeconds, AKTouchPasswordInWorldDebounceSeconds);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        gReport = fdopen(dup(STDERR_FILENO), "w");
        setvbuf(gReport, NULL, _IONBF, 0);
        void (*tests[])(void) = {game_start_is_not_in_the_world, single_pulse_enters_the_world, double_pulse_leaves_the_world,
            double_pulse_never_flashes_in_the_world, pulses_in_the_group_window_are_one_group, reload_while_in_the_world_stays,
            three_pulses_a_window_is_open, four_or_more_pulses_leave, window_state_is_still_the_world_for_a_password_box, long_secure_on_is_a_password_box, long_secure_on_seen_only_at_its_off, in_between_is_a_box_out_of_the_world_and_nothing_in_it,
            box_then_login_then_pulse, repeated_events_are_ignored, debounce_is_the_pulse_limit};
        const char *names[] = {"game_start_is_not_in_the_world", "single_pulse_enters_the_world", "double_pulse_leaves_the_world",
            "double_pulse_never_flashes_in_the_world", "pulses_in_the_group_window_are_one_group", "reload_while_in_the_world_stays",
            "three_pulses_a_window_is_open", "four_or_more_pulses_leave", "window_state_is_still_the_world_for_a_password_box", "long_secure_on_is_a_password_box", "long_secure_on_seen_only_at_its_off", "in_between_is_a_box_out_of_the_world_and_nothing_in_it",
            "box_then_login_then_pulse", "repeated_events_are_ignored", "debounce_is_the_pulse_limit"};
        for (size_t i = 0; i < sizeof tests / sizeof *tests; i++) {
            int before = failures;
            tests[i]();
            printf("%s %s\n", failures == before ? "PASS" : "FAIL", names[i]);
        }
        printf("TOUCH_WORLD_%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
        return failures ? 1 : 0;
    }
}
