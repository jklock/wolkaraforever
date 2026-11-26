// TouchPlay's buttons played by the fingers (the input path, rules 8 and 2): a finger on an area lights it at
// once, sends the tap key at the lift, the hold key when it stays, the tap key once when it is dragged
// off, and Jump's key for as long as it is down. A recorder takes the keys, a fixture clock drives the
// hold, and the views are read straight from the view the areas draw in. No guest, no host view: the
// host's own wiring is checked in test_touch_controls_app.m.
//
//   test_touch_areas <fixtures folder>
//
// The contract is the iPad's own saved file (TouchPlay-v1.lua, 26 areas, hold 0.45 s).
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "InterfaceMode.h"
#import "TouchContract.h"
#import "TouchAreas.h"
#include <math.h>

static int checks = 0, failures = 0;
#define CHECK(condition, ...) do { checks++; if (!(condition)) { failures++; \
    fprintf(stderr, "FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString alloc] initWithFormat:@__VA_ARGS__].UTF8String); } } while (0)

static const NSUInteger kControl = 1 << 18, kOption = 1 << 19, kShift = 1 << 17;
static const NSUInteger kChord = (1 << 18) | (1 << 19) | (1 << 17);
// macOS key codes of the fixture's keys.
enum { kF1 = 122, kF2 = 120, kF3 = 99, kF4 = 118, kF8 = 100, kD = 2, kE = 14, kF = 3, kR = 15, kS = 1, kT = 17, kSix = 22 };

static NSString *gFixtures;
static NSString *Fixture(NSString *name) {
    return [NSString stringWithContentsOfFile:[gFixtures stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:NULL];
}
static AKTouchContract *FixtureContract(NSString *replace, NSString *with) {
    NSString *text = Fixture(@"TouchPlay-v1.lua");
    if (replace) text = [text stringByReplacingOccurrencesOfString:replace withString:with];
    return AKTouchContractParse(text);
}
static void SetMode(NSString *mode) {
    if (mode) [NSUserDefaults.standardUserDefaults setObject:mode forKey:AKInterfaceModeDefaultsKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:AKInterfaceModeDefaultsKey];
}

/// One rig per test: a 1366 x 1024 view (one layout unit = one point), the areas over it with the
/// fixture contract, a clock the test moves, and every key the areas sent, as "99v" (down) / "99^" (up).
@interface Rig : NSObject
@property UIView *view;
@property AKTouchAreas *areas;
@property NSTimeInterval now;
@property NSMutableArray<NSString *> *keys;
@property BOOL allChorded;   // every key carried control + option + shift
// The modifiers of each key, in order.
@property NSMutableArray<NSNumber *> *mods;
// Where the areas put the host's pointer: "move 640,560" (the cursor follows) / "click 640,560".
@property NSMutableArray<NSString *> *pointer;
@end
@implementation Rig
- (instancetype)initWithContract:(AKTouchContract *)contract {
    if ((self = [super init])) {
        _view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        _areas = [[AKTouchAreas alloc] initWithView:_view];
        _areas.contract = contract;
        _keys = [NSMutableArray array];
        _mods = [NSMutableArray array];
        _pointer = [NSMutableArray array];
        _allChorded = YES;
        __weak Rig *weakSelf = self;
        _areas.clock = ^NSTimeInterval { return weakSelf.now; };
        _areas.keySender = ^(uint16_t code, NSUInteger mods, BOOL down) {
            Rig *rig = weakSelf;
            [rig.keys addObject:[NSString stringWithFormat:@"%u%@", code, down ? @"v" : @"^"]];
            [rig.mods addObject:@(mods)];
            if (mods != kChord) rig.allChorded = NO;
        };
        _areas.pointerSender = ^(CGPoint p, BOOL click) {
            [weakSelf.pointer addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f", click ? @"click" : @"move", p.x, p.y]];
        };
    }
    return self;
}
- (CGRect)rect:(NSString *)name { return AKTouchAreaRect([self.areas.contract areaNamed:name], self.view.bounds.size); }
- (CGPoint)centre:(NSString *)name { CGRect r = [self rect:name]; return CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r)); }
- (void)at:(NSTimeInterval)time { self.now = time; [self.areas tick]; }
- (NSString *)sent { return [self.keys componentsJoinedByString:@" "]; }
- (NSString *)pointed { return [self.pointer componentsJoinedByString:@"; "]; }
@end

static Rig *NewRig(void) { return [[Rig alloc] initWithContract:FixtureContract(nil, nil)]; }
/// The iPad's contract with Dive on CTRL-ALT-SHIFT-T. Its own Dive is on S, a walk key (W, A, S, D), and
/// the host makes a chord on a walk key no key (the add-on's pool skips them from now on), so the press tests use T.
static Rig *NewDiveRig(void) {
    return [[Rig alloc] initWithContract:FixtureContract(@"dive,BR,478,232,56,56,,,CTRL-ALT-SHIFT-S", @"dive,BR,478,232,56,56,,,CTRL-ALT-SHIFT-T")];
}
/// The add-on's newer key set: Interact has a hold key, CTRL-ALT-SHIFT-R, bound to a hidden
/// "stop" button (stops spell targeting, only while targeting); Jump presses S and Dive T.
static Rig *NewStopRig(void) { return [[Rig alloc] initWithContract:AKTouchContractParse(Fixture(@"TouchPlay-v1-stopkey.lua"))]; }
static UITouch *Finger(void) { return [UITouch new]; }
static NSString *Tap(unsigned code) { return [NSString stringWithFormat:@"%uv %u^", code, code]; }

static BOOL Showing(UIView *view, UIView *root) {
    return view && view.superview == root && !view.hidden && view.alpha > 0.9;
}

// The press look (a device check, matching TouchPlay's own): a soft pale-gold edge glow - a thin pale-gold edge 2 pt outside
// the area, a faint wash of the same gold inside and a soft gold shadow round it - in the area's shape: the round areas
// (Jump, Dive, Interact, the minimap) a circle, the rest a rounded rectangle whose corner suits the size (a fifth of
// the short side, 6 to 14 pt). Lit the frame the finger lands.
static BOOL PaleGold(CGColorRef color, CGFloat alpha, CGFloat tolerance) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [[UIColor colorWithCGColor:color] getRed:&r green:&g blue:&b alpha:&a];
    return fabs(r - 1) < 0.01 && fabs(g - 0.9) < 0.01 && fabs(b - 0.55) < 0.01 && fabs(a - alpha) < tolerance;
}
static void rule8_glow_on_touch(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    CHECK([rig.areas touchBegan:finger at:[rig centre:@"spell2"]], "a finger on spell2 is the area's");
    AKTouchPressView *glow = [rig.areas pressViewForTouch:finger];
    CHECK(Showing(glow, rig.view), "the press glow is in the view the moment the finger lands (%@)", glow);
    CGRect expected = CGRectInset([rig rect:@"spell2"], -2, -2);
    CHECK(CGRectEqualToRect(glow.frame, expected), "the glow's edge is 2 pt outside the area: %@ vs %@",
          NSStringFromCGRect(glow.frame), NSStringFromCGRect(expected));
    CHECK([glow.areaName isEqualToString:@"spell2"], "glow for %@", glow.areaName);
    CHECK(PaleGold(glow.layer.borderColor, 0.9, 0.02) && glow.layer.borderWidth == 2, "a thin pale-gold edge (1, 0.9, 0.55)");
    CHECK(PaleGold(glow.layer.backgroundColor, 0.12, 0.05), "a faint pale-gold wash inside");
    CHECK(PaleGold(glow.layer.shadowColor, 1, 0.01) && glow.layer.shadowOpacity > 0.5 && glow.layer.shadowRadius >= 6 &&
          CGSizeEqualToSize(glow.layer.shadowOffset, CGSizeZero) && glow.layer.shadowPath, "a soft glow all round, in the shape");
    CGFloat side = MIN(glow.bounds.size.width, glow.bounds.size.height);
    CHECK(glow.layer.cornerRadius >= 6 && glow.layer.cornerRadius <= 14 && fabs(glow.layer.cornerRadius - MIN(14, MAX(6, round(side / 5)))) < 0.01,
          "a rounded rectangle, the corner suited to the size: %.1f for a %.0f pt side", glow.layer.cornerRadius, side);
    CHECK(!glow.userInteractionEnabled, "the glow never takes a touch");
    CHECK(rig.keys.count == 0, "no key yet: %@", rig.sent);
    CHECK([rig.areas ownsTouch:finger] && rig.areas.activeFingerCount == 1, "one finger held");
    Rig *other = NewRig();
    UITouch *jump = Finger();
    [other.areas touchBegan:jump at:[other centre:@"jump"]];
    AKTouchPressView *round = [other.areas pressViewForTouch:jump];
    CHECK(round && fabs(round.layer.cornerRadius - MIN(round.bounds.size.width, round.bounds.size.height) / 2) < 0.01, "a round area glows round");
    [other.areas touchEnded:jump at:[other centre:@"jump"]];
}

// The press outline only where the add-on says it draws something (a device check, a player: the empty quest list's area lit
// up gold for a tap the add-on ignored). With the contract's `outline=` list, an area left out of it takes the finger
// and sends its keys exactly as before - only the outline is not drawn. Without the list, every area is outlined.
static void outline_only_listed_areas(void) {
    Rig *rig = [[Rig alloc] initWithContract:FixtureContract(@"world=CTRL-ALT-SHIFT-F1;", @"world=CTRL-ALT-SHIFT-F1;outline=spell2,jump;")];
    CHECK(rig.areas.contract.outlineAreas.count == 2, "the fixture with an outline list");
    UITouch *quest = Finger();
    CHECK([rig.areas touchBegan:quest at:[rig centre:@"quest"]], "a finger on the quest list is still the area's");
    CHECK([rig.areas pressViewForTouch:quest] == nil, "no outline round an area the add-on did not list");
    BOOL drawn = NO;
    for (UIView *view in rig.view.subviews) if ([view isKindOfClass:AKTouchPressView.class]) drawn = YES;
    CHECK(!drawn, "nothing drawn in the view");
    CHECK([rig.areas touchEnded:quest at:[rig centre:@"quest"]], "the lift is the area's");
    AKTouchArea *area = [rig.areas.contract areaNamed:@"quest"];
    CHECK(area.tapKey.length > 0 && rig.keys.count == 2, "its tap key still goes, once, at the lift: %@", rig.sent);
    UITouch *spell = Finger();
    [rig.areas touchBegan:spell at:[rig centre:@"spell2"]];
    CHECK(Showing([rig.areas pressViewForTouch:spell], rig.view), "a listed area is outlined as before");
    [rig.areas touchEnded:spell at:[rig centre:@"spell2"]];
    CHECK(![rig.areas pressViewForTouch:spell], "and the outline goes with the finger");
    // The add-on before the list: every area, the quest list included, as before.
    Rig *old = NewRig();
    UITouch *again = Finger();
    [old.areas touchBegan:again at:[old centre:@"quest"]];
    CHECK(Showing([old.areas pressViewForTouch:again], old.view), "no list: the quest list's area is outlined as before");
    [old.areas touchEnded:again at:[old centre:@"quest"]];
}

static void rule8_tap_sends_on_lift(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
    [rig at:0.1];
    CHECK(rig.keys.count == 0, "nothing before the lift: %@", rig.sent);
    CHECK([rig.areas touchEnded:finger at:[rig centre:@"spell2"]], "the lift is the area's too");
    CHECK([rig.sent isEqualToString:Tap(kF3)], "ctrl+opt+shift F3 down, up, once, at lift: %@", rig.sent);
    CHECK(rig.allChorded, "with control, option and shift");
    CHECK(![rig.areas pressViewForTouch:finger] && rig.areas.activeFingerCount == 0, "the glow goes with the finger");
    // It fades out over about 120 ms from the lift (an opacity animation the render server runs; the view's own opacity
    // is 0 at once), then leaves the view.
    AKTouchPressView *fading = nil;
    for (UIView *view in rig.view.subviews) if ([view isKindOfClass:AKTouchPressView.class]) fading = (AKTouchPressView *)view;
    CABasicAnimation *fade = fading.letGoAnimation;
    CHECK(fading && fading.alpha < 0.01, "not lit after the lift");
    CHECK([fade isKindOfClass:CABasicAnimation.class] && [fade.keyPath isEqual:@"opacity"] && [fade.fromValue doubleValue] == 1 &&
          [fade.toValue doubleValue] == 0 && fabs(fade.duration - 0.12) < 0.001, "a 120 ms fade: %@", fade);
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    BOOL glowLeft = NO;
    for (UIView *view in rig.view.subviews) if ([view isKindOfClass:AKTouchPressView.class]) glowLeft = YES;
    CHECK(!glowLeft, "no glow left in the view after the fade");
    // Reduce Motion: no fade - the glow holds 120 ms, then drops.
    Rig *still = NewRig();
    still.areas.reduceMotion = ^BOOL { return YES; };
    UITouch *again = Finger();
    [still.areas touchBegan:again at:[still centre:@"spell2"]];
    [still.areas touchEnded:again at:[still centre:@"spell2"]];
    for (UIView *view in still.view.subviews) if ([view isKindOfClass:AKTouchPressView.class]) fading = (AKTouchPressView *)view;
    CABasicAnimation *hold = fading.letGoAnimation;
    CHECK([hold.fromValue doubleValue] == 1 && [hold.toValue doubleValue] == 1 && fabs(hold.duration - 0.12) < 0.001, "Reduce Motion: a hold, no fade: %@", hold);
    [rig at:2];
    CHECK([rig.sent isEqualToString:Tap(kF3)], "and nothing later: %@", rig.sent);
}

static void rule2_hold_sends_hold_key_only(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
    [rig at:0.3];
    CHECK(rig.keys.count == 0, "nothing at 0.3 s: %@", rig.sent);
    [rig at:0.449];
    CHECK(rig.keys.count == 0, "nothing just before the hold time: %@", rig.sent);
    [rig at:0.45];
    CHECK([rig.sent isEqualToString:Tap(kE)], "ctrl+opt+shift E down and up at 0.45 s: %@", rig.sent);
    CHECK(rig.allChorded, "with control, option and shift");
    [rig at:1.2];
    [rig.areas touchEnded:finger at:[rig centre:@"spell2"]];
    CHECK([rig.sent isEqualToString:Tap(kE)], "the lift sends nothing more: %@", rig.sent);
}

static void hold_ring_appears_after_0_15(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
    [rig at:0.1];
    AKTouchHoldRing *ring = [rig.areas holdRingForTouch:finger];
    CHECK(!Showing(ring, rig.view), "no ring at 0.1 s");
    [rig at:0.2];
    ring = [rig.areas holdRingForTouch:finger];
    CHECK(Showing(ring, rig.view), "a ring at 0.2 s");
    CHECK(ring.state == AKTouchHoldRingFilling, "filling");
    CHECK(fabs(ring.progress - 0.2 / 0.45) < 0.01, "filled by the time held: %.3f", ring.progress);
    CHECK(!ring.userInteractionEnabled, "the ring never takes a touch");
    // Mockup 10, "Filling": a small grey finger dot in the ring's centre.
    CALayer *dot = ring.fingerDot;
    CHECK(dot != nil && dot.superlayer == ring.layer && !dot.hidden, "the finger dot is drawn while filling");
    CHECK(fabs(CGRectGetMidX(dot.frame) - ring.bounds.size.width / 2) < 0.5 && fabs(CGRectGetMidY(dot.frame) - ring.bounds.size.height / 2) < 0.5,
          "in the ring's centre: %@", NSStringFromCGRect(dot.frame));
    CHECK(dot.frame.size.width > 8 && dot.frame.size.width < ring.bounds.size.width / 2, "small: %.1f", dot.frame.size.width);
    CGPoint centre = [rig centre:@"spell2"];
    CHECK(fabs(CGRectGetMidX(ring.frame) - centre.x) < 0.5 && fabs(CGRectGetMidY(ring.frame) - centre.y) < 0.5, "round the button");
    CHECK(ring.bounds.size.width >= [rig rect:@"spell2"].size.width, "outside the button: %@", NSStringFromCGRect(ring.frame));
    [rig at:0.45];
    CHECK(ring.progress >= 1 - 1e-9 && ring.state == AKTouchHoldRingDone, "full at 0.45 s, and it pops (state %ld)", (long)ring.state);
    CHECK(ring.fingerDot.hidden, "the dot goes when it pops (mockup: Done has none)");
    // Nothing about the ring for an area without a hold key.
    Rig *other = NewRig();
    UITouch *bags = Finger();
    [other.areas touchBegan:bags at:[other centre:@"bags"]];
    [other at:0.3];
    CHECK(!Showing([other.areas holdRingForTouch:bags], other.view), "Bags has no hold key, so no ring");
}

static void slide_off_cancels_hold_ring(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    CGRect area = [rig rect:@"spell2"];
    [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
    [rig at:0.2];
    AKTouchHoldRing *ring = [rig.areas holdRingForTouch:finger];
    CHECK(ring.state == AKTouchHoldRingFilling, "filling first");
    [rig.areas touchMoved:finger at:CGPointMake(CGRectGetMinX(area) - 30, CGRectGetMidY(area))];
    CHECK(ring.state == AKTouchHoldRingCancelled, "slid off: the ring is cancelled (state %ld)", (long)ring.state);
    CHECK(ring.transform.a < 1, "and shrinks (%.2f)", ring.transform.a);
    CHECK(ring.fingerDot.hidden, "the cross replaces the finger dot");
    [rig at:1];
    CHECK(![rig.sent containsString:@"14v"], "the hold key never goes out: %@", rig.sent);
}

static void drag_off_sends_key_once(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    CGRect area = [rig rect:@"spell2"];
    [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
    [rig at:0.1];
    // Inside the 10 pt allowance is still on the button.
    CHECK([rig.areas touchMoved:finger at:CGPointMake(CGRectGetMaxX(area) + 8, CGRectGetMidY(area))], "still the area's");
    CHECK(rig.keys.count == 0, "8 pt out is not off: %@", rig.sent);
    [rig at:0.2];
    CHECK([rig.areas touchMoved:finger at:CGPointMake(CGRectGetMaxX(area) + 30, CGRectGetMidY(area))], "the dragging finger stays the area's");
    CHECK([rig.sent isEqualToString:Tap(kF3)], "the tap key once, at the moment it leaves: %@", rig.sent);
    CHECK(rig.allChorded, "with control, option and shift");
    CHECK(![rig.areas pressViewForTouch:finger] || [rig.areas pressViewForTouch:finger].hidden, "the button is no longer lit");
    [rig.areas touchMoved:finger at:CGPointMake(CGRectGetMaxX(area) + 90, CGRectGetMidY(area) - 40)];
    [rig.areas touchMoved:finger at:[rig centre:@"spell2"]];
    [rig at:1.5];
    CHECK([rig.areas touchEnded:finger at:CGPointMake(500, 500)], "its lift is the area's");
    CHECK([rig.sent isEqualToString:Tap(kF3)], "nothing more: no hold, no second tap: %@", rig.sent);
    CHECK(rig.areas.activeFingerCount == 0, "and it is let go");
}

static void jump_press_and_release(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    CHECK([rig.areas touchBegan:finger at:[rig centre:@"jump"]], "Jump is an area");
    CHECK([rig.sent isEqualToString:@"15v"], "R down on begin: %@", rig.sent);
    [rig at:2];
    CHECK([rig.sent isEqualToString:@"15v"], "held, nothing else (no hold, no tap): %@", rig.sent);
    [rig.areas touchEnded:finger at:[rig centre:@"jump"]];
    CHECK([rig.sent isEqualToString:Tap(kR)], "R up on end: %@", rig.sent);
    CHECK(rig.allChorded, "with control, option and shift");

    Rig *cancelled = NewRig();
    UITouch *again = Finger();
    [cancelled.areas touchBegan:again at:[cancelled centre:@"jump"]];
    CHECK([cancelled.areas touchCancelled:again], "a cancelled finger is the area's");
    CHECK([cancelled.sent isEqualToString:Tap(kR)], "R up on cancel: %@", cancelled.sent);

    // Dragged off, Jump still holds until the lift: it has no tap key to send.
    Rig *dragged = NewRig();
    UITouch *thumb = Finger();
    [dragged.areas touchBegan:thumb at:[dragged centre:@"jump"]];
    [dragged.areas touchMoved:thumb at:CGPointMake([dragged centre:@"jump"].x - 120, [dragged centre:@"jump"].y)];
    CHECK([dragged.sent isEqualToString:@"15v"], "dragging off Jump sends nothing: %@", dragged.sent);
    [dragged.areas touchEnded:thumb at:CGPointMake(300, 300)];
    CHECK([dragged.sent isEqualToString:Tap(kR)], "and the lift lets go of R: %@", dragged.sent);

    // Every finger let go releases a held key: the areas are told to drop everything.
    Rig *dropped = NewRig();
    UITouch *held = Finger();
    [dropped.areas touchBegan:held at:[dropped centre:@"jump"]];
    [dropped.areas cancelAll];
    CHECK([dropped.sent isEqualToString:Tap(kR)] && dropped.areas.activeFingerCount == 0, "cancelAll releases R: %@", dropped.sent);
}

static void no_hold_key_long_press_taps(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"bags"]];
    [rig at:1];
    CHECK(rig.keys.count == 0, "nothing while held: %@", rig.sent);
    [rig.areas touchEnded:finger at:[rig centre:@"bags"]];
    CHECK([rig.sent isEqualToString:Tap(kSix)], "Bags' tap key at the lift: %@", rig.sent);
}

static void two_fingers_two_keys(void) {
    Rig *rig = NewRig();
    UITouch *one = Finger(), *three = Finger();
    CHECK([rig.areas touchBegan:one at:[rig centre:@"spell1"]], "spell1");
    CHECK([rig.areas touchBegan:three at:[rig centre:@"spell3"]], "spell3");
    CHECK(rig.areas.activeFingerCount == 2, "two fingers: %lu", (unsigned long)rig.areas.activeFingerCount);
    CHECK(Showing([rig.areas pressViewForTouch:one], rig.view) && Showing([rig.areas pressViewForTouch:three], rig.view), "both lit");
    [rig at:0.1];
    [rig.areas touchEnded:one at:[rig centre:@"spell1"]];
    [rig.areas touchEnded:three at:[rig centre:@"spell3"]];
    NSCountedSet *sent = [[NSCountedSet alloc] initWithArray:rig.keys];
    for (NSString *key in @[@"120v", @"120^", @"118v", @"118^"])
        CHECK([sent countForObject:key] == 1, "%@ once: %@", key, rig.sent);
    CHECK(rig.keys.count == 4, "both tap keys, one each, nothing else: %@", rig.sent);
    // And one finger holding while the other taps: each on its own.
    Rig *mixed = NewRig();
    UITouch *holder = Finger(), *tapper = Finger();
    [mixed.areas touchBegan:holder at:[mixed centre:@"spell2"]];
    [mixed at:0.2];
    [mixed.areas touchBegan:tapper at:[mixed centre:@"spell3"]];
    [mixed at:0.3];
    [mixed.areas touchEnded:tapper at:[mixed centre:@"spell3"]];
    [mixed at:0.45];
    NSString *tapThenHold = [NSString stringWithFormat:@"%@ %@", Tap(kF4), Tap(kE)];
    CHECK([mixed.sent isEqualToString:tapThenHold], "a tap during another finger's hold: %@", mixed.sent);
    [mixed at:0.5];
    [mixed.areas touchBegan:tapper at:[mixed centre:@"spell3"]];
    [mixed at:0.75];
    CHECK([mixed.sent hasSuffix:Tap(kE)] && mixed.keys.count == 4, "the second finger's own hold clock starts at its own touch: %@", mixed.sent);
    [mixed at:0.95];
    CHECK([mixed.sent hasSuffix:Tap(kF)], "spell3's hold at 0.45 s after it began: %@", mixed.sent);
}

static void hold_time_from_contract(void) {
    AKTouchContract *slow = FixtureContract(@"hold=0.45", @"hold=0.6");
    CHECK(slow.holdSeconds == 0.6, "the fixture with hold=0.6 parses");
    Rig *rig = [[Rig alloc] initWithContract:slow];
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
    [rig at:0.5];
    CHECK(rig.keys.count == 0, "no hold key at 0.5 s: %@", rig.sent);
    CHECK(fabs([rig.areas holdRingForTouch:finger].progress - 0.5 / 0.6) < 0.01, "the ring fills over 0.6 s");
    [rig at:0.6];
    CHECK([rig.sent isEqualToString:Tap(kE)], "sent at 0.6 s: %@", rig.sent);
}

static void ipados_unchanged(void) {
    // Outside iPad touch there is no contract (AKTouchCurrentContract is nil), and nothing is claimed.
    AKTouchContractReset();
    SetMode(@"ipados");
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    AKTouchAreas *areas = [[AKTouchAreas alloc] initWithView:view];
    NSMutableArray *keys = [NSMutableArray array];
    areas.keySender = ^(uint16_t code, NSUInteger mods, BOOL down) { [keys addObject:@(code)]; };
    CHECK(areas.contract == nil, "no contract in iPadOS");
    UITouch *finger = Finger();
    CGRect spell2 = AKTouchAreaRect([FixtureContract(nil, nil) areaNamed:@"spell2"], view.bounds.size);
    CGPoint p = CGPointMake(CGRectGetMidX(spell2), CGRectGetMidY(spell2));
    CHECK(![areas touchBegan:finger at:p] && ![areas claimsPoint:p], "a finger where spell2 would be is not claimed");
    CHECK(![areas touchEnded:finger at:p], "nor its lift");
    CHECK(view.subviews.count == 0 && keys.count == 0, "nothing drawn, nothing sent");
    CHECK(![areas showMissingNoticeIfNeeded], "and no notice outside iPad touch");
    NSSet *both = [NSSet setWithObjects:Finger(), Finger(), nil];
    CHECK([[areas unclaimedTouches:both phase:UITouchPhaseBegan] isEqualToSet:both], "every finger goes to the host's own gestures");
    SetMode(@"ipadtouch");
}

static void world_touch_not_claimed(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    CGPoint world = CGPointMake(683, 600);
    CHECK(![rig.areas claimsPoint:world], "the middle of the screen is the world");
    CHECK(![rig.areas touchBegan:finger at:world] && rig.view.subviews.count == 0 && rig.keys.count == 0, "not claimed, nothing drawn");
    CHECK(![rig.areas touchMoved:finger at:[rig centre:@"spell2"]] && ![rig.areas touchEnded:finger at:[rig centre:@"spell2"]],
          "a world finger that slides onto a button is still the world's");
    CHECK(rig.keys.count == 0, "and sends no key: %@", rig.sent);
    // The host's form: of two fingers, the one on a button is taken.
    UITouch *a = Finger(), *b = Finger();
    NSMutableSet *both = [NSMutableSet setWithObjects:a, b, nil];
    // unclaimedTouches asks each finger where it is; give them places through the per-finger calls.
    CHECK([rig.areas touchBegan:a at:[rig centre:@"spell1"]] && ![rig.areas touchBegan:b at:world], "one on spell1, one in the world");
    CHECK([rig.areas ownsTouch:a] && ![rig.areas ownsTouch:b], "only the button's finger is held");
    (void)both;
}

static void unknown_key_is_no_key(void) {
    AKTouchContract *odd = FixtureContract(@"spell2,BR,302,80,64,64,CTRL-ALT-SHIFT-F3,", @"spell2,BR,302,80,64,64,CTRL-ALT-SHIFT-F20,");
    CHECK(odd != nil, "the reader takes the line (it does not check key names)");
    Rig *rig = [[Rig alloc] initWithContract:odd];
    UITouch *finger = Finger();
    CHECK([rig.areas touchBegan:finger at:[rig centre:@"spell2"]], "still a button");
    [rig.areas touchEnded:finger at:[rig centre:@"spell2"]];
    CHECK(rig.keys.count == 0, "an unknown tap key sends nothing: %@", rig.sent);
    UITouch *holder = Finger();
    [rig.areas touchBegan:holder at:[rig centre:@"spell2"]];
    [rig at:0.45];
    CHECK([rig.sent isEqualToString:Tap(kE)], "its known hold key still works: %@", rig.sent);
}

static void contract_reload_releases_and_replaces(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"jump"]];
    AKTouchContract *moved = FixtureContract(@"jump,BR,190,51,58,58", @"jump,BR,600,51,58,58");
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchContractDidChangeNotification object:moved];
    CHECK(rig.areas.contract == moved, "the saved buttons are the ones in use");
    CHECK([rig.sent isEqualToString:Tap(kR)] && rig.areas.activeFingerCount == 0, "a key held across the reload is released: %@", rig.sent);
    CGRect old = AKTouchAreaRect([FixtureContract(nil, nil) areaNamed:@"jump"], rig.view.bounds.size);
    CHECK(![rig.areas claimsPoint:CGPointMake(CGRectGetMidX(old), CGRectGetMidY(old))], "the old place is not Jump any more");
    CHECK([rig.areas claimsPoint:[rig centre:@"jump"]], "the new place is");
}

static void rects_follow_view_size(void) {
    Rig *rig = NewRig();
    rig.view.frame = CGRectMake(0, 0, 1180, 820);
    UITouch *finger = Finger();
    CGPoint centre = [rig centre:@"spell2"];
    CHECK([rig.areas touchBegan:finger at:centre], "spell2 where it is at the new size");
    CHECK(CGRectEqualToRect([rig.areas pressViewForTouch:finger].frame, CGRectInset([rig rect:@"spell2"], -2, -2)), "glow at the new size");
}

/// The host's key path: a sink that records, and the characters a Mac would report.
@interface Sink : NSObject <AKTouchKeySink>
@property NSMutableArray<NSString *> *log;
@end
@implementation Sink
- (void)touchKey:(unsigned short)code characters:(NSString *)characters modifiers:(NSUInteger)modifiers pressed:(BOOL)pressed {
    if (!self.log) self.log = [NSMutableArray array];
    [self.log addObject:[NSString stringWithFormat:@"%u %@ %04x %lu", code, pressed ? @"down" : @"up",
                         characters.length ? [characters characterAtIndex:0] : 0, (unsigned long)modifiers]];
}
- (void)touchPointerAt:(CGPoint)p click:(BOOL)click {
    if (!self.log) self.log = [NSMutableArray array];
    [self.log addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f", click ? @"click" : @"move", p.x, p.y]];
}
@end

static void send_key_reaches_the_host(void) {
    Sink *sink = [Sink new];
    AKTouchSetKeySink(sink);
    AKTouchSendKey(kF3, kChord, YES);
    AKTouchSendKey(kF3, kChord, NO);
    AKTouchSendKey(kE, kChord, YES);
    AKTouchSendKey(kSix, kChord, YES);
    NSArray *expected = @[[NSString stringWithFormat:@"99 down f706 %lu", (unsigned long)kChord],
                          [NSString stringWithFormat:@"99 up f706 %lu", (unsigned long)kChord],
                          [NSString stringWithFormat:@"14 down 0065 %lu", (unsigned long)kChord],
                          [NSString stringWithFormat:@"22 down 0036 %lu", (unsigned long)kChord]];
    CHECK([sink.log isEqualToArray:expected], "the host gets code, characters and the chord: %@", sink.log);
    CHECK([AKTouchCharactersForKeyCode(111) isEqualToString:@""] && [AKTouchCharactersForKeyCode(29) isEqualToString:@"0"] &&
          [AKTouchCharactersForKeyCode(6) isEqualToString:@"z"], "F12, 0 and Z");
    // Every key the contract can name has characters.
    for (NSString *name in @[@"F1", @"F5", @"F9", @"F11", @"1", @"5", @"9", @"A", @"M", @"Q", @"Y"]) {
        uint16_t code = 0;
        AKTouchKeyCodeForName([@"CTRL-ALT-SHIFT-" stringByAppendingString:name], &code, NULL);
        CHECK(AKTouchCharactersForKeyCode(code).length == 1, "characters for %@", name);
    }
    // The keypad and F13..F19: the characters the host posts with each code (as AppKit gives them: keypad digits and
    // symbols as typed, F13+ as the private-use NSF13FunctionKey (U+F710) ... NSF19FunctionKey (U+F716)).
    NSDictionary<NSNumber *, NSString *> *extra = @{
        @82: @"0", @83: @"1", @84: @"2", @85: @"3", @86: @"4", @87: @"5", @88: @"6", @89: @"7", @91: @"8", @92: @"9",
        @65: @".", @67: @"*", @69: @"+", @75: @"/", @78: @"-",
        @105: @"\uF710", @107: @"\uF711", @113: @"\uF712", @106: @"\uF713", @64: @"\uF714", @79: @"\uF715", @80: @"\uF716"};
    CHECK(extra.count == 22, "22 new codes");
    for (NSNumber *code in extra) {
        NSString *got = AKTouchCharactersForKeyCode(code.unsignedShortValue);
        CHECK([got isEqualToString:extra[code]], "characters for code %@: %04x", code, got.length ? [got characterAtIndex:0] : 0);
    }
    CHECK([AKTouchCharactersForKeyCode(81) isEqualToString:@""] && [AKTouchCharactersForKeyCode(90) isEqualToString:@""] &&
          [AKTouchCharactersForKeyCode(108) isEqualToString:@""], "codes that are no TouchPlay key (keypad equals, F20) stay empty");
    AKTouchSetKeySink(nil);
    AKTouchSendKey(kF3, kChord, YES);   // no host: nothing, and no crash
    CHECK(sink.log.count == 4, "a key with no host goes nowhere");
    (void)kControl; (void)kOption; (void)kShift; (void)kD;
}

/// The keypad and F13..F19 chords as an area sends them: each of the 22 names as a contract tap key, in the game's
/// modifier order or the reverse, plays its code with all three modifiers, down then up at the lift. A hold key on a new
/// name plays; W stays no key; a new name without all three modifiers is no key.
static void new_chords_play(void) {
    NSDictionary<NSString *, NSNumber *> *extra = @{
        @"NUMPAD0": @82, @"NUMPAD1": @83, @"NUMPAD2": @84, @"NUMPAD3": @85, @"NUMPAD4": @86, @"NUMPAD5": @87, @"NUMPAD6": @88,
        @"NUMPAD7": @89, @"NUMPAD8": @91, @"NUMPAD9": @92, @"NUMPADDECIMAL": @65, @"NUMPADMULTIPLY": @67, @"NUMPADPLUS": @69,
        @"NUMPADDIVIDE": @75, @"NUMPADMINUS": @78,
        @"F13": @105, @"F14": @107, @"F15": @113, @"F16": @106, @"F17": @64, @"F18": @79, @"F19": @80};
    NSString *replace = @"spell2,BR,302,80,64,64,CTRL-ALT-SHIFT-F3,";
    for (NSString *prefix in @[@"ALT-CTRL-SHIFT-", @"SHIFT-CTRL-ALT-"]) {
        for (NSString *name in extra) {
            Rig *rig = [[Rig alloc] initWithContract:FixtureContract(replace, [NSString stringWithFormat:@"spell2,BR,302,80,64,64,%@%@,", prefix, name])];
            UITouch *finger = Finger();
            [rig.areas touchBegan:finger at:[rig centre:@"spell2"]];
            [rig.areas touchEnded:finger at:[rig centre:@"spell2"]];
            unsigned code = extra[name].unsignedIntValue;
            CHECK([rig.sent isEqualToString:Tap(code)] && rig.allChorded && rig.mods.count == 2, "%@%@ taps code %u chorded: %@", prefix, name, code, rig.sent);
        }
    }
    Rig *holdRig = [[Rig alloc] initWithContract:FixtureContract(@"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,CTRL-ALT-SHIFT-D", @"spell1,BR,54,68,88,88,CTRL-ALT-SHIFT-F2,ALT-CTRL-SHIFT-NUMPAD7")];
    UITouch *hold = Finger();
    [holdRig.areas touchBegan:hold at:[holdRig centre:@"spell1"]]; [holdRig at:1.0]; [holdRig.areas touchEnded:hold at:[holdRig centre:@"spell1"]];
    CHECK([holdRig.sent isEqualToString:Tap(89)] && holdRig.allChorded, "a hold key on NUMPAD7 plays code 89 chorded: %@", holdRig.sent);
    Rig *wRig = [[Rig alloc] initWithContract:FixtureContract(replace, @"spell2,BR,302,80,64,64,ALT-CTRL-SHIFT-W,")];
    UITouch *wTap = Finger();
    [wRig.areas touchBegan:wTap at:[wRig centre:@"spell2"]]; [wRig.areas touchEnded:wTap at:[wRig centre:@"spell2"]];
    CHECK(wRig.keys.count == 0, "W is still no key: %@", wRig.sent);
    Rig *bareRig = [[Rig alloc] initWithContract:FixtureContract(replace, @"spell2,BR,302,80,64,64,ALT-CTRL-NUMPAD1,")];
    UITouch *bareTap = Finger();
    [bareRig.areas touchBegan:bareTap at:[bareRig centre:@"spell2"]]; [bareRig.areas touchEnded:bareTap at:[bareRig centre:@"spell2"]];
    CHECK(bareRig.keys.count == 0, "NUMPAD1 without SHIFT is no key: %@", bareRig.sent);
}

static void default_sender_is_the_host_path(void) {
    Sink *sink = [Sink new];
    AKTouchSetKeySink(sink);
    Rig *rig = NewRig();
    rig.areas.keySender = nil;   // back to the default: AKTouchSendKey
    UITouch *finger = Finger();
    [rig.areas touchBegan:finger at:[rig centre:@"spell1"]];
    [rig.areas touchEnded:finger at:[rig centre:@"spell1"]];
    CHECK(sink.log.count == 2 && [sink.log.firstObject hasPrefix:@"120 down"] && [sink.log.lastObject hasPrefix:@"120 up"], "spell1's F2 through the host: %@", sink.log);
    AKTouchSetKeySink(nil);
}


/// I1: the hold with the real clock and the real timer - nobody ticks by hand.
static void hold_fires_from_the_real_timer(void) {
    Rig *rig = NewRig();
    rig.areas.clock = nil;   // the system uptime
    UITouch *one = Finger(), *two = Finger();
    [rig.areas touchBegan:one at:[rig centre:@"spell2"]];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    CHECK(rig.keys.count == 0, "nothing at 0.2 s: %@", rig.sent);
    CHECK([rig.areas holdRingForTouch:one].state == AKTouchHoldRingFilling, "the timer drew the ring");
    [rig.areas touchBegan:two at:[rig centre:@"spell3"]];   // a second finger, 0.2 s later, held with it
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    CHECK([rig.sent isEqualToString:Tap(kE)], "spell2's hold key from the timer alone, by 0.6 s: %@", rig.sent);
    CHECK([rig.areas holdRingForTouch:one].state == AKTouchHoldRingDone, "its ring popped");
    CHECK([rig.areas holdRingForTouch:two].state == AKTouchHoldRingFilling, "the second still filling");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    NSString *both = [NSString stringWithFormat:@"%@ %@", Tap(kE), Tap(kF)];
    CHECK([rig.sent isEqualToString:both], "then spell3's, on its own clock: %@", rig.sent);
    CHECK([rig.areas holdRingForTouch:two].state == AKTouchHoldRingDone, "its ring popped too");
    [rig.areas touchEnded:one at:[rig centre:@"spell2"]];
    [rig.areas touchEnded:two at:[rig centre:@"spell3"]];
    CHECK([rig.sent isEqualToString:both], "the lifts add nothing: %@", rig.sent);
}

/// M1: a finger let go of by a reload (or a size change) stays the areas' until it lifts: its later
/// moves and lift are swallowed, never handed to the host's gestures, and send nothing.
static void orphaned_finger_is_swallowed(void) {
    Rig *rig = NewRig();
    UITouch *jump = Finger(), *spell = Finger();
    [rig.areas touchBegan:jump at:[rig centre:@"jump"]];
    [rig.areas touchBegan:spell at:[rig centre:@"spell2"]];
    [rig.areas cancelAll];
    CHECK([rig.sent isEqualToString:Tap(kR)] && rig.areas.activeFingerCount == 0, "R released, nobody active: %@", rig.sent);
    CHECK([rig.areas ownsTouch:jump] && [rig.areas ownsTouch:spell], "but both fingers are still not the world's");
    CHECK([rig.areas touchMoved:jump at:CGPointMake(400, 400)], "a move is swallowed");
    NSSet *moved = [rig.areas unclaimedTouches:[NSSet setWithObjects:jump, spell, nil] phase:UITouchPhaseMoved];
    CHECK(moved.count == 0, "the host's form hands neither on (%lu)", (unsigned long)moved.count);
    CHECK([rig.areas touchEnded:jump at:CGPointMake(400, 400)] && [rig.areas touchCancelled:spell], "the lift and the cancel are swallowed");
    CHECK([rig.sent isEqualToString:Tap(kR)], "and send nothing: %@", rig.sent);
    CHECK(![rig.areas ownsTouch:jump] && ![rig.areas touchMoved:jump at:CGPointMake(1, 1)], "once lifted they are forgotten");
    // The same after a reload to no contract at all.
    UITouch *held = Finger();
    [rig.areas touchBegan:held at:[rig centre:@"jump"]];
    rig.areas.contract = nil;
    NSSet *ended = [rig.areas unclaimedTouches:[NSSet setWithObject:held] phase:UITouchPhaseEnded];
    CHECK(ended.count == 0, "with no contract left, its lift is still swallowed");
    NSString *twice = [NSString stringWithFormat:@"%@ %@", Tap(kR), Tap(kR)];
    CHECK([rig.sent isEqualToString:twice], "R down and up once more: %@", rig.sent);
}

/// M2: two fingers on one press button hold one key: down at the first, up at the last.
static void one_press_key_two_fingers(void) {
    Rig *rig = NewRig();
    UITouch *a = Finger(), *b = Finger();
    [rig.areas touchBegan:a at:[rig centre:@"jump"]];
    [rig.areas touchBegan:b at:[rig centre:@"jump"]];
    CHECK([rig.sent isEqualToString:@"15v"], "R down once: %@", rig.sent);
    [rig.areas touchEnded:a at:[rig centre:@"jump"]];
    CHECK([rig.sent isEqualToString:@"15v"], "still down while the second finger is: %@", rig.sent);
    [rig.areas touchCancelled:b];
    CHECK([rig.sent isEqualToString:Tap(kR)], "up with the last: %@", rig.sent);
    // cancelAll with two on it: one up.
    [rig.areas touchBegan:a at:[rig centre:@"jump"]];
    [rig.areas touchBegan:b at:[rig centre:@"jump"]];
    [rig.areas cancelAll];
    NSString *twice = [NSString stringWithFormat:@"%@ %@", Tap(kR), Tap(kR)];
    CHECK([rig.sent isEqualToString:twice], "cancelAll: one down, one up: %@", rig.sent);
}

static void jump_and_dive_independent(void) {
    Rig *rig = NewDiveRig();
    UITouch *jump = Finger(), *dive = Finger();
    [rig.areas touchBegan:jump at:[rig centre:@"jump"]];
    [rig.areas touchBegan:dive at:[rig centre:@"dive"]];
    CHECK([rig.sent isEqualToString:@"15v 17v"], "R and T down: %@", rig.sent);
    [rig.areas touchEnded:jump at:[rig centre:@"jump"]];
    CHECK([rig.sent isEqualToString:@"15v 17v 15^"], "lifting Jump lets go of R only: %@", rig.sent);
    [rig.areas touchEnded:dive at:[rig centre:@"dive"]];
    CHECK([rig.sent isEqualToString:@"15v 17v 15^ 17^"], "then T: %@", rig.sent);
}

/// M4: Dive is a press button like Jump: T down on begin, up on end, up on cancel (Dive on T: see NewDiveRig).
static void dive_press_and_release(void) {
    Rig *rig = NewDiveRig();
    UITouch *finger = Finger();
    CHECK([rig.areas touchBegan:finger at:[rig centre:@"dive"]], "Dive is an area");
    CHECK([rig.sent isEqualToString:@"17v"], "T down on begin: %@", rig.sent);
    [rig at:2];
    CHECK([rig.sent isEqualToString:@"17v"], "held: %@", rig.sent);
    [rig.areas touchEnded:finger at:[rig centre:@"dive"]];
    CHECK([rig.sent isEqualToString:Tap(kT)] && rig.allChorded, "T up on end, with the chord: %@", rig.sent);
    Rig *cancelled = NewDiveRig();
    UITouch *again = Finger();
    [cancelled.areas touchBegan:again at:[cancelled centre:@"dive"]];
    [cancelled.areas touchCancelled:again];
    CHECK([cancelled.sent isEqualToString:Tap(kT)], "T up on cancel: %@", cancelled.sent);
}

static void missing_notice_once(void) {
    // A game with buttons gets no notice.
    Rig *rig = NewRig();
    CHECK(![rig.areas showMissingNoticeIfNeeded] && !rig.areas.missingNotice, "no notice with a contract");
    // iPad touch with no contract: the notice, once per game start, and it never takes a touch.
    AKTouchContractReset();
    SetMode(@"ipadtouch");
    [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:@"WolkaraForeverAppLanguage"];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    AKTouchAreas *areas = [[AKTouchAreas alloc] initWithView:view];
    CHECK(areas.contract == nil, "no contract here (the working directory has no game)");
    // not in the world (login, character select) TouchPlay is not drawn, so nothing is "not found" yet:
    // the host's ask is held, and the notice is shown when the buttons go live with still no contract.
    areas.live = NO;
    CHECK(![areas showMissingNoticeIfNeeded] && !areas.missingNotice, "live NO: no notice");
    areas.live = YES;
    CHECK(areas.missingNotice != nil, "live YES: the notice the host asked for is shown");
    UIView *notice = areas.missingNotice;
    areas.live = NO;
    areas.live = YES;
    CHECK(areas.missingNotice == notice && notice.superview == view, "going live again shows it no second time");
    CHECK(Showing(notice, view) && !notice.userInteractionEnabled, "in the game view, never taking a touch");
    UILabel *label = nil;
    for (UIView *sub in notice.subviews) if ([sub isKindOfClass:UILabel.class]) label = (UILabel *)sub;
    // In the app's language; the app's tables lie beside this test, as they do beside the app.
    CHECK([label.text hasPrefix:@"Touch buttons not found"], "the notice's words (English): %@", label.text);
    CHECK(![areas showMissingNoticeIfNeeded], "not twice");
    AKTouchAreas *second = [[AKTouchAreas alloc] initWithView:view];
    CHECK(![second showMissingNoticeIfNeeded], "not again in the same game start");
    CHECK(AKTouchMissingNoticeSeconds >= 5 && AKTouchMissingNoticeSeconds <= 7, "about six seconds");
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverAppLanguage"];
}


#pragma mark the input path: aiming by dragging off a spell (mockups 23, 24), the world key, quiet fingers

/// Begins `finger` on `area` and drags it out to `to`: the input path's drag off (the tap key, once).
static void DragOff(Rig *rig, UITouch *finger, NSString *area, CGPoint to) {
    [rig.areas touchBegan:finger at:[rig centre:area]];
    [rig at:rig.now + 0.1];
    [rig.areas touchMoved:finger at:to];
}

/// A finger dragged off a spell aims: the spell's key went out when it left (the game shows its circle),
/// the host's pointer follows the finger from there, and the lift on the world is a left click there.
static void drag_to_world_clicks_there(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    DragOff(rig, finger, @"spell7", CGPointMake(900, 600));
    CHECK([rig.sent isEqualToString:Tap(kF8)] && rig.allChorded, "spell7's F8 once, when it left: %@", rig.sent);
    CHECK([rig.pointed isEqualToString:@"move 900,600"], "the cursor jumps to the finger as it leaves: %@", rig.pointed);
    CHECK([rig.areas touchMoved:finger at:CGPointMake(640, 560)], "the aiming finger is still the areas'");
    CHECK([rig.pointed isEqualToString:@"move 900,600; move 640,560"], "and the cursor follows it: %@", rig.pointed);
    [rig at:2];   // no hold while aiming, however long
    CHECK([rig.areas touchEnded:finger at:CGPointMake(640, 560)], "its lift is the areas'");
    CHECK([rig.pointed isEqualToString:@"move 900,600; move 640,560; click 640,560"], "a left click where it lifts: %@", rig.pointed);
    CHECK([rig.sent isEqualToString:Tap(kF8)], "and no other key: %@", rig.sent);
    CHECK(rig.areas.activeFingerCount == 0 && ![rig.areas ownsTouch:finger], "then it is let go");
}

/// Lifted on Interact (the Cancel button while a spell is aimed): Interact's hold key (the add-on's
/// hidden "stop" button),, with its chord, down and up; no click. Never Escape, which opens the
/// game menu when nothing is being aimed. A contract whose Interact has no hold key: nothing at all.
static void drag_to_interact_cancels(void) {
    Rig *rig = NewStopRig();
    CHECK([[rig.areas.contract areaNamed:@"interact"].holdKey isEqualToString:@"CTRL-ALT-SHIFT-R"] &&
          [[rig.areas.contract areaNamed:@"jump"].pressKey isEqualToString:@"CTRL-ALT-SHIFT-S"], "the newer key set");
    UITouch *finger = Finger();
    DragOff(rig, finger, @"spell7", CGPointMake(900, 600));
    CGPoint cancel = [rig centre:@"interact"];
    [rig.areas touchMoved:finger at:cancel];
    CHECK([rig.areas touchEnded:finger at:cancel], "its lift is the areas'");
    NSString *expected = [NSString stringWithFormat:@"%@ %@", Tap(kF8), Tap(kR)];
    CHECK([rig.sent isEqualToString:expected] && rig.allChorded, "F8 when it left, then Interact's hold key R with the chord: %@", rig.sent);
    CHECK(![rig.pointed containsString:@"click"], "no click: %@", rig.pointed);
    CHECK(rig.areas.activeFingerCount == 0, "let go");
    // Anywhere inside Interact counts, not only its centre.
    Rig *corner = NewStopRig();
    UITouch *again = Finger();
    DragOff(corner, again, @"spell1", CGPointMake(900, 600));
    CGRect interact = [corner rect:@"interact"];
    [corner.areas touchEnded:again at:CGPointMake(CGRectGetMinX(interact) + 2, CGRectGetMaxY(interact) - 2)];
    NSString *cornerExpected = [NSString stringWithFormat:@"%@ %@", Tap(kF2), Tap(kR)];
    CHECK([corner.sent isEqualToString:cornerExpected] && ![corner.pointed containsString:@"click"],
          "a corner of Interact stops too: %@ / %@", corner.sent, corner.pointed);
    // The iPad's current file: Interact has no hold key. The lift sends nothing and clicks nothing.
    Rig *old = NewRig();
    UITouch *third = Finger();
    DragOff(old, third, @"spell7", CGPointMake(900, 600));
    CHECK([old.areas touchEnded:third at:[old centre:@"interact"]], "its lift is the areas'");
    CHECK([old.sent isEqualToString:Tap(kF8)], "no key but F8 (no Escape): %@", old.sent);
    CHECK(![old.pointed containsString:@"click"], "no click: %@", old.pointed);
}

/// Lifted over any other button while aiming (another spell, Bags, Jump...): a stop too,
/// never a click on that secure button, and never that button's own key.
static void drag_to_any_area_stops(void) {
    for (NSString *name in @[@"bags", @"spell3", @"jump", @"player", @"chat", @"minimap"]) {
        Rig *rig = NewStopRig();
        UITouch *finger = Finger();
        DragOff(rig, finger, @"spell7", CGPointMake(900, 600));
        [rig.areas touchMoved:finger at:[rig centre:name]];
        CHECK([rig.areas touchEnded:finger at:[rig centre:name]], "%@: the lift is the areas'", name);
        NSString *stopped = [NSString stringWithFormat:@"%@ %@", Tap(kF8), Tap(kR)];
        CHECK([rig.sent isEqualToString:stopped], "%@: F8, then the stop key only: %@", name, rig.sent);
        CHECK(![rig.pointed containsString:@"click"], "%@: no click: %@", name, rig.pointed);
        CHECK(rig.view.subviews.count == 0 || ![rig.areas pressViewForTouch:finger], "%@: nothing lit", name);
        Rig *old = NewRig();
        UITouch *t = Finger();
        DragOff(old, t, @"spell7", CGPointMake(900, 600));
        [old.areas touchEnded:t at:[old centre:name]];
        CHECK([old.sent isEqualToString:Tap(kF8)] && ![old.pointed containsString:@"click"], "%@ without a stop key: nothing: %@ / %@", name, old.sent, old.pointed);
    }
}

/// Only a spell aims. Dragged off another button (Bags), its key went out once and that is all: no
/// cursor, no click at the lift (the input path's behaviour).
static void only_spells_aim(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    DragOff(rig, finger, @"bags", CGPointMake(700, 500));
    CHECK([rig.sent isEqualToString:Tap(kSix)], "Bags' key once: %@", rig.sent);
    [rig.areas touchMoved:finger at:CGPointMake(640, 560)];
    CHECK([rig.areas touchEnded:finger at:CGPointMake(640, 560)], "still the areas' finger");
    CHECK(rig.pointer.count == 0 && [rig.sent isEqualToString:Tap(kSix)], "no cursor, no click, no Escape: %@ / %@", rig.pointed, rig.sent);
    // Every spell aims.
    for (NSString *name in @[@"spell1", @"spell2", @"spell3", @"spell4", @"spell5", @"spell6", @"spell7"]) {
        Rig *each = NewRig();
        UITouch *t = Finger();
        DragOff(each, t, name, CGPointMake(600, 500));
        [each.areas touchEnded:t at:CGPointMake(600, 500)];
        CHECK([each.pointed isEqualToString:@"move 600,500; click 600,500"], "%@ aims: %@", name, each.pointed);
    }
}

/// An aiming finger that is cancelled (the system took it) or let go of by a reload or a size change
/// clicks nothing, and stops the aim (Interact's hold key) so the game is not left targeting.
static void aiming_cancelled_stops(void) {
    NSString *stopped = [NSString stringWithFormat:@"%@ %@", Tap(kF8), Tap(kR)];
    Rig *rig = NewStopRig();
    UITouch *finger = Finger();
    DragOff(rig, finger, @"spell7", CGPointMake(900, 600));
    CHECK([rig.areas touchCancelled:finger], "the cancel is the areas'");
    CHECK([rig.pointed isEqualToString:@"move 900,600"] && [rig.sent isEqualToString:stopped], "the stop key, no click: %@ / %@", rig.pointed, rig.sent);
    Rig *resize = NewStopRig();
    UITouch *held = Finger();
    DragOff(resize, held, @"spell7", CGPointMake(900, 600));
    [resize.areas cancelAll];
    CHECK([resize.sent isEqualToString:stopped], "cancelAll (a size change) stops it: %@", resize.sent);
    CHECK([resize.areas touchMoved:held at:CGPointMake(640, 560)] && [resize.areas touchEnded:held at:CGPointMake(640, 560)], "then swallowed");
    CHECK([resize.pointed isEqualToString:@"move 900,600"] && [resize.sent isEqualToString:stopped], "no cursor, no click, nothing more: %@ / %@", resize.pointed, resize.sent);
    // A reload (a new contract) stops it with the key the old contract had.
    Rig *reload = NewStopRig();
    UITouch *third = Finger();
    DragOff(reload, third, @"spell7", CGPointMake(900, 600));
    reload.areas.contract = FixtureContract(nil, nil);
    CHECK([reload.sent isEqualToString:stopped], "a reload stops it: %@", reload.sent);
    // Without a stop key: nothing.
    Rig *old = NewRig();
    UITouch *fourth = Finger();
    DragOff(old, fourth, @"spell7", CGPointMake(900, 600));
    [old.areas touchCancelled:fourth];
    CHECK([old.sent isEqualToString:Tap(kF8)] && [old.pointed isEqualToString:@"move 900,600"], "no stop key, nothing: %@ / %@", old.sent, old.pointed);
}

/// Inside the 10 pt allowance a spell finger is still on the button: no aim, no cursor.
static void no_aim_inside_the_allowance(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    CGRect area = [rig rect:@"spell7"];
    [rig.areas touchBegan:finger at:[rig centre:@"spell7"]];
    [rig.areas touchMoved:finger at:CGPointMake(CGRectGetMinX(area) - 8, CGRectGetMidY(area))];
    [rig.areas touchEnded:finger at:CGPointMake(CGRectGetMinX(area) - 8, CGRectGetMidY(area))];
    CHECK(rig.pointer.count == 0 && [rig.sent isEqualToString:Tap(kF8)], "a plain tap at the lift: %@ / %@", rig.sent, rig.pointed);
}

/// The contract's world key (TouchPlay shows the card of what is under the cursor): its chord, down and up.
static void world_key_from_contract(void) {
    Rig *rig = NewRig();
    CHECK([rig.areas sendWorldKey], "the fixture names CTRL-ALT-SHIFT-F1");
    CHECK([rig.sent isEqualToString:Tap(kF1)] && rig.allChorded, "F1 with the chord, down and up: %@", rig.sent);
    Rig *odd = [[Rig alloc] initWithContract:FixtureContract(@"world=CTRL-ALT-SHIFT-F1", @"world=CTRL-ALT-SHIFT-F20")];
    CHECK(odd.areas.contract && ![odd.areas sendWorldKey] && odd.keys.count == 0, "a key name it does not know is no key: %@", odd.sent);
    rig.areas.contract = nil;
    [rig.keys removeAllObjects];
    CHECK(![rig.areas sendWorldKey] && rig.keys.count == 0, "no contract, no world key");
}

/// A finger the host keeps quiet (the 20 pt edge zone) is the areas' until it lifts, and sends nothing.
static void quiet_finger_is_swallowed(void) {
    Rig *rig = NewRig();
    UITouch *finger = Finger();
    [rig.areas keepQuiet:finger];
    CHECK([rig.areas ownsTouch:finger] && rig.areas.activeFingerCount == 0, "held quietly, not an active button finger");
    NSSet *moved = [rig.areas unclaimedTouches:[NSSet setWithObject:finger] phase:UITouchPhaseMoved];
    CHECK(moved.count == 0, "its moves are not the host's");
    CHECK([rig.areas touchEnded:finger at:[rig centre:@"spell2"]], "its lift is swallowed, even over a button");
    CHECK(rig.keys.count == 0 && rig.pointer.count == 0 && rig.view.subviews.count == 0, "nothing sent or drawn: %@", rig.sent);
    CHECK(![rig.areas ownsTouch:finger], "then forgotten");
}

/// The newer key set: Dive presses T; Interact taps C on a lift and, held, sends R (the stop button;
/// harmless when nothing is aimed). Its Jump presses S, a walk key: no key, so Jump sends
/// nothing with this set - the add-on's pool skips W, A, S and D from now on.
static void stop_key_set_jump_and_dive(void) {
    Rig *rig = NewStopRig();
    UITouch *jump = Finger(), *dive = Finger(), *interact = Finger();
    CHECK([rig.areas touchBegan:jump at:[rig centre:@"jump"]], "Jump is still a button");
    [rig.areas touchBegan:dive at:[rig centre:@"dive"]];
    [rig.areas touchEnded:jump at:[rig centre:@"jump"]];
    [rig.areas touchEnded:dive at:[rig centre:@"dive"]];
    CHECK([rig.sent isEqualToString:@"17v 17^"], "T held and let go; Jump's S never sent: %@", rig.sent);
    [rig.keys removeAllObjects];
    [rig.areas touchBegan:interact at:[rig centre:@"interact"]];
    [rig at:rig.now + 1];
    [rig.areas touchEnded:interact at:[rig centre:@"interact"]];
    CHECK([rig.sent isEqualToString:Tap(kR)], "Interact held: R: %@", rig.sent);
}


static BOOL SentWalkKey(Rig *rig) {
    for (NSString *key in rig.keys) {
        int code = key.intValue;
        if (code == 13 || code == 0 || code == 1 || code == 2) return YES;
    }
    return NO;
}
/// a contract key on a walk key's code (W, A, S or D) is no key. The host sends by key code, so a
/// chord on one would release (or repeat) the walk stick's held key. The iPad's own v1 file has three: spell1's
/// hold (D), the minimap's tap (A) and Dive's press (S).
static void walk_keys_are_no_key(void) {
    Rig *rig = NewRig();
    UITouch *spell = Finger();
    CHECK([rig.areas touchBegan:spell at:[rig centre:@"spell1"]], "spell1 is a button");
    [rig at:1.0];
    [rig.areas touchEnded:spell at:[rig centre:@"spell1"]];
    CHECK([rig.sent isEqualToString:Tap(kF2)] && !SentWalkKey(rig), "spell1 held: no D chord; with no hold key it taps F2 at the lift: %@", rig.sent);
    [rig.keys removeAllObjects];
    UITouch *minimap = Finger(), *dive = Finger();
    CHECK([rig.areas touchBegan:minimap at:[rig centre:@"minimap"]], "the minimap is a button");
    [rig.areas touchEnded:minimap at:[rig centre:@"minimap"]];
    CHECK([rig.areas touchBegan:dive at:[rig centre:@"dive"]], "Dive is a button");
    [rig.areas touchEnded:dive at:[rig centre:@"dive"]];
    CHECK(rig.keys.count == 0, "the minimap's A and Dive's S send nothing: %@", rig.sent);
    // A tap key on A, and one on W, send nothing; the world key on W is no world key.
    AKTouchContract *odd = FixtureContract(@"spell2,BR,302,80,64,64,CTRL-ALT-SHIFT-F3,", @"spell2,BR,302,80,64,64,CTRL-ALT-SHIFT-A,");
    odd.worldKey = @"CTRL-ALT-SHIFT-W";
    Rig *other = [[Rig alloc] initWithContract:odd];
    UITouch *tap = Finger();
    [other.areas touchBegan:tap at:[other centre:@"spell2"]];
    [other.areas touchEnded:tap at:[other centre:@"spell2"]];
    CHECK(other.keys.count == 0, "a tap key on A sends nothing: %@", other.sent);
    CHECK(![other.areas sendWorldKey] && other.keys.count == 0, "a world key on W is no world key: %@", other.sent);
    AKTouchContract *w = FixtureContract(@"spell3,BR,289,158,64,64,CTRL-ALT-SHIFT-F4,", @"spell3,BR,289,158,64,64,CTRL-ALT-SHIFT-W,");
    Rig *wRig = [[Rig alloc] initWithContract:w];
    UITouch *wTap = Finger();
    [wRig.areas touchBegan:wTap at:[wRig centre:@"spell3"]];
    [wRig.areas touchEnded:wTap at:[wRig centre:@"spell3"]];
    CHECK(wRig.keys.count == 0, "a tap key on W sends nothing: %@", wRig.sent);
}

/// The add-on's current key set: no key on W, A, S or D, so every one of its keys plays.
/// The same key set bound in the game's own order (ALT-CTRL-SHIFT-, the order the game looks a binding up by) plays
/// exactly the same keys and chords.
static void a22_contract_plays_every_key(void) {
    for (NSString *file in @[@"TouchPlay-v1-a22.lua", @"TouchPlay-v1-altorder.lua"]) {
        Rig *rig = [[Rig alloc] initWithContract:AKTouchContractParse(Fixture(file))];
        CHECK(rig.areas.contract.areas.count == 26, "%@: 26 areas", file);
        UITouch *jump = Finger(), *dive = Finger(), *minimap = Finger(), *spell = Finger(), *tap = Finger();
        [rig.areas touchBegan:jump at:[rig centre:@"jump"]]; [rig.areas touchEnded:jump at:[rig centre:@"jump"]];
        [rig.areas touchBegan:dive at:[rig centre:@"dive"]]; [rig.areas touchEnded:dive at:[rig centre:@"dive"]];
        [rig.areas touchBegan:minimap at:[rig centre:@"minimap"]]; [rig.areas touchEnded:minimap at:[rig centre:@"minimap"]];
        [rig.areas touchBegan:spell at:[rig centre:@"spell1"]]; [rig at:1.0]; [rig.areas touchEnded:spell at:[rig centre:@"spell1"]];
        [rig.areas touchBegan:tap at:[rig centre:@"spell2"]]; [rig.areas touchEnded:tap at:[rig centre:@"spell2"]];
        // V (9), X (7), B (11), spell1's hold F (3) and spell2's tap F3 (99), each with the chord.
        CHECK([rig.sent isEqualToString:@"9v 9^ 7v 7^ 11v 11^ 3v 3^ 99v 99^"] && rig.allChorded && !SentWalkKey(rig),
              "%@: Jump V, Dive X, minimap B, spell1 held F, spell2 tapped F3: %@", file, rig.sent);
    }
}

/// TouchPlay's chat strip: a tap opens the app's chat keyboard instead of sending the strip's
/// chord (the composer sends F12 + the line + Return). A long press is a tap too (no hold key); a finger slid
/// off the strip sends nothing and opens nothing. The strip still lights under the finger.
static void chat_area_opens_the_chat_keyboard(void) {
    for (NSString *file in @[@"TouchPlay-v1.lua", @"TouchPlay-v1-a22.lua"]) {
        Rig *rig = [[Rig alloc] initWithContract:AKTouchContractParse(Fixture(file))];
        __block int opened = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKTouchChatAreaTappedNotification object:nil queue:nil
                                                                  usingBlock:^(NSNotification *note) { (void)note; opened++; }];
        UITouch *tap = Finger();
        CHECK([rig.areas touchBegan:tap at:[rig centre:@"chat"]], "%@: the chat strip is an area", file);
        CHECK([rig.areas pressViewForTouch:tap] != nil, "%@: it lights", file);
        CHECK(opened == 0, "%@: nothing until the lift", file);
        CHECK([rig.areas touchEnded:tap at:[rig centre:@"chat"]], "%@: the lift is the areas'", file);
        CHECK(opened == 1 && rig.keys.count == 0, "%@: the keyboard once, no chord: %d / %@", file, opened, rig.sent);
        UITouch *press = Finger();
        [rig.areas touchBegan:press at:[rig centre:@"chat"]];
        [rig at:rig.now + 1.0];
        [rig.areas touchEnded:press at:[rig centre:@"chat"]];
        CHECK(opened == 2 && rig.keys.count == 0, "%@: a long press opens it too: %d / %@", file, opened, rig.sent);
        UITouch *slid = Finger();
        DragOff(rig, slid, @"chat", CGPointMake(700, 500));
        [rig.areas touchEnded:slid at:CGPointMake(700, 500)];
        CHECK(opened == 2 && rig.keys.count == 0 && rig.pointer.count == 0, "%@: slid off, nothing: %d / %@", file, opened, rig.sent);
        UITouch *cancelled = Finger();
        [rig.areas touchBegan:cancelled at:[rig centre:@"chat"]];
        [rig.areas touchCancelled:cancelled];
        CHECK(opened == 2 && rig.keys.count == 0, "%@: cancelled, nothing", file);
        [rig.areas setLive:NO windowOpen:NO chatOnly:YES];
        CHECK(rig.areas.chatOnly && !rig.areas.live && rig.areas.liveContract == nil, "S10 Sheet exposes chat only, no live contract");
        CHECK(![rig.areas sendWorldKey] && rig.keys.count == 0, "S10 Sheet cannot send the world key");
        CHECK([rig.areas claimsPoint:[rig centre:@"chat"]] && ![rig.areas claimsPoint:[rig centre:@"spell1"]],
              "S2/S3 Sheet claims chat, leaves other buttons plain");
        UITouch *sheet = Finger();
        CHECK([rig.areas touchBegan:sheet at:[rig centre:@"chat"]], "S12 Sheet chat finger claimed");
        [rig.areas touchEnded:sheet at:[rig centre:@"chat"]];
        CHECK(opened == 3 && rig.keys.count == 0 && rig.pointer.count == 0, "S2 Sheet tap opens composer once, no key or click");
        UITouch *sliding = Finger();
        DragOff(rig, sliding, @"chat", CGPointMake(700, 500));
        [rig.areas touchEnded:sliding at:CGPointMake(700, 500)];
        CHECK(opened == 3 && rig.keys.count == 0 && rig.pointer.count == 0, "S4 Sheet slide off opens nothing");
        UITouch *heldSheet = Finger();
        [rig.areas touchBegan:heldSheet at:[rig centre:@"chat"]];
        [rig.areas setLive:NO windowOpen:NO chatOnly:NO];
        [rig.areas touchEnded:heldSheet at:[rig centre:@"chat"]];
        CHECK(opened == 3, "S9 leaving Sheet releases held chat finger");
        for (NSNumber *destination in @[@0, @1, @2]) {
            [rig.areas setLive:NO windowOpen:NO chatOnly:YES];
            UITouch *finger = Finger();
            [rig.areas touchBegan:finger at:[rig centre:@"chat"]];
            if (destination.integerValue == 0) [rig.areas setLive:NO windowOpen:NO chatOnly:NO];
            if (destination.integerValue == 1) [rig.areas setLive:NO windowOpen:YES chatOnly:NO];
            if (destination.integerValue == 2) [rig.areas setLive:YES windowOpen:NO chatOnly:NO];
            [rig.areas touchEnded:finger at:[rig centre:@"chat"]];
            CHECK(opened == 3 && rig.keys.count == 0, "S9 held chat released on Out, Window and In: %@", destination);
        }
        [rig.areas setLive:NO windowOpen:NO chatOnly:NO];
        CHECK(!rig.areas.chatOnly && ![rig.areas claimsPoint:[rig centre:@"chat"]] && ![rig.areas sendWorldKey],
              "S5/S10 Out leaves chat and world key plain");
        [rig.areas setLive:NO windowOpen:YES chatOnly:NO];
        CHECK(!rig.areas.chatOnly && ![rig.areas claimsPoint:[rig centre:@"chat"]], "S7 Window leaves chat plain");
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
}

/// A chat strip with a hold key (an add-on that gives it one): the hold sends that key, as any area's, and the
/// keyboard does not open; a tap still opens it.
static void chat_hold_key_holds(void) {
    NSString *text = Fixture(@"TouchPlay-v1-a22.lua");
    NSString *chat = @"chat,BL,296,24,568,52,CTRL-ALT-SHIFT-C,,";
    CHECK([text containsString:chat], "the a22 file's chat strip");
    Rig *rig = [[Rig alloc] initWithContract:AKTouchContractParse([text stringByReplacingOccurrencesOfString:chat withString:@"chat,BL,296,24,568,52,CTRL-ALT-SHIFT-C,CTRL-ALT-SHIFT-Y,"])];
    __block int opened = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKTouchChatAreaTappedNotification object:nil queue:nil
                                                              usingBlock:^(NSNotification *note) { (void)note; opened++; }];
    UITouch *held = Finger();
    [rig.areas touchBegan:held at:[rig centre:@"chat"]];
    [rig at:rig.now + 0.5];
    [rig.areas touchEnded:held at:[rig centre:@"chat"]];
    CHECK([rig.sent isEqualToString:@"16v 16^"] && rig.allChorded && opened == 0, "the hold key (Y), no keyboard: %@ / %d", rig.sent, opened);
    UITouch *tap = Finger();
    [rig.areas touchBegan:tap at:[rig centre:@"chat"]];
    [rig.areas touchEnded:tap at:[rig centre:@"chat"]];
    CHECK(opened == 1 && [rig.sent isEqualToString:@"16v 16^"], "a tap opens it, still no chord: %@ / %d", rig.sent, opened);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

/// one switch says whether TouchPlay's buttons are on screen. Off: nothing is claimed (the host's
/// plain touch), a held key is let go, the contract stays; on again: the buttons play again.
static void areas_live_switch(void) {
    Rig *rig = NewDiveRig();
    CHECK(rig.areas.live, "live by default");
    UITouch *dive = Finger();
    [rig.areas touchBegan:dive at:[rig centre:@"dive"]];
    CHECK([rig.sent isEqualToString:@"17v"], "Dive held: %@", rig.sent);
    rig.areas.live = NO;
    CHECK([rig.sent isEqualToString:@"17v 17^"], "off: the held key is let go: %@", rig.sent);
    CHECK([rig.areas touchEnded:dive at:[rig centre:@"dive"]] && [rig.sent isEqualToString:@"17v 17^"], "its lift is swallowed, nothing more");
    CHECK(rig.areas.contract != nil, "the contract is kept");
    UITouch *spell = Finger();
    CHECK(![rig.areas claimsPoint:[rig centre:@"spell2"]] && ![rig.areas touchBegan:spell at:[rig centre:@"spell2"]], "off: no area claims a finger");
    NSSet *both = [NSSet setWithObjects:Finger(), nil];
    CHECK([[rig.areas unclaimedTouches:both phase:UITouchPhaseBegan] isEqualToSet:both], "off: every finger is the host's");
    rig.areas.live = YES;
    UITouch *again = Finger();
    CHECK([rig.areas touchBegan:again at:[rig centre:@"spell2"]], "on again: spell2 is a button");
    [rig.areas touchEnded:again at:[rig centre:@"spell2"]];
    CHECK([rig.sent hasSuffix:Tap(kF3)], "and taps: %@", rig.sent);
}

/// `liveContract` is the contract while the buttons are on screen; the live switch tells the world.
static void live_contract_and_notification(void) {
    Rig *rig = NewRig();
    __block int posted = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:AKTouchAreasLiveDidChangeNotification object:rig.areas queue:nil
                                                              usingBlock:^(NSNotification *note) { (void)note; posted++; }];
    CHECK(rig.areas.liveContract == rig.areas.contract && rig.areas.liveContract != nil, "live: the contract");
    rig.areas.live = NO;
    CHECK(rig.areas.liveContract == nil && rig.areas.contract != nil, "not live: no contract for the host, the contract kept");
    CHECK(posted == 1, "the change is posted once: %d", posted);
    rig.areas.live = NO;
    CHECK(posted == 1, "no change, no post: %d", posted);
    rig.areas.live = YES;
    CHECK(posted == 2 && rig.areas.liveContract != nil, "back on: posted, the contract again");
    [rig.areas setLive:NO windowOpen:NO chatOnly:YES];
    CHECK(posted == 3 && rig.areas.chatOnly && rig.areas.liveContract == nil, "S10/S12 chat-only change posts and hides live contract");
    [rig.areas setLive:NO windowOpen:NO chatOnly:YES];
    CHECK(posted == 3, "S12 unchanged chat-only state does not post twice");
    [rig.areas setLive:NO windowOpen:NO chatOnly:NO];
    CHECK(posted == 4 && !rig.areas.chatOnly, "S9/S12 leaving Sheet posts");
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    // The world key is not sent out of the world (the host falls back to its plain right click).
    rig.areas.live = NO;
    CHECK(![rig.areas sendWorldKey] && rig.sent.length == 0, "no world key out of the world: %@", rig.sent);
}

/// The host's key path gets exactly what it is sent: the walk stick's keys go bare, and nothing sends a walk key
/// again behind anyone's back (a contract key on a walk key's code is no key, so there is no chord to repair).
static void walk_keys_go_bare_and_nothing_repeats_them(void) {
    Sink *sink = [Sink new];
    AKTouchSetKeySink(sink);
    CHECK(AKTouchIsWalkKeyCode(2) && AKTouchIsWalkKeyCode(13) && AKTouchIsWalkKeyCode(0) && AKTouchIsWalkKeyCode(1) && !AKTouchIsWalkKeyCode(3),
          "W, A, S, D are the walk keys");
    AKTouchSendWalkKey(2, YES);
    CHECK([sink.log isEqualToArray:(@[@"2 down 0064 0"])], "D down, bare: %@", sink.log);
    AKTouchSendKey(2, kChord, NO);
    CHECK([sink.log isEqualToArray:(@[@"2 down 0064 0", @"2 up 0064 917504"])], "a key event on D's code is sent as it is, not repeated: %@", sink.log);
    AKTouchSendWalkKey(3, YES);
    CHECK(sink.log.count == 2, "a key that is not a walk key is no walk key's: %@", sink.log);
    AKTouchSendWalkKey(2, NO);
    CHECK(sink.log.count == 3 && [sink.log.lastObject isEqual:@"2 up 0064 0"], "D up, bare: %@", sink.log);
    AKTouchSetKeySink(nil);
}

/// The pointer path to the host.
static void pointer_reaches_the_host(void) {
    Sink *sink = [Sink new];
    AKTouchSetKeySink(sink);
    Rig *rig = NewRig();
    rig.areas.pointerSender = nil;   // back to the default: AKTouchSendPointer
    UITouch *finger = Finger();
    DragOff(rig, finger, @"spell7", CGPointMake(900, 600));
    [rig.areas touchEnded:finger at:CGPointMake(640, 560)];
    CHECK([sink.log isEqualToArray:(@[@"move 900,600", @"click 640,560"])], "move and click through the host: %@", sink.log);
    AKTouchSetKeySink(nil);
    AKTouchSendPointer(CGPointMake(1, 1), YES);   // no host: nothing, no crash
    CHECK(sink.log.count == 2, "a pointer with no host goes nowhere");
}

#pragma mark The toolbar's dock (the input path)

// The add-on's current key set, and the same list left-handed: hand L, with the thumb side and the chat strip on
// the other corner (ns.Placed flips the corner a mirrored element counts from and keeps its numbers); the cards, the
// minimap, Bags, Menu and the quest list stay.
static AKTouchContract *LeftHandedCurrent(void) {
    NSString *text = [Fixture(@"TouchPlay-v1-a22.lua") stringByReplacingOccurrencesOfString:@"hand=R" withString:@"hand=L"];
    NSDictionary *flip = @{@"BR": @"BL", @"BL": @"BR", @"TR": @"TL", @"TL": @"TR"};
    for (NSString *name in @[@"spell1", @"spell2", @"spell3", @"spell4", @"spell5", @"spell6", @"spell7", @"page1", @"page2", @"page3",
                             @"page4", @"nexttarget", @"item1", @"item2", @"item3", @"item4", @"interact", @"jump", @"dive", @"chat"]) {
        for (NSString *corner in flip) {
            NSString *from = [NSString stringWithFormat:@"%@,%@,", name, corner];
            if (![text containsString:from]) continue;
            text = [text stringByReplacingOccurrencesOfString:from withString:[NSString stringWithFormat:@"%@,%@,", name, flip[corner]]];
            break;
        }
    }
    return AKTouchContractParse(text);
}
// The toolbar's frame at a dock: the top row's arithmetic (TouchControls.m placeToolbarInHost, iPad touch).
static CGRect ToolbarFrame(AKTouchToolbarDock dock, CGSize size, CGSize view, UIEdgeInsets safe) {
    (void)view;
    return CGRectMake(floor(dock.centreX - size.width / 2), safe.top + 8, size.width, size.height);
}
// Whether `frame` is on screen and 7 pt (the margin less the rounding) from every area.
static BOOL ToolbarClearOfAreas(AKTouchContract *contract, CGRect frame, CGSize view) {
    if (frame.origin.x < 7 || CGRectGetMaxX(frame) > view.width - 7 || frame.origin.y < 0 || CGRectGetMaxY(frame) > view.height) return NO;
    for (AKTouchArea *area in contract.areas)
        if (CGRectIntersectsRect(CGRectInset(AKTouchAreaRect(area, view), -7, -7), frame)) return NO;
    return YES;
}
static void handle_avoids_areas(void) {
    // Run 5: in iPad touch the toolbar is always in the top-centre band; it moves along the top row only to stay clear of
    // a button that reaches into it, and never far from the centre.
    CGSize open = CGSizeMake(208, 44), folded = CGSizeMake(96, 34);
    NSArray<NSValue *> *views = @[[NSValue valueWithCGSize:CGSizeMake(1366, 1024)], [NSValue valueWithCGSize:CGSizeMake(1194, 834)],
                                  [NSValue valueWithCGSize:CGSizeMake(1210, 834)]];
    NSArray<NSValue *> *insets = @[[NSValue valueWithUIEdgeInsets:UIEdgeInsetsZero], [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(24, 0, 20, 0)]];
    NSDictionary<NSString *, AKTouchContract *> *contracts = @{
        @"right-handed (a22)": AKTouchContractParse(Fixture(@"TouchPlay-v1-a22.lua")),
        @"left-handed": LeftHandedCurrent(),
        @"older add-on (v1)": AKTouchContractParse(Fixture(@"TouchPlay-v1.lua")),
        @"stop-key set": AKTouchContractParse(Fixture(@"TouchPlay-v1-stopkey.lua")),
    };
    CHECK(contracts.count == 4 && LeftHandedCurrent().leftHanded, "the contracts, one left-handed");
    for (NSString *name in contracts) {
        AKTouchContract *contract = contracts[name];
        CHECK(contract.areas.count == 26, "%@: 26 areas", name);
        for (NSValue *viewValue in views) for (NSValue *insetValue in insets) {
            CGSize view = viewValue.CGSizeValue; UIEdgeInsets safe = insetValue.UIEdgeInsetsValue;
            AKTouchToolbarDock dock = AKTouchToolbarDockFor(contract, view, safe, open, folded);
            CHECK(dock.clear, "%@ %@: a spot was found in the top band", name, NSStringFromCGSize(view));
            CGRect foldedFrame = ToolbarFrame(dock, folded, view, safe), openFrame = ToolbarFrame(dock, open, view, safe);
            CHECK(ToolbarClearOfAreas(contract, foldedFrame, view), "%@ %@: the folded handle %@ overlaps an area", name,
                  NSStringFromCGSize(view), NSStringFromCGRect(foldedFrame));
            CHECK(ToolbarClearOfAreas(contract, openFrame, view), "%@ %@: the open toolbar %@ overlaps an area", name,
                  NSStringFromCGSize(view), NSStringFromCGRect(openFrame));
            CHECK(CGRectContainsRect(openFrame, foldedFrame), "%@: the handle sits inside the open toolbar's place: %@ in %@", name,
                  NSStringFromCGRect(foldedFrame), NSStringFromCGRect(openFrame));
            CHECK(fabs(dock.centreX - view.width / 2) <= view.width * 0.2 + 0.5, "%@ %@: the top-centre band, centre %.0f of %.0f", name,
                  NSStringFromCGSize(view), dock.centreX, view.width);
        }
    }
    // The right-handed 1366 x 1024 case in numbers: the fixture's Target card reaches x 708, so the open toolbar starts 8 pt
    // after it, before Bags (from x 968).
    AKTouchToolbarDock beside = AKTouchToolbarDockFor(contracts[@"right-handed (a22)"], CGSizeMake(1366, 1024), UIEdgeInsetsZero, open, folded);
    CHECK(beside.clear && fabs(beside.centreX - (708 + 8 + 104)) < 1, "top row beside the Target card: centre %.1f", beside.centreX);
    // Nothing in the band: the centre. No contract; no areas at all.
    AKTouchToolbarDock none = AKTouchToolbarDockFor(nil, CGSizeMake(1366, 1024), UIEdgeInsetsZero, open, folded);
    CHECK(none.centreX == 683 && none.clear, "no contract: the top centre");
    AKTouchToolbarDock empty = AKTouchToolbarDockFor(AKTouchContractParse(@"TouchPlayDB = {\n[\"contract\"] = \"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=\",\n}"), CGSizeMake(1366, 1024), UIEdgeInsetsZero, open, folded);
    CHECK(empty.centreX == 683 && empty.clear, "no areas: the top centre");
    // A button across the whole top band: never a far corner - the centre, said not clear.
    AKTouchToolbarDock blocked = AKTouchToolbarDockFor(AKTouchContractParse(@"TouchPlayDB = {\n[\"contract\"] = \"TPC1;hold=0.45;hand=R;turn=1;world=CTRL-ALT-SHIFT-F1;areas=wide,TL,100,0,1100,120,CTRL-ALT-SHIFT-F2,,\",\n}"), CGSizeMake(1366, 1024), UIEdgeInsetsZero, open, folded);
    CHECK(!blocked.clear && blocked.centreX == 683, "a button over the whole band: the centre, not clear (%d, %.1f)", blocked.clear, blocked.centreX);
    // A window narrowed by Stage Manager: whatever the size, an answer inside the screen in the top band.
    for (NSNumber *width in @[@1024, @820, @700]) {
        CGSize view = CGSizeMake(width.doubleValue, 834);
        AKTouchToolbarDock narrow = AKTouchToolbarDockFor(contracts[@"right-handed (a22)"], view, UIEdgeInsetsZero, open, folded);
        CGRect frame = ToolbarFrame(narrow, folded, view, UIEdgeInsetsZero);
        CHECK(CGRectContainsRect(CGRectMake(0, 0, view.width, view.height), frame), "width %@: on screen: %@", width, NSStringFromCGRect(frame));
        if (narrow.clear) CHECK(ToolbarClearOfAreas(contracts[@"right-handed (a22)"], frame, view), "width %@: the handle is clear: %@", width, NSStringFromCGRect(frame));
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: test_touch_areas <fixtures folder>\n"); return 2; }
        gFixtures = [NSString stringWithUTF8String:argv[1]];
        CHECK(FixtureContract(nil, nil).areas.count == 26, "the iPad's contract, 26 areas, found in %@", gFixtures);
        id savedMode = [NSUserDefaults.standardUserDefaults objectForKey:AKInterfaceModeDefaultsKey];
        SetMode(@"ipadtouch");
        void (*tests[])(void) = {rule8_glow_on_touch, rule8_tap_sends_on_lift, rule2_hold_sends_hold_key_only, hold_ring_appears_after_0_15,
            slide_off_cancels_hold_ring, drag_off_sends_key_once, jump_press_and_release, no_hold_key_long_press_taps, two_fingers_two_keys,
            hold_time_from_contract, ipados_unchanged, world_touch_not_claimed, unknown_key_is_no_key, contract_reload_releases_and_replaces,
            rects_follow_view_size, send_key_reaches_the_host, new_chords_play, default_sender_is_the_host_path, hold_fires_from_the_real_timer,
            orphaned_finger_is_swallowed, one_press_key_two_fingers, jump_and_dive_independent, dive_press_and_release, missing_notice_once,
            drag_to_world_clicks_there, drag_to_interact_cancels, only_spells_aim, aiming_cancelled_stops, no_aim_inside_the_allowance,
            world_key_from_contract, quiet_finger_is_swallowed, pointer_reaches_the_host, drag_to_any_area_stops, stop_key_set_jump_and_dive,
            walk_keys_are_no_key, walk_keys_go_bare_and_nothing_repeats_them, a22_contract_plays_every_key, chat_area_opens_the_chat_keyboard, chat_hold_key_holds, areas_live_switch, live_contract_and_notification, handle_avoids_areas, outline_only_listed_areas};
        const char *names[] = {"rule8_glow_on_touch", "rule8_tap_sends_on_lift", "rule2_hold_sends_hold_key_only", "hold_ring_appears_after_0_15",
            "slide_off_cancels_hold_ring", "drag_off_sends_key_once", "jump_press_and_release", "no_hold_key_long_press_taps", "two_fingers_two_keys",
            "hold_time_from_contract", "ipados_unchanged", "world_touch_not_claimed", "unknown_key_is_no_key", "contract_reload_releases_and_replaces",
            "rects_follow_view_size", "send_key_reaches_the_host", "new_chords_play", "default_sender_is_the_host_path", "hold_fires_from_the_real_timer",
            "orphaned_finger_is_swallowed", "one_press_key_two_fingers", "jump_and_dive_independent", "dive_press_and_release", "missing_notice_once",
            "drag_to_world_clicks_there", "drag_to_interact_cancels", "only_spells_aim", "aiming_cancelled_stops", "no_aim_inside_the_allowance",
            "world_key_from_contract", "quiet_finger_is_swallowed", "pointer_reaches_the_host", "drag_to_any_area_stops", "stop_key_set_jump_and_dive",
            "walk_keys_are_no_key", "walk_keys_go_bare_and_nothing_repeats_them", "a22_contract_plays_every_key", "chat_area_opens_the_chat_keyboard", "chat_hold_key_holds", "areas_live_switch", "live_contract_and_notification", "handle_avoids_areas", "outline_only_listed_areas"};
        for (size_t i = 0; i < sizeof tests / sizeof *tests; i++) {
            int before = failures;
            tests[i]();
            printf("%s %s\n", failures == before ? "PASS" : "FAIL", names[i]);
        }
        if (savedMode) [NSUserDefaults.standardUserDefaults setObject:savedMode forKey:AKInterfaceModeDefaultsKey];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:AKInterfaceModeDefaultsKey];
        printf("TOUCH_AREAS_%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
        return failures ? 1 : 0;
    }
}
