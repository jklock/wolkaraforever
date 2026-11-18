#import "TouchAreas.h"
#import "InterfaceMode.h"
#import "AKHostLocalization.h"
#include <math.h>

const NSTimeInterval AKTouchHoldRingDelay = 0.15;
const CGFloat AKTouchDragOffDistance = 10;
const NSTimeInterval AKTouchMissingNoticeSeconds = 6;
NSNotificationName const AKTouchChatAreaTappedNotification = @"AKTouchChatAreaTapped";
NSNotificationName const AKTouchAreasLiveDidChangeNotification = @"AKTouchAreasLiveDidChange";

/// Above the game and the performance HUD (90000), below the cursor (100000).
static const CGFloat kFeedbackZ = 95000;
/// The press glow (18 Nov 2026, TouchPlay's press look): a 2 pt pale-gold edge 2 pt outside the area, a faint wash of
/// the same gold inside, a soft gold shadow round it; it fades out over 120 ms from the lift.
static const CGFloat kGlowOutset = 2, kGlowLine = 2, kGlowShadow = 7;
static const NSTimeInterval kGlowLetGo = 0.12;
static const CGFloat kRingLine = 5;
/// An area larger than this (the unit frames, the quest list) gets its ring under the finger.
static const CGFloat kRingAroundAreaMax = 120, kRingUnderFinger = 96;

static UIColor *AKTouchGold(CGFloat alpha) { return [UIColor colorWithRed:1 green:0xe2 / 255.0 blue:0x8c / 255.0 alpha:alpha]; }
/// TouchPlay's press gold (Style.lua, Kit.AddPress): (1, 0.9, 0.55).
static UIColor *AKTouchPaleGold(CGFloat alpha) { return [UIColor colorWithRed:1 green:0.9 blue:0.55 alpha:alpha]; }

#pragma mark The host's key path

static __weak id<AKTouchKeySink> gSink;

void AKTouchSetKeySink(id<AKTouchKeySink> sink) { gSink = sink; }

NSString *AKTouchCharactersForKeyCode(uint16_t code) {
    static NSDictionary<NSNumber *, NSString *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *t = [NSMutableDictionary dictionary];
        // Carbon kVK_* codes, as TouchContract.m's table; F-keys report AppKit's private-use characters
        // (NSF1FunctionKey = U+F704 ...), letters their lower case, digits themselves.
        const uint16_t fkeys[12] = {122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111};
        for (int i = 0; i < 12; i++) t[@(fkeys[i])] = [NSString stringWithFormat:@"%C", (unichar)(0xF704 + i)];
        const uint16_t digits[10] = {29, 18, 19, 20, 21, 23, 22, 26, 28, 25};   // 0 ... 9
        for (int i = 0; i < 10; i++) t[@(digits[i])] = [NSString stringWithFormat:@"%c", '0' + i];
        const uint16_t letters[26] = {0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6};
        for (int i = 0; i < 26; i++) t[@(letters[i])] = [NSString stringWithFormat:@"%c", 'a' + i];
        // The keypad (kVK_ANSI_Keypad*): digits and symbols as typed. F13..F19 are AppKit's NSF13FunctionKey ...
        // NSF19FunctionKey, U+F710 ... U+F716, in the order of F1..F12's U+F704 + i (the codes are not in key order).
        const uint16_t pad[10] = {82, 83, 84, 85, 86, 87, 88, 89, 91, 92};   // 0 ... 9
        for (int i = 0; i < 10; i++) t[@(pad[i])] = [NSString stringWithFormat:@"%c", '0' + i];
        t[@65] = @".";  t[@67] = @"*";  t[@69] = @"+";  t[@75] = @"/";  t[@78] = @"-";
        const uint16_t fhigh[7] = {105, 107, 113, 106, 64, 79, 80};   // F13 ... F19
        for (int i = 0; i < 7; i++) t[@(fhigh[i])] = [NSString stringWithFormat:@"%C", (unichar)(0xF710 + i)];
        table = t;
    });
    return table[@(code)] ?: @"";
}

BOOL AKTouchIsWalkKeyCode(uint16_t code) {
    return code == AKTouchWalkKeyW || code == AKTouchWalkKeyA || code == AKTouchWalkKeyS || code == AKTouchWalkKeyD;
}

void AKTouchSendKey(uint16_t code, NSUInteger mods, BOOL down) {
    id<AKTouchKeySink> sink = gSink;
    NSString *characters = AKTouchCharactersForKeyCode(code);
    [sink touchKey:code characters:characters modifiers:mods pressed:down];
}

void AKTouchSendWalkKey(uint16_t code, BOOL down) {
    if (!AKTouchIsWalkKeyCode(code)) return;
    id<AKTouchKeySink> sink = gSink;
    [sink touchKey:code characters:AKTouchCharactersForKeyCode(code) modifiers:0 pressed:down];
}

// A22: a contract key on a walk key's code is no key. Said once per key name, in the log.
static BOOL AKTouchAreaKey(NSString *name, NSString *area, uint16_t *code, NSUInteger *mods) {
    if (!name.length || !AKTouchKeyCodeForName(name, code, mods)) return NO;
    if (!AKTouchIsWalkKeyCode(*code)) return YES;
    static NSMutableSet<NSString *> *said;
    if (!said) said = [NSMutableSet set];
    if (![said containsObject:name]) {
        [said addObject:name];
        NSLog(@"[ak] touch areas: %@ on %@ shares a walk key's code (W, A, S, D); it is no key (the add-on's newer key set avoids them)", name, area);
    }
    return NO;
}

void AKTouchSendPointer(CGPoint p, BOOL click) {
    id<AKTouchKeySink> sink = gSink;
    [sink touchPointerAt:p click:click];
}

void AKTouchReleaseWorldGesture(void) {
    id<AKTouchKeySink> sink = gSink;
    if ([sink respondsToSelector:@selector(touchReleaseWorldGesture)]) [sink touchReleaseWorldGesture];
}

#pragma mark The toolbar's dock (Task 9)

const CGFloat AKTouchToolbarMargin = 8;
// The toolbar stays in the top-centre band: a clear spot is taken only this close to the centre, as a fraction of the width.
static const CGFloat kToolbarNearCentre = 0.2;

// The left edge nearest `preferred` at which a rectangle of `size`, its top at `rowTop`, is clear of every rect (each
// grown by the margin) and inside the sides; NAN when there is none. Each rect that shares the row forbids an open
// interval of left edges, so the nearest allowed edge is `preferred` itself, a forbidden interval's end, or an end of
// the range.
static CGFloat AKClearLeftEdge(NSArray<NSValue *> *rects, CGFloat viewWidth, CGSize size, CGFloat rowTop, CGFloat preferred) {
    CGFloat lo = AKTouchToolbarMargin, hi = viewWidth - AKTouchToolbarMargin - size.width;
    if (hi < lo) return NAN;
    NSMutableArray<NSValue *> *forbidden = [NSMutableArray array];
    for (NSValue *value in rects) {
        CGRect r = value.CGRectValue;
        if (CGRectIsEmpty(r)) continue;
        if (!(rowTop < CGRectGetMaxY(r) + AKTouchToolbarMargin && rowTop + size.height > CGRectGetMinY(r) - AKTouchToolbarMargin)) continue;
        [forbidden addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(r) - AKTouchToolbarMargin - size.width,
                                                                   CGRectGetMaxX(r) + AKTouchToolbarMargin)]];
    }
    NSMutableArray<NSNumber *> *candidates = [NSMutableArray arrayWithObjects:@(MIN(MAX(preferred, lo), hi)), @(lo), @(hi), nil];
    for (NSValue *value in forbidden) { [candidates addObject:@(value.CGPointValue.x)]; [candidates addObject:@(value.CGPointValue.y)]; }
    CGFloat best = NAN;
    for (NSNumber *candidate in candidates) {
        CGFloat x = candidate.doubleValue;
        if (x < lo - 1e-6 || x > hi + 1e-6) continue;
        BOOL inside = NO;
        for (NSValue *value in forbidden) if (x > value.CGPointValue.x + 1e-6 && x < value.CGPointValue.y - 1e-6) { inside = YES; break; }
        if (inside) continue;
        if (isnan(best) || fabs(x - preferred) < fabs(best - preferred)) best = x;
    }
    return best;
}

AKTouchToolbarDock AKTouchToolbarDockFor(AKTouchContract *contract, CGSize viewSize, UIEdgeInsets safe, CGSize openSize, CGSize foldedSize) {
    // The top centre: where it goes with no buttons, and when nothing clear is near enough.
    AKTouchToolbarDock centre = { viewSize.width / 2, NO };
    if (!contract.areas.count || viewSize.width <= 0 || viewSize.height <= 0) { centre.clear = YES; return centre; }
    NSMutableArray<NSValue *> *rects = [NSMutableArray arrayWithCapacity:contract.areas.count];
    for (AKTouchArea *area in contract.areas) [rects addObject:[NSValue valueWithCGRect:AKTouchAreaRect(area, viewSize)]];
    for (NSValue *sizeValue in @[[NSValue valueWithCGSize:openSize], [NSValue valueWithCGSize:foldedSize]]) {
        CGSize size = sizeValue.CGSizeValue;
        CGFloat preferred = (viewSize.width - size.width) / 2;
        CGFloat left = AKClearLeftEdge(rects, viewSize.width, size, safe.top + AKTouchToolbarMargin, preferred);
        if (!isnan(left) && fabs(left - preferred) <= viewSize.width * kToolbarNearCentre)
            return (AKTouchToolbarDock){ left + size.width / 2, YES };
    }
    return centre;
}

#pragma mark Feedback views

@interface AKTouchPressView ()
@property (nonatomic, readwrite, copy) NSString *areaName;
@property (nonatomic, readwrite, nullable) CABasicAnimation *letGoAnimation;
@end

@implementation AKTouchPressView
- (instancetype)initWithAreaRect:(CGRect)rect name:(NSString *)name round:(BOOL)round {
    if ((self = [super initWithFrame:CGRectInset(rect, -kGlowOutset, -kGlowOutset)])) {
        _areaName = [name copy];
        self.userInteractionEnabled = NO;
        self.layer.zPosition = kFeedbackZ;
        // The area's shape: the contract does not say it, so the round areas are known by name (AKTouchAreas); the rest
        // are rounded rectangles with a corner suited to their size - a fifth of the short side, 6 to 14 pt.
        CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
        self.layer.cornerRadius = round ? side / 2 : MIN(14, MAX(6, (CGFloat)lround(side / 5)));   // `round` is the argument here
        self.layer.backgroundColor = AKTouchPaleGold(0.12).CGColor;
        self.layer.borderWidth = kGlowLine;
        self.layer.borderColor = AKTouchPaleGold(0.9).CGColor;
        self.layer.shadowColor = AKTouchPaleGold(1).CGColor;
        self.layer.shadowOpacity = 0.8;
        self.layer.shadowRadius = kGlowShadow;
        self.layer.shadowOffset = CGSizeZero;
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;
        self.isAccessibilityElement = NO;
    }
    return self;
}
- (void)letGoReducingMotion:(BOOL)reduceMotion {
    // The render server runs it, so it fades even while the guest holds the main thread in its own loop. Reduce Motion:
    // no fade - lit for the same 120 ms, then gone.
    CABasicAnimation *letGo = [CABasicAnimation animationWithKeyPath:@"opacity"];
    letGo.fromValue = @1;
    letGo.toValue = reduceMotion ? @1 : @0;
    letGo.duration = kGlowLetGo;
    letGo.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    self.letGoAnimation = letGo;
    self.layer.opacity = 0;
    [self.layer addAnimation:letGo forKey:@"letGo"];
}
@end

@interface AKTouchHoldRing ()
@property (nonatomic, readwrite) AKTouchHoldRingState state;
@property (nonatomic, readwrite) CGFloat progress;
@end

@implementation AKTouchHoldRing {
    CAShapeLayer *_track, *_fill, *_cross, *_dot;
}
- (CALayer *)fingerDot { return _dot; }
- (instancetype)initWithCentre:(CGPoint)centre diameter:(CGFloat)diameter {
    if ((self = [super initWithFrame:CGRectMake(centre.x - diameter / 2, centre.y - diameter / 2, diameter, diameter)])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.layer.zPosition = kFeedbackZ + 1;
        self.isAccessibilityElement = NO;
        CGFloat radius = diameter / 2 - kRingLine / 2;
        CGPoint middle = CGPointMake(diameter / 2, diameter / 2);
        // From the top, clockwise: the way the mockup's ring fills.
        UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:middle radius:radius startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES];
        _track = [CAShapeLayer layer];
        _track.path = circle.CGPath; _track.fillColor = nil; _track.lineWidth = kRingLine;
        _track.strokeColor = [UIColor colorWithWhite:0 alpha:0.45].CGColor;
        _fill = [CAShapeLayer layer];
        _fill.path = circle.CGPath; _fill.fillColor = nil; _fill.lineWidth = kRingLine; _fill.lineCap = kCALineCapRound;
        _fill.strokeColor = AKTouchGold(0.95).CGColor;
        _fill.strokeEnd = 0;
        // Cancelled: a small cross in the middle, as in the mockup.
        UIBezierPath *cross = [UIBezierPath bezierPath];
        CGFloat arm = 6;
        [cross moveToPoint:CGPointMake(middle.x - arm, middle.y - arm)]; [cross addLineToPoint:CGPointMake(middle.x + arm, middle.y + arm)];
        [cross moveToPoint:CGPointMake(middle.x + arm, middle.y - arm)]; [cross addLineToPoint:CGPointMake(middle.x - arm, middle.y + arm)];
        _cross = [CAShapeLayer layer];
        _cross.path = cross.CGPath; _cross.lineWidth = 2.5; _cross.lineCap = kCALineCapRound;
        _cross.strokeColor = [UIColor colorWithWhite:0.75 alpha:0.9].CGColor; _cross.hidden = YES;
        // Filling: the finger, a small grey dot in the middle (mockup 10).
        CGFloat dot = round(MAX(12, diameter * 0.34));
        _dot = [CAShapeLayer layer];
        _dot.frame = CGRectMake(middle.x - dot / 2, middle.y - dot / 2, dot, dot);
        _dot.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, dot, dot)].CGPath;
        _dot.fillColor = [UIColor colorWithWhite:0.42 alpha:0.9].CGColor;
        for (CALayer *layer in @[_track, _fill, _dot, _cross]) [self.layer addSublayer:layer];
    }
    return self;
}
- (void)fillTo:(CGFloat)progress {
    if (_state != AKTouchHoldRingFilling) return;
    _progress = MAX(0, MIN(1, progress));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.strokeEnd = _progress;
    [CATransaction commit];
}
/// Full: the card opens. A short pop outward, then gone.
- (void)pop {
    if (_state != AKTouchHoldRingFilling) return;
    [self fillTo:1];
    _state = AKTouchHoldRingDone;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dot.hidden = YES;
    [CATransaction commit];
    self.layer.shadowColor = AKTouchGold(1).CGColor;
    self.layer.shadowOpacity = 0.9; self.layer.shadowRadius = 8; self.layer.shadowOffset = CGSizeZero;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = CGAffineTransformMakeScale(1.18, 1.18); self.alpha = 0; }
                     completion:^(BOOL finished) { (void)finished; [self removeFromSuperview]; }];
}
/// The finger slid away (or was taken): grey, a cross, shrinking and fading.
- (void)cancel {
    if (_state != AKTouchHoldRingFilling) return;
    _state = AKTouchHoldRingCancelled;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.strokeColor = [UIColor colorWithWhite:0.55 alpha:0.9].CGColor;
    _cross.hidden = NO;
    _dot.hidden = YES;
    [CATransaction commit];
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = CGAffineTransformMakeScale(0.8, 0.8); self.alpha = 0; }
                     completion:^(BOOL finished) { (void)finished; [self removeFromSuperview]; }];
}
@end

#pragma mark Areas

/// One area's keys, resolved once per contract. A name the reader does not know is no key.
@interface AKTouchResolvedArea : NSObject
@property (nonatomic, strong) AKTouchArea *area;
@property (nonatomic) BOOL hasTap, hasHold, hasPress;
@property (nonatomic) uint16_t tapCode, holdCode, pressCode;
@property (nonatomic) NSUInteger tapMods, holdMods, pressMods;
@property (nonatomic) BOOL round;
@property (nonatomic) BOOL aims;     // a spell: dragged off, the finger aims it (Task 5)
@property (nonatomic) BOOL opensChat;   // the chat strip: a tap opens the app's chat keyboard, never its chord (A7)
@end
@implementation AKTouchResolvedArea
@end

/// One finger on an area.
@interface AKTouchFinger : NSObject
@property (nonatomic, strong) AKTouchResolvedArea *area;
@property (nonatomic) CGRect rect;
@property (nonatomic) CGPoint start;
@property (nonatomic) NSTimeInterval began;
@property (nonatomic) BOOL pressDown;   // the press key is down
@property (nonatomic) BOOL finished;    // the hold fired or the finger slid off: no more of the button's keys
@property (nonatomic) BOOL aiming;      // slid off a spell: the pointer follows it, its lift clicks or cancels
@property (nonatomic) CGPoint aimedAt;  // where the pointer was last put
@property (nonatomic, strong) AKTouchPressView *glow;
@property (nonatomic, strong) AKTouchHoldRing *ring;
@end
@implementation AKTouchFinger
@end

static BOOL gMissingNoticeShown;

@implementation AKTouchAreas {
    __weak UIView *_view;
    NSArray<AKTouchResolvedArea *> *_resolved;
    NSArray<NSValue *> *_rects;
    CGSize _rectsSize;
    NSMapTable<UITouch *, AKTouchFinger *> *_fingers;
    NSTimer *_timer;
    // Fingers let go of by cancelAll (a reload, a size change) while still down, and the ones the host
    // keeps quiet (the edge zone): they stay the areas' until they lift, so their moves and lift never
    // reach the host's gestures, and they send nothing.
    NSHashTable<UITouch *> *_orphans;
    // Press keys held, by key code: two fingers on Jump hold R once, released with the last.
    NSCountedSet<NSNumber *> *_pressHeld;
    NSTimeInterval _lastContractAsk;
    UIView *_missingNotice;
    // The host asked for the notice while the buttons were not live (ruling A24): shown when they go live.
    BOOL _noticeWaiting;
    // The contract's world key, resolved once per contract.
    BOOL _hasWorldKey;
    uint16_t _worldCode;
    NSUInteger _worldMods;
}
@synthesize clock = _clock, keySender = _keySender, pointerSender = _pointerSender, reduceMotion = _reduceMotion;

// The areas made over each view, held weakly both ways: the host owns its areas, and a view of the
// layer over the same game (the walk stick) asks here instead of reaching into the host.
static NSMapTable<UIView *, AKTouchAreas *> *AKTouchAreasByView(void) {
    static NSMapTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSMapTable weakToWeakObjectsMapTable]; });
    return table;
}
+ (AKTouchAreas *)areasForView:(UIView *)view { return view ? [AKTouchAreasByView() objectForKey:view] : nil; }
- (instancetype)initWithView:(UIView *)view {
    if ((self = [super init])) {
        _view = view;
        if (view) [AKTouchAreasByView() setObject:self forKey:view];
        _fingers = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                         valueOptions:NSPointerFunctionsStrongMemory];
        _orphans = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
        _pressHeld = [NSCountedSet set];
        _live = YES;
        self.clock = nil;
        self.keySender = nil;
        self.pointerSender = nil;
        self.reduceMotion = nil;
        // Once per view setup: the contract is cached, not read per touch.
        self.contract = AKTouchCurrentContract();
        _lastContractAsk = self.clock();
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contractChanged:)
                                                   name:AKTouchContractDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_timer invalidate];
}

- (void)setClock:(NSTimeInterval (^)(void))clock {
    _clock = clock ?: ^NSTimeInterval { return NSProcessInfo.processInfo.systemUptime; };
}
- (void)setKeySender:(void (^)(uint16_t, NSUInteger, BOOL))sender {
    _keySender = sender ?: ^(uint16_t code, NSUInteger mods, BOOL down) { AKTouchSendKey(code, mods, down); };
}
- (void)setReduceMotion:(BOOL (^)(void))reduceMotion {
    _reduceMotion = reduceMotion ?: ^BOOL { return UIAccessibilityIsReduceMotionEnabled(); };
}
- (void)setPointerSender:(void (^)(CGPoint, BOOL))sender {
    _pointerSender = sender ?: ^(CGPoint p, BOOL click) { AKTouchSendPointer(p, click); };
}

#pragma mark The contract

- (void)contractChanged:(NSNotification *)note {
    // The player saved new buttons (ruling A18): they replace the old ones at once.
    if (![note.object isKindOfClass:AKTouchContract.class]) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self contractChanged:note]; });
        return;
    }
    self.contract = note.object;
}

- (void)setContract:(AKTouchContract *)contract {
    [self cancelAll];
    _contract = contract;
    NSMutableArray<AKTouchResolvedArea *> *resolved = [NSMutableArray array];
    for (AKTouchArea *area in contract.areas) {
        AKTouchResolvedArea *r = [AKTouchResolvedArea new];
        r.area = area;
        uint16_t code = 0; NSUInteger mods = 0;
        if ((r.hasTap = AKTouchAreaKey(area.tapKey, area.name, &code, &mods))) { r.tapCode = code; r.tapMods = mods; }
        if ((r.hasHold = AKTouchAreaKey(area.holdKey, area.name, &code, &mods))) { r.holdCode = code; r.holdMods = mods; }
        if ((r.hasPress = AKTouchAreaKey(area.pressKey, area.name, &code, &mods))) { r.pressCode = code; r.pressMods = mods; }
        r.round = [@[@"jump", @"dive", @"interact", @"minimap"] containsObject:area.name];
        r.opensChat = [area.name isEqualToString:@"chat"];
        r.aims = [@[@"spell1", @"spell2", @"spell3", @"spell4", @"spell5", @"spell6", @"spell7"] containsObject:area.name];
        [resolved addObject:r];
    }
    _resolved = resolved;
    _rects = nil;
    uint16_t code = 0; NSUInteger mods = 0;
    _hasWorldKey = AKTouchAreaKey(contract.worldKey, @"world", &code, &mods);
    _worldCode = _hasWorldKey ? code : 0;
    _worldMods = _hasWorldKey ? mods : 0;
}

- (void)setLive:(BOOL)live { [self setLive:live windowOpen:NO]; }
- (void)setLive:(BOOL)live windowOpen:(BOOL)windowOpen {
    windowOpen = windowOpen && !live;
    if (_live == live && _windowOpen == windowOpen) return;
    // Off: the buttons are not on screen, so no finger is theirs; held keys are let go (fingers still down stay
    // swallowed until they lift, as after a reload).
    if (!live && _live) [self cancelAll];
    _live = live;
    _windowOpen = windowOpen;
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchAreasLiveDidChangeNotification object:self];
    // The notice was held back while the buttons were not on screen: now they are, and this game has none.
    if (live && _noticeWaiting) { _noticeWaiting = NO; [self showMissingNoticeIfNeeded]; }
}
- (AKTouchContract *)liveContract { return _live ? _contract : nil; }

- (BOOL)sendWorldKey {
    if (!_contract || !_live || !_hasWorldKey) return NO;
    [self tapCode:_worldCode mods:_worldMods];
    return YES;
}

/// Interact (the Cancel button while a spell is aimed): its resolved area, and in `rect` its rectangle at
/// the current size; nil (and a null rectangle) when the contract has none.
- (AKTouchResolvedArea *)interactArea:(CGRect *)rect {
    NSArray<NSValue *> *rects = [self rects];
    for (NSUInteger i = 0; i < _resolved.count; i++) {
        if (![_resolved[i].area.name isEqualToString:@"interact"]) continue;
        if (rect) *rect = rects[i].CGRectValue;
        return _resolved[i];
    }
    if (rect) *rect = CGRectNull;
    return nil;
}

/// Stops an aimed spell (rulings A19, A21): Interact's hold key, which the add-on binds to a hidden "stop"
/// button (it stops spell targeting, and only while there is targeting), down and up with its chord.
/// Never Escape: with nothing aimed that opens the game menu. No hold key on Interact: nothing.
- (void)stopAiming:(AKTouchFinger *)finger {
    if (!finger.aiming) return;
    finger.aiming = NO;
    AKTouchResolvedArea *interact = [self interactArea:NULL];
    if (interact.hasHold) [self tapCode:interact.holdCode mods:interact.holdMods];
}

/// Nothing to use yet: ask again, at most once a second (an early read before the game folder was the
/// working directory is not an answer). Once there is a contract it is kept until a reload says otherwise.
- (void)refreshMissingContract {
    if (_contract) return;
    NSTimeInterval now = self.clock();
    if (now - _lastContractAsk < 1) return;
    _lastContractAsk = now;
    AKTouchContract *current = AKTouchCurrentContract();
    if (current) self.contract = current;
}

/// The areas' rectangles at the view's current size (recomputed when it changes: rotation, Stage Manager).
- (NSArray<NSValue *> *)rects {
    CGSize size = _view.bounds.size;
    if (!_rects || !CGSizeEqualToSize(size, _rectsSize)) {
        NSMutableArray *rects = [NSMutableArray arrayWithCapacity:_resolved.count];
        for (AKTouchResolvedArea *r in _resolved) [rects addObject:[NSValue valueWithCGRect:AKTouchAreaRect(r.area, size)]];
        _rects = rects;
        _rectsSize = size;
    }
    return _rects;
}

/// The area under `p`: the smallest one, so a button drawn over a larger frame wins.
- (NSInteger)indexAtPoint:(CGPoint)p {
    if (!_contract || !_live) return NSNotFound;
    NSArray<NSValue *> *rects = [self rects];
    NSInteger best = NSNotFound;
    CGFloat bestArea = INFINITY;
    for (NSUInteger i = 0; i < rects.count; i++) {
        CGRect rect = rects[i].CGRectValue;
        if (CGRectIsEmpty(rect) || !CGRectContainsPoint(rect, p)) continue;
        CGFloat size = rect.size.width * rect.size.height;
        if (size < bestArea) { best = (NSInteger)i; bestArea = size; }
    }
    return best;
}

- (BOOL)claimsPoint:(CGPoint)p { return [self indexAtPoint:p] != NSNotFound; }
- (BOOL)ownsTouch:(UITouch *)t { return t && ([_fingers objectForKey:t] != nil || [_orphans containsObject:t]); }
- (NSUInteger)activeFingerCount { return _fingers.count; }
- (AKTouchPressView *)pressViewForTouch:(UITouch *)t { return [_fingers objectForKey:t].glow; }
- (AKTouchHoldRing *)holdRingForTouch:(UITouch *)t { return [_fingers objectForKey:t].ring; }

#pragma mark Keys and feedback

- (void)tapCode:(uint16_t)code mods:(NSUInteger)mods {
    // TouchPlay's secure buttons act on the up click, so a tap is always a down and an up.
    self.keySender(code, mods, YES);
    self.keySender(code, mods, NO);
}

static void AKTouchShowNow(void (^change)(void)) {
    // Within one frame: no implicit animation, and committed now - the guest runs a nested loop in which
    // UIKit's own commit can wait (the host's cursor does the same).
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    change();
    [CATransaction commit];
    [CATransaction flush];
}

- (void)removeGlow:(AKTouchFinger *)finger {
    AKTouchPressView *glow = finger.glow;
    finger.glow = nil;
    if (!glow) return;
    BOOL reduceMotion = self.reduceMotion();
    AKTouchShowNow(^{ [glow letGoReducingMotion:reduceMotion]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kGlowLetGo + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AKTouchShowNow(^{ [glow removeFromSuperview]; });
    });
}

/// The finger's hold timing at `now`: the ring after 0.15 s, the hold key when the time is up.
- (void)advance:(AKTouchFinger *)finger to:(NSTimeInterval)now {
    if (finger.finished || !finger.area.hasHold) return;
    NSTimeInterval held = now - finger.began;
    double hold = _contract.holdSeconds > 0 ? _contract.holdSeconds : 0.45;
    if (held + 1e-9 >= AKTouchHoldRingDelay && !finger.ring) {
        CGRect rect = finger.rect;
        BOOL large = MAX(rect.size.width, rect.size.height) > kRingAroundAreaMax;
        CGPoint centre = large ? finger.start : CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        CGFloat diameter = large ? kRingUnderFinger : MAX(72, MAX(rect.size.width, rect.size.height) * 1.6);
        AKTouchHoldRing *ring = [[AKTouchHoldRing alloc] initWithCentre:centre diameter:diameter];
        finger.ring = ring;
        UIView *view = _view;
        AKTouchShowNow(^{ [view addSubview:ring]; });
    }
    [finger.ring fillTo:held / hold];
    if (held + 1e-9 < hold) return;
    // Full: the card. The hold key, down then up, and this finger is done.
    finger.finished = YES;
    [self tapCode:finger.area.holdCode mods:finger.area.holdMods];
    [finger.ring pop];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)tick {
    NSTimeInterval now = self.clock();
    BOOL waiting = NO;
    for (UITouch *touch in [_fingers keyEnumerator].allObjects) {
        AKTouchFinger *finger = [_fingers objectForKey:touch];
        [self advance:finger to:now];
        if (!finger.finished && finger.area.hasHold) waiting = YES;
    }
    if (!waiting) { [_timer invalidate]; _timer = nil; }
}

- (void)startTimer {
    if (_timer) return;
    __weak AKTouchAreas *weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *timer) { (void)timer; [weakSelf tick]; }];
    // The guest's own loop runs the default mode; common modes include it.
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

#pragma mark Fingers

- (BOOL)touchBegan:(UITouch *)t at:(CGPoint)p {
    if (!t) return NO;
    [_orphans removeObject:t];
    [self refreshMissingContract];
    NSInteger index = [self indexAtPoint:p];
    if (index == NSNotFound) return NO;
    AKTouchFinger *finger = [AKTouchFinger new];
    finger.area = _resolved[(NSUInteger)index];
    finger.rect = [self rects][(NSUInteger)index].CGRectValue;
    finger.start = p;
    finger.began = self.clock();
    [_fingers setObject:finger forKey:t];
    // Lit the frame it lands - only where the add-on says it always draws something (the contract's `outline=`; every
    // area when it does not say). An empty quest list's area took the finger and lit up for a tap the add-on ignored
    // (17 Nov 2026); the finger is still the area's and its keys go as before.
    if ([_contract outlinesArea:finger.area.area.name]) {
        AKTouchPressView *glow = [[AKTouchPressView alloc] initWithAreaRect:finger.rect name:finger.area.area.name round:finger.area.round];
        finger.glow = glow;
        UIView *view = _view;
        AKTouchShowNow(^{ [view addSubview:glow]; });
    }
    if (finger.area.hasPress) {
        finger.pressDown = YES;
        NSNumber *code = @(finger.area.pressCode);
        [_pressHeld addObject:code];
        if ([_pressHeld countForObject:code] == 1) self.keySender(finger.area.pressCode, finger.area.pressMods, YES);
    }
    if (finger.area.hasHold) [self startTimer];
    return YES;
}

- (BOOL)touchMoved:(UITouch *)t at:(CGPoint)p {
    if (t && [_orphans containsObject:t]) return YES;
    AKTouchFinger *finger = t ? [_fingers objectForKey:t] : nil;
    if (!finger) return NO;
    // Aiming: the pointer follows the finger, so the game's circle is under it.
    if (finger.aiming) {
        if (!CGPointEqualToPoint(p, finger.aimedAt)) { finger.aimedAt = p; self.pointerSender(p, NO); }
        return YES;
    }
    [self advance:finger to:self.clock()];
    if (finger.finished) return YES;
    if (CGRectContainsPoint(CGRectInset(finger.rect, -AKTouchDragOffDistance, -AKTouchDragOffDistance), p)) return YES;
    // Off the button before a hold: the tap key once, now (a ground spell starts aiming). Off a spell the
    // finger aims from here on: the pointer jumps to it now, after the key, and follows it.
    finger.finished = YES;
    if (finger.area.hasTap && !finger.area.opensChat) [self tapCode:finger.area.tapCode mods:finger.area.tapMods];
    [self removeGlow:finger];
    [finger.ring cancel];
    if (finger.area.aims && finger.area.hasTap) {
        finger.aiming = YES;
        finger.aimedAt = p;
        self.pointerSender(p, NO);
    }
    return YES;
}

- (void)letGo:(UITouch *)t finger:(AKTouchFinger *)finger {
    if (finger.pressDown) {
        finger.pressDown = NO;
        NSNumber *code = @(finger.area.pressCode);
        [_pressHeld removeObject:code];
        if ([_pressHeld countForObject:code] == 0) self.keySender(finger.area.pressCode, finger.area.pressMods, NO);
    }
    [self removeGlow:finger];
    [finger.ring cancel];
    [_fingers removeObjectForKey:t];
    if (!_fingers.count) { [_timer invalidate]; _timer = nil; }
}

- (BOOL)touchEnded:(UITouch *)t at:(CGPoint)p {
    if (t && [_orphans containsObject:t]) { [_orphans removeObject:t]; return YES; }
    AKTouchFinger *finger = t ? [_fingers objectForKey:t] : nil;
    if (!finger) return NO;
    if (finger.aiming) {
        // Lifted on the world: a left click there, which places the spell. Lifted over any button
        // (Interact, the Cancel button while aiming, or any other): the aim is stopped, and that secure
        // button is never clicked.
        if ([self indexAtPoint:p] != NSNotFound) [self stopAiming:finger];
        else { finger.aiming = NO; self.pointerSender(p, YES); }
        [self letGo:t finger:finger];
        return YES;
    }
    [self advance:finger to:self.clock()];
    // Lifted on the button before a hold (however long it stayed, when the area has no hold): the tap. The chat
    // strip's tap is the app's chat keyboard (ruling A7), never its chord: the composer's Send is F12 + the line.
    if (!finger.finished && finger.area.opensChat)
        [NSNotificationCenter.defaultCenter postNotificationName:AKTouchChatAreaTappedNotification object:self];
    else if (!finger.finished && finger.area.hasTap) [self tapCode:finger.area.tapCode mods:finger.area.tapMods];
    finger.finished = YES;
    // A ring that was filling just goes; it did not complete.
    if (finger.ring.state == AKTouchHoldRingFilling) { AKTouchHoldRing *ring = finger.ring; AKTouchShowNow(^{ [ring removeFromSuperview]; }); finger.ring = nil; }
    [self letGo:t finger:finger];
    return YES;
}

- (BOOL)touchCancelled:(UITouch *)t {
    if (t && [_orphans containsObject:t]) { [_orphans removeObject:t]; return YES; }
    AKTouchFinger *finger = t ? [_fingers objectForKey:t] : nil;
    if (!finger) return NO;
    // Cancelled clicks nothing; a held key is let go, and an aimed spell is stopped (A21).
    [self stopAiming:finger];
    finger.finished = YES;
    [self letGo:t finger:finger];
    return YES;
}

- (void)cancelAll {
    // Every held key let go, nothing tapped; the fingers are still down, so they stay ours until they lift.
    for (UITouch *touch in [_fingers keyEnumerator].allObjects) {
        AKTouchFinger *finger = [_fingers objectForKey:touch];
        [self stopAiming:finger];   // with the contract it was aimed under (a reload replaces it after this)
        finger.finished = YES;
        [self letGo:touch finger:finger];
        [_orphans addObject:touch];
    }
}

- (void)keepQuiet:(UITouch *)t {
    if (t && ![_fingers objectForKey:t]) [_orphans addObject:t];
}

- (NSSet<UITouch *> *)unclaimedTouches:(NSSet<UITouch *> *)touches phase:(UITouchPhase)phase {
    // Nothing held and nothing to claim with: every finger is the host's, untouched.
    BOOL canClaim = _live && (_contract || (phase == UITouchPhaseBegan && [self contractMayAppear]));
    if (!_fingers.count && !_orphans.count && !canClaim) return touches;
    NSMutableSet<UITouch *> *rest = [NSMutableSet setWithCapacity:touches.count];
    for (UITouch *touch in touches) {
        BOOL claimed = NO;
        UIView *view = _view;
        switch (phase) {
            case UITouchPhaseBegan:
                claimed = touch.type == UITouchTypeDirect && [self touchBegan:touch at:[touch locationInView:view]];
                break;
            case UITouchPhaseMoved:
            case UITouchPhaseStationary:
                claimed = [self touchMoved:touch at:[touch locationInView:view]];
                break;
            case UITouchPhaseEnded:
                claimed = [self touchEnded:touch at:[touch locationInView:view]];
                break;
            case UITouchPhaseCancelled:
                claimed = [self touchCancelled:touch];
                break;
            default:
                break;
        }
        if (!claimed) [rest addObject:touch];
    }
    return rest;
}

/// Whether a finger landing now could still find a contract (iPad touch with none read yet).
- (BOOL)contractMayAppear {
    return !_contract && AKInterfaceModeIsTouchPlay();
}

#pragma mark The notice (ruling A17)

- (UIView *)missingNotice { return _missingNotice; }

- (BOOL)showMissingNoticeIfNeeded {
    if (gMissingNoticeShown || !AKInterfaceModeIsTouchPlay()) return NO;
    // Not in the world (login, character select): TouchPlay is not drawn there, so "not found" would be noise.
    if (!_live) { _noticeWaiting = YES; return NO; }
    if (!_contract) { _lastContractAsk = self.clock(); self.contract = AKTouchCurrentContract(); }
    if (_contract) return NO;
    UIView *view = _view;
    CGSize size = view.bounds.size;
    if (!view || size.width <= 0 || size.height <= 0) return NO;
    gMissingNoticeShown = YES;

    CGFloat width = MIN(560, size.width - 48);
    UILabel *label = [UILabel new];
    label.text = AKHostLocalized(AKTouchContractMissingNoticeKey);
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    CGSize fit = [label sizeThatFits:CGSizeMake(width - 32, CGFLOAT_MAX)];
    label.frame = CGRectMake(16, 12, width - 32, ceil(fit.height));

    UIView *notice = [[UIView alloc] initWithFrame:CGRectMake(round((size.width - width) / 2), round(size.height * 0.36),
                                                              width, ceil(fit.height) + 24)];
    notice.userInteractionEnabled = NO;     // it never takes a touch
    notice.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.86];
    notice.layer.cornerRadius = 12;
    notice.layer.borderWidth = 1;
    notice.layer.borderColor = AKTouchGold(0.6).CGColor;
    notice.layer.zPosition = kFeedbackZ + 2;
    notice.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                              UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    notice.accessibilityIdentifier = @"wolkaraforever.touch.contractMissing";
    [notice addSubview:label];
    _missingNotice = notice;
    AKTouchShowNow(^{ [view addSubview:notice]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(AKTouchMissingNoticeSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.4 animations:^{ notice.alpha = 0; }
                         completion:^(BOOL finished) { (void)finished; [notice removeFromSuperview]; }];
    });
    return YES;
}
@end
