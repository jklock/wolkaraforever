#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "AKHostLocalization.h"
#import "InterfaceMode.h"
#import "LayoutStore.h"
#import "TouchControllerLog.h"
#import "TouchHaptics.h"
#import "TouchControls.h"
#include <math.h>
// The guest log in the app; a plain [ak] line where the fixture builds this file alone.
#if __has_include("AKSupport.h")
#import "AKSupport.h"
#define AKGamepadLog(...) AKLog(__VA_ARGS__)
#else
#define AKGamepadLog(...) NSLog(@"[ak] %@", [NSString stringWithFormat:__VA_ARGS__])
#endif

CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size) {
    if (!isfinite(point.x) || !isfinite(point.y) || !isfinite(size.width) || !isfinite(size.height) ||
        size.width <= 0 || size.height <= 0) return CGPointZero;
    CGFloat radius = MIN(size.width,size.height) / 2;
    CGFloat x = (point.x - size.width / 2) / radius, y = (size.height / 2 - point.y) / radius;
    CGFloat length = hypot(x,y);
    if (!isfinite(x) || !isfinite(y) || !isfinite(length)) return CGPointZero;
    if (length < 0.10) return CGPointZero;
    CGFloat scale = MIN(1,(length - 0.10) / 0.90) / length;
    return CGPointMake(x * scale,y * scale);
}

@interface AKGamepadButton : UIButton
@property(nonatomic, copy) NSString *element;
@property(nonatomic, copy) NSString *slot;
@property(nonatomic, readonly) BOOL pressed;
@property(nonatomic) NSInteger sector;
- (void)releaseInput;
@end
@implementation AKGamepadButton { CAShapeLayer *_sectorLayer; UIBezierPath *_sectorPath; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _sector = -1;
        self.exclusiveTouch = NO;
        self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.layer.cornerRadius = 22; self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
        self.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.64];
        [self setTitleColor:[UIColor colorWithWhite:1 alpha:0.95] forState:UIControlStateNormal];
        [self addTarget:self action:@selector(pressInput) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(releaseInput) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
    }
    return self;
}
- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    UIColor *color = pressed ? [UIColor colorWithRed:0.1 green:0.55 blue:0.65 alpha:0.8] : [UIColor colorWithWhite:0.13 alpha:0.64];
    if (_sector >= 0) _sectorLayer.fillColor = color.CGColor; else self.backgroundColor = color;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)setSector:(NSInteger)sector {
    _sector = sector; self.backgroundColor = UIColor.clearColor; self.layer.borderWidth = 0;
    if (!_sectorLayer) { _sectorLayer = [CAShapeLayer layer]; [self.layer insertSublayer:_sectorLayer atIndex:0]; }
    _sectorLayer.fillColor = [UIColor colorWithWhite:0.13 alpha:0.64].CGColor;
    _sectorLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor; _sectorLayer.lineWidth = 1;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews]; if (_sector < 0) return;
    CGPoint center = CGPointMake(self.bounds.size.width/2,self.bounds.size.height/2);
    CGFloat angle = (_sector - 1) * M_PI_2, start = angle - M_PI_4 + 0.045, end = angle + M_PI_4 - 0.045;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path addArcWithCenter:center radius:104 startAngle:start endAngle:end clockwise:YES];
    [path addArcWithCenter:center radius:60 startAngle:end endAngle:start clockwise:NO]; [path closePath];
    _sectorPath = path; _sectorLayer.frame = self.bounds; _sectorLayer.path = path.CGPath;
    self.titleLabel.frame = CGRectMake(center.x+82*cos(angle)-26,center.y+82*sin(angle)-18,52,36);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (_sector >= 0) return [_sectorPath containsPoint:point];
    return [super pointInside:point withEvent:event];
}
- (CGPoint)accessibilityActivationPoint {
    if (_sector < 0 || !self.window) return super.accessibilityActivationPoint;
    CGPoint point = [self convertPoint:self.titleLabel.center toView:self.window];
    return [self.window convertPoint:point toCoordinateSpace:self.window.screen.coordinateSpace];
}
- (void)pressInput { [self setPressed:YES]; }
- (void)releaseInput { [self setPressed:NO]; }
@end

@interface AKGamepadStick : UIControl
@property(nonatomic, copy) NSString *element;
@property(nonatomic, readonly) CGPoint position;
// The floating arrangement: the ring comes back under the thumb that presses its half of the
// screen instead of staying where the layout put it.
@property(nonatomic) BOOL floating;
@property(nonatomic) CGFloat idleAlpha, activeAlpha;
@property(nonatomic, readonly) BOOL held;
// The movement stick also arms an auto-run: push it forward and hold, a lock appears; keep
// pushing and it lights up; lift the finger then and the character runs until the stick is
// touched again. Every stage is cancelled by letting go early, by touching the stick and by
// -reset, so a lost touch cannot leave a run on.
@property(nonatomic) BOOL autoRunAllowed;
@property(nonatomic, copy) void (^autoRunStage)(NSInteger stage);
// A tap that stayed put, reported on lift so the overlay can decide whether it was the second
// of a double tap. Nothing about movement changes: this is measured after the finger is gone,
// and a tap that travelled is not reported at all.
@property(nonatomic, copy, nullable) void (^tapRecognized)(NSTimeInterval time);
- (void)pollAutoRun:(NSTimeInterval)now;
- (void)reset;
@end
// The tap a stick button is recognised from: the same distance the trackpad calls a tap, and a
// finger that is not dragged in between. The window is short enough that two deliberate taps
// fit in it and long enough that a normal double tap does.
static const CGFloat AKStickTapTravel = 8;
static const NSTimeInterval AKStickTapDuration = 0.35;
static const NSTimeInterval AKStickDoubleTapInterval = 0.32;
// A stick button is a press, not a hold: it is released by itself after this, by a lifecycle
// exit, or by leaving the arrangement, whichever comes first.
static const NSTimeInterval AKStickButtonHold = 0.12;
static const NSTimeInterval AKAutoRunHold = 2;
static const CGFloat AKAutoRunArm = 60;
@implementation AKGamepadStick {
    UIView *_knob;
    NSTimeInterval _forwardSince;
    NSInteger _autoStage;
    BOOL _autoRunning, _stoppedRun;
    // The tap in progress, in the units a tap is judged by: where it started, when, and how far
    // it has travelled since.
    NSTimeInterval _tapStarted;
    CGPoint _tapLast;
    CGFloat _tapTravel;
    BOOL _tapMoved;
}
- (void)setAutoStage:(NSInteger)stage {
    if (_autoStage == stage) return;
    _autoStage = stage;
    if (self.autoRunStage) self.autoRunStage(stage);
}
- (BOOL)pushedForward { return _position.y >= 0.85 && fabs(_position.x) <= 0.4; }
- (void)pollAutoRun:(NSTimeInterval)now {
    if (!_autoRunAllowed || !_held || _autoStage != 0) return;
    if (![self pushedForward]) { _forwardSince = 0; return; }
    if (_forwardSince == 0) _forwardSince = now;
    else if (now - _forwardSince >= AKAutoRunHold) [self setAutoStage:1];
}
- (void)trackAutoRun:(UITouch *)touch {
    if (!_autoRunAllowed) return;
    if (_autoStage == 0) { [self pollAutoRun:touch.timestamp]; return; }
    if (_autoStage == 1 || _autoStage == 2) {
        CGFloat scale = self.superview.transform.d > 0 ? self.superview.transform.d : 1;
        BOOL above = [touch locationInView:self].y < -AKAutoRunArm / scale;
        [self setAutoStage:above ? 2 : 1];
    }
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.exclusiveTouch = NO;
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.48];
        self.layer.borderWidth = 1; self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        _knob = [UIView new]; _knob.userInteractionEnabled = NO;
        _knob.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.55]; [self addSubview:_knob];
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat diameter = MIN(self.bounds.size.width,self.bounds.size.height);
    self.layer.cornerRadius = diameter/2;
    _knob.bounds = CGRectMake(0,0,diameter*0.42,diameter*0.42); _knob.layer.cornerRadius = diameter*0.21;
    _knob.center = CGPointMake(self.bounds.size.width/2 + _position.x*diameter*0.27,
                               self.bounds.size.height/2 - _position.y*diameter*0.27);
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return hypot(point.x-self.bounds.size.width/2,point.y-self.bounds.size.height/2) <= MIN(self.bounds.size.width,self.bounds.size.height)/2;
}
- (void)updatePosition:(CGPoint)position {
    if (CGPointEqualToPoint(_position,position)) return;
    _position = position; [self setNeedsLayout]; [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    UIView *ring = self.superview;
    _held = YES;
    _forwardSince = 0;
    _stoppedRun = _autoRunning;
    _tapStarted = touch.timestamp;
    _tapLast = [touch locationInView:self];
    _tapTravel = 0;
    _tapMoved = NO;
    if (_autoRunning) { _autoRunning = NO; [self setAutoStage:0]; }
    if (_floating && ring.superview) {
        ring.center = [touch locationInView:ring.superview];
        ring.alpha = _activeAlpha > 0 ? _activeAlpha : 1;
    }
    [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self],self.bounds.size)]; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    CGPoint point = [touch locationInView:self];
    _tapTravel += hypot(point.x - _tapLast.x, point.y - _tapLast.y);
    _tapLast = point;
    // A finger that leaves the tap's circle is steering, not tapping: the pending tap is gone
    // for good, so a drag can never become a stick button on the way back.
    if (_tapTravel > AKStickTapTravel) _tapMoved = YES;
    [self updatePosition:AKTouchGamepadStickPosition(point,self.bounds.size)];
    [self trackAutoRun:touch];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    _held = NO;
    BOOL tap = !_tapMoved && _tapTravel <= AKStickTapTravel && touch &&
        isfinite(touch.timestamp) && isfinite(_tapStarted) &&
        touch.timestamp >= _tapStarted && touch.timestamp - _tapStarted <= AKStickTapDuration;
    if (_autoStage == 2 && _autoRunAllowed) {
        // Confirmed: the run stays on with the stick held forward, and the ring goes away.
        _autoRunning = YES;
        [self setAutoStage:3];
        [self updatePosition:CGPointMake(0, 1)];
        [self fadeOut];
        return;
    }
    [self reset]; [self fadeOut];
    // Reported after the reset, so the tap is judged against a stick that is already let go of:
    // a gesture never depends on the position the tap left behind.
    if (tap && self.tapRecognized) self.tapRecognized(touch.timestamp);
    if (_stoppedRun) { _stoppedRun = NO; return; }
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    _held = NO;
    _tapMoved = YES;   // cancelled is never a tap
    [self reset]; [self fadeOut];
}
- (void)fadeOut { if (_floating) self.superview.alpha = _idleAlpha > 0 ? _idleAlpha : 0.02; }
- (void)reset {
    // Every reset is a release: the overlay resets on settings, on the keyboard and when the
    // controls hide, and a stick that kept _held would refuse the next finger.
    _held = NO; _autoRunning = NO; _forwardSince = 0; _stoppedRun = NO;
    [self setAutoStage:0];
    [self updatePosition:CGPointZero];
}
@end

@interface AKGamepadOverlay : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, readonly) NSDictionary<NSString *,AKGamepadButton *> *buttons;
@property(nonatomic, readonly) AKGamepadStick *leftStick;
@property(nonatomic, readonly) AKGamepadStick *rightStick;
@property(nonatomic, readonly) AKGamepadLayout *preferences;
@property(nonatomic) BOOL controlsVisible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, readonly) BOOL editing;
@property(nonatomic, copy) void (^configurationChanged)(void);
// The stick buttons and the ability zones, told to the manager as presses and releases it
// counts. Everything about what a press means lives on the manager side; this side only knows
// which surface was touched.
@property(nonatomic, copy, nullable) void (^elementPress)(NSString *element, BOOL pressed, NSString *control, NSString *reason);
// Whether the controller on the other end of this overlay has a stick button. Apple's
// virtual controller does not (measured: its extended profile carries no stick-button
// element at all), so on it the gesture is refused rather than pretended.
@property(nonatomic) BOOL stickButtonsAvailable;
- (void)reset;
- (void)toggleSettings;
- (void)finishConfiguration;
- (void)reloadLayout;
- (void)releaseTransientInput:(NSString *)reason;
@end
// The floating arrangement's own geometry, in fractions of the overlay. Each thumb owns a
// half of the screen, and the corner beyond the camera stick is the jump. Nothing here knows
// about any add-on: areas reserved for the game or for someone's installed buttons come from
// the saved layout, so an add-on can never define this interface.
static const CGFloat AKFloatIdleAlpha = 0.02;
static const CGFloat AKFloatJumpRadius = 0.16;
static const CGFloat AKFloatLeftMinX = 0.10, AKFloatLeftMaxX = 0.42;
static const CGFloat AKFloatLeftMinY = 0.42, AKFloatLeftLowY = 0.86;
static const CGFloat AKFloatRightMinX = 0.64, AKFloatRightMinY = 0.25, AKFloatRightMaxY = 0.92;
@implementation AKGamepadOverlay {
    NSDictionary<NSString *,UIView *> *_items;
    NSDictionary<NSString *,AKGamepadButton *> *_slots;
    AKGamepadButton *_jumpButton;
    NSMutableDictionary<NSString *,NSValue *> *_dragOrigins;
    UIView *_settings;
    UIButton *_editDone;
    UILabel *_hint;
    UISwitch *_editSwitch, *_hapticsSwitch, *_overlaySwitch, *_swapShouldersSwitch, *_sticksOnlySwitch;
    UISwitch *_floatingSwitch, *_simpleSwitch, *_stickButtonsSwitch;
    UIButton *_addZoneButton, *_clearZoneButton;
    // The ability zones on screen, in the order the layout lists them.
    NSMutableArray<AKGamepadButton *> *_zoneButtons;
    // The double tap: when each stick was last tapped, and the one stick button that may be held
    // at a time, with the timer that lets it go.
    NSTimeInterval _leftTap, _rightTap;
    NSString *_stickButtonElement;
    NSTimer *_stickButtonTimer;
    UIStackView *_settingsColumns;
    NSArray<UISlider *> *_sliders;
    NSArray<UILabel *> *_values;
    CAShapeLayer *_editGrid, *_editAxes;
    // A touch that belongs to a stick already held, and must not become a click on the game.
    UIView *_sink;
    UIView *_autoLock;
    UILabel *_autoBadge;
    __weak UIGestureRecognizer *_hostPinch;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        // Above the guest surface, below the cursor and keyboard toolbar.
        self.layer.zPosition = 99999;
        _preferences = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        _dragOrigins = [NSMutableDictionary new];
        _editGrid = [CAShapeLayer layer]; _editAxes = [CAShapeLayer layer];
        _editGrid.name = @"WolkaraForeverEditGrid"; _editAxes.name = @"WolkaraForeverEditAxes";
        for (CAShapeLayer *layer in @[_editGrid, _editAxes]) {
            layer.fillColor = nil; layer.zPosition = -1; [self.layer addSublayer:layer];
        }
        _editGrid.strokeColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor; _editGrid.lineWidth = 0.5;
        _editAxes.strokeColor = [UIColor.systemYellowColor colorWithAlphaComponent:0.6].CGColor; _editAxes.lineWidth = 1;
        _editAxes.lineDashPattern = @[@4,@4];
        NSArray *elements = @[GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,
            GCInputLeftShoulder,GCInputLeftTrigger,GCInputRightTrigger,GCInputRightShoulder,
            GCInputButtonMenu,@"dpad.up",@"dpad.right",@"dpad.down",@"dpad.left"];
        NSArray *titles = @[@"A",@"B",@"X",@"Y",@"LB",@"LT",@"RT",@"RB",@"+",@"↑",@"→",@"↓",@"←"];
        NSMutableDictionary *buttons = [NSMutableDictionary new];
        NSMutableDictionary *slots = [NSMutableDictionary new];
        UIView *left = [UIView new], *right = [UIView new];
        left.multipleTouchEnabled = right.multipleTouchEnabled = YES;
        [self addSubview:left]; [self addSubview:right];
        for (NSUInteger i=0; i<elements.count; i++) {
            // The slot is where the control sits and what it is called; the element is what it
            // sends to the game, which the player may have changed in the layout.
            AKGamepadButton *button = [AKGamepadButton new];
            button.slot = elements[i];
            button.element = [_preferences elementForSlot:elements[i]];
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.accessibilityLabel = AKHostLocalizedFormat(@"touch.gamepad.button", elements[i]);
            button.accessibilityIdentifier = [@"tolkara.gamepad." stringByAppendingString:elements[i]];
            buttons[button.element] = button;
            slots[button.slot] = button;
            [(i<4 ? right : i>=9 ? left : self) addSubview:button];
        }
        _buttons = buttons;
        _slots = slots;
        _jumpButton = slots[GCInputButtonA];
        _leftStick = [AKGamepadStick new]; _rightStick = [AKGamepadStick new];
        _leftStick.element = GCInputLeftThumbstick; _rightStick.element = GCInputRightThumbstick;
        _leftStick.accessibilityLabel = AKHostLocalized(@"touch.gamepad.leftStick");
        _rightStick.accessibilityLabel = AKHostLocalized(@"touch.gamepad.rightStick");
        _leftStick.accessibilityIdentifier = @"tolkara.gamepad.leftStick"; _rightStick.accessibilityIdentifier = @"tolkara.gamepad.rightStick";
        [left addSubview:_leftStick]; [right addSubview:_rightStick];
        _items = @{@"left":left,@"right":right,@"LB":slots[GCInputLeftShoulder],@"LT":slots[GCInputLeftTrigger],
            @"RB":slots[GCInputRightShoulder],@"RT":slots[GCInputRightTrigger],@"menu":slots[GCInputButtonMenu]};
        for (NSString *name in _items) {
            UIView *item = _items[name]; item.accessibilityIdentifier = [@"wolkaraforever.layout." stringByAppendingString:name];
            // Retain button identifiers used by input tests and accessibility.
            if ([item isKindOfClass:AKGamepadButton.class]) item.accessibilityIdentifier = [@"tolkara.gamepad." stringByAppendingString:((AKGamepadButton *)item).element];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
            pan.delegate = self; [item addGestureRecognizer:pan];
        }
        _editDone = [UIButton buttonWithType:UIButtonTypeSystem];
        [_editDone setTitle:AKHostLocalized(@"touch.gamepad.doneEditing") forState:UIControlStateNormal];
        _editDone.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        _editDone.tintColor = UIColor.systemYellowColor; _editDone.layer.cornerRadius = 14;
        _editDone.accessibilityIdentifier = @"wolkaraforever.layout.done";
        [_editDone addTarget:self action:@selector(finishConfiguration) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_editDone];
        _hint = [UILabel new]; _hint.text = AKHostLocalized(@"touch.gamepad.dragHint");
        _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _hint.textColor = UIColor.whiteColor; _hint.textAlignment = NSTextAlignmentCenter;
        _hint.userInteractionEnabled = NO; [self addSubview:_hint];
        _sink = [UIView new];
        [self addSubview:_sink];
        _autoLock = [UIView new]; _autoLock.userInteractionEnabled = NO; _autoLock.hidden = YES;
        _autoLock.accessibilityIdentifier = @"wolkaraforever.controls.autorunLock";
        _autoLock.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7];
        _autoLock.layer.cornerRadius = 24; _autoLock.layer.borderWidth = 1;
        _autoLock.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        UIImageView *lockImage = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
        lockImage.tintColor = UIColor.whiteColor; lockImage.frame = CGRectMake(12, 12, 24, 24);
        lockImage.contentMode = UIViewContentModeScaleAspectFit;
        [_autoLock addSubview:lockImage];
        [self addSubview:_autoLock];
        _autoBadge = [UILabel new]; _autoBadge.userInteractionEnabled = NO; _autoBadge.hidden = YES;
        _autoBadge.accessibilityIdentifier = @"wolkaraforever.controls.autorun";
        _autoBadge.text = AKHostLocalized(@"touch.autorun"); _autoBadge.textAlignment = NSTextAlignmentCenter;
        _autoBadge.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _autoBadge.textColor = UIColor.whiteColor;
        _autoBadge.backgroundColor = [UIColor colorWithRed:0.1 green:0.45 blue:0.55 alpha:0.8];
        _autoBadge.layer.cornerRadius = 12; _autoBadge.clipsToBounds = YES;
        [self addSubview:_autoBadge];
        __weak AKGamepadOverlay *weakOverlay = self;
        _leftStick.autoRunStage = ^(NSInteger stage) { [weakOverlay showAutoRun:stage]; };
        _zoneButtons = [NSMutableArray new];
        // A tap reports itself on lift; whether it was the second of a double tap is decided
        // here, where the two sticks' times can be compared with one another.
        _leftStick.tapRecognized = ^(NSTimeInterval time) {
            AKGamepadOverlay *overlay = weakOverlay;
            if (overlay) [overlay stickTapped:overlay->_leftStick at:time];
        };
        _rightStick.tapRecognized = ^(NSTimeInterval time) {
            AKGamepadOverlay *overlay = weakOverlay;
            if (overlay) [overlay stickTapped:overlay->_rightStick at:time];
        };
        // Common modes, because the guest drives the main run loop in modes of its own while it
        // runs; a default-mode timer would wait for the game to return to the default mode.
        __weak AKGamepadOverlay *weakSelf = self;
        NSTimer *idle = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            AKGamepadOverlay *overlay = weakSelf;
            if (!overlay) { [timer invalidate]; return; }
            [overlay hideIdleRings];
        }];
        [NSRunLoop.mainRunLoop addTimer:idle forMode:NSRunLoopCommonModes];
        // The launcher writes the same dictionary the settings panel does, so a change from
        // either side has to reach the arrangement that is on screen.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(layoutDidChange:)
                                                   name:AKGamepadLayoutDidChangeNotification
                                                 object:NSUserDefaults.standardUserDefaults];
        [self syncAbilityZones];
        [self updateAppearance];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_stickButtonTimer invalidate];
}
- (BOOL)configuring { return _settings != nil || _editing; }

#pragma mark - Stick buttons (L3/R3)

// Two taps on the same stick, each one that stayed put, inside the window: that is the stick's
// own button, pressed for a moment. One tap is nothing - it is how a thumb lands on the ring
// before steering - and a drag is never a tap at all, which is the rule that keeps this away
// from the camera.
- (void)stickTapped:(AKGamepadStick *)stick at:(NSTimeInterval)time {
    NSTimeInterval *last = stick == _leftStick ? &_leftTap : &_rightTap;
    BOOL wanted = _preferences.stickButtonsEnabled && !self.configuring && _controlsVisible;
    if (wanted && !self.stickButtonsAvailable) {
        *last = 0;
        AKTouchControllerLog(AKTouchControllerEventGesture, @"refused",
                             @{@"control": stick == _leftStick ? @"leftStick" : @"rightStick",
                               @"reason": @"unsupported"});
        return;
    }
    if (!wanted || !isfinite(time)) {
        *last = 0;
        AKTouchControllerLog(AKTouchControllerEventGesture, @"refused",
                             @{@"control": stick == _leftStick ? @"leftStick" : @"rightStick",
                               @"reason": wanted ? @"not-visible" : @"disabled"});
        return;
    }
    if (*last > 0 && time >= *last && time - *last <= AKStickDoubleTapInterval) {
        *last = 0;
        [self pressStickButtonFor:stick];
        return;
    }
    *last = time;
    AKTouchControllerLog(AKTouchControllerEventGesture, @"armed",
                         @{@"control": stick == _leftStick ? @"leftStick" : @"rightStick"});
}
- (void)pressStickButtonFor:(AKGamepadStick *)stick {
    // The element is the stick's own click, which is the button a controller calls L3 or R3.
    NSString *element = AKGamepadStickButtonElement(stick.element);
    if (!element.length) return;
    AKTouchControllerLog(AKTouchControllerEventGesture, @"recognized",
                         @{@"control": stick == _leftStick ? @"leftStick" : @"rightStick",
                           @"element": AKGamepadElementToken(element)});
    if (self.elementPress) self.elementPress(element, YES, @"stickButton", @"gesture");
    [_stickButtonTimer invalidate];
    // One at a time: a second stick button replaces the first, and the first is released first.
    if (_stickButtonElement.length && ![_stickButtonElement isEqualToString:element])
        [self releaseStickButton:@"replaced"];
    _stickButtonElement = element;
    __weak AKGamepadOverlay *weakSelf = self;
    _stickButtonTimer = [NSTimer timerWithTimeInterval:AKStickButtonHold repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        AKGamepadOverlay *overlay = weakSelf;
        if (overlay) [overlay releaseStickButton:@"expired"];
    }];
    [NSRunLoop.mainRunLoop addTimer:_stickButtonTimer forMode:NSRunLoopCommonModes];
}
// Exactly one release for every press: this is the only place the stick button is let go of,
// whether by its own timer, by a lifecycle exit or by the next gesture.
- (void)releaseStickButton:(NSString *)reason {
    [_stickButtonTimer invalidate]; _stickButtonTimer = nil;
    NSString *element = _stickButtonElement;
    _stickButtonElement = nil;
    if (!element.length) return;
    if (self.elementPress) self.elementPress(element, NO, @"stickButton", reason ?: @"expired");
}
- (void)releaseTransientInput:(NSString *)reason {
    [self releaseStickButton:reason];
    for (AKGamepadButton *zone in _zoneButtons) [zone releaseInput];
}

#pragma mark - Ability zones

- (NSString *)titleForElement:(NSString *)element {
    static NSDictionary *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{GCInputButtonA:@"A", GCInputButtonB:@"B", GCInputButtonX:@"X", GCInputButtonY:@"Y",
                   GCInputLeftShoulder:@"LB", GCInputLeftTrigger:@"LT", GCInputRightTrigger:@"RT",
                   GCInputRightShoulder:@"RB", GCInputButtonMenu:@"+"};
    });
    return titles[element] ?: @"";
}
// The zones on screen are rebuilt from the layout whenever it changes, so there is one source
// of truth for what they are and where they sit: the saved dictionary.
- (void)syncAbilityZones {
    NSArray<NSDictionary<NSString *, id> *> *zones = _preferences.abilityZones;
    while (_zoneButtons.count > zones.count) {
        [_zoneButtons.lastObject removeFromSuperview];
        [_zoneButtons removeLastObject];
    }
    for (NSUInteger index = 0; index < zones.count; index++) {
        AKGamepadButton *zone = index < _zoneButtons.count ? _zoneButtons[index] : nil;
        if (!zone) {
            zone = [AKGamepadButton new];
            zone.slot = nil;
            [zone addTarget:self action:@selector(zoneChanged:) forControlEvents:UIControlEventValueChanged];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
            pan.delegate = self; [zone addGestureRecognizer:pan];
            UITapGestureRecognizer *choose = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chooseZoneElement:)];
            choose.delegate = self; [zone addGestureRecognizer:choose];
            [self addSubview:zone];
            [_zoneButtons addObject:zone];
        }
        zone.element = zones[index][@"element"];
        [zone setTitle:[self titleForElement:zone.element] forState:UIControlStateNormal];
        zone.accessibilityIdentifier = [@"wolkaraforever.abilityZone." stringByAppendingFormat:@"%lu",(unsigned long)(index+1)];
        zone.accessibilityLabel = AKHostLocalizedFormat(@"touch.zone.button", [self titleForElement:zone.element]);
        zone.accessibilityHint = AKHostLocalized(@"touch.zone.hint");
        zone.accessibilityValue = self.editing ? AKHostLocalized(@"touch.zone.editing") : nil;
        [self updateZoneMenuForZone:zone atIndex:index];
    }
    [self updateAppearance];
    [self setNeedsLayout];
}
- (NSString *)nextZoneElement {
    NSArray<NSString *> *elements = AKLayoutZoneElements();
    NSMutableSet<NSString *> *used = [NSMutableSet new];
    for (NSDictionary *zone in _preferences.abilityZones) [used addObject:zone[@"element"]];
    for (NSString *element in elements) if (![used containsObject:element]) return element;
    // Every element is already on a zone: the first one again, which is a second surface for
    // the same button and is accounted for the same way as any other duplicate.
    return elements.firstObject;
}
- (void)updateZoneMenuForZone:(AKGamepadButton *)zone atIndex:(NSUInteger)index {
    // Editing a zone changes which button it sends. It is a menu on the zone itself, opened by
    // a tap while the editor is open; outside the editor the same tap presses the button.
    if (!self.editing) { zone.menu = nil; zone.showsMenuAsPrimaryAction = NO; return; }
    __weak AKGamepadOverlay *weakSelf = self;
    NSMutableArray<UIAction *> *actions = [NSMutableArray new];
    for (NSString *element in AKLayoutZoneElements()) {
        NSString *title = [self titleForElement:element];
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil
                                              handler:^(__unused UIAction *chosen) {
            AKGamepadOverlay *overlay = weakSelf;
            if (!overlay) return;
            [overlay->_preferences setAbilityZoneElement:element atIndex:index];
            [overlay->_preferences save];
            [overlay syncAbilityZones];
        }];
        action.state = [element isEqualToString:zone.element] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    zone.menu = [UIMenu menuWithTitle:AKHostLocalized(@"touch.zone.choose") children:actions];
    zone.showsMenuAsPrimaryAction = YES;
}
- (void)zoneChanged:(AKGamepadButton *)zone {
    NSUInteger index = [_zoneButtons indexOfObject:zone];
    if (index == NSNotFound || !self.elementPress) return;
    // Nothing is sent while a surface of ours is open: the same rule every other control
    // follows. In the editor a zone is edited, not pressed.
    if (self.configuring) {
        AKTouchControllerLog(AKTouchControllerEventPress, @"refused",
                             @{@"control": @"abilityZone", @"element": AKGamepadElementToken(zone.element), @"reason": @"configuring"});
        return;
    }
    // The zone's own name is where it is in the list, not what it does: the element travels
    // beside it, so a log line never has to guess which button a zone was pointing at.
    NSString *control = [NSString stringWithFormat:@"zone%lu", (unsigned long)(index + 1)];
    self.elementPress(zone.element, zone.pressed, control, zone.pressed ? @"touch" : @"lifted");
}
- (void)chooseZoneElement:(UITapGestureRecognizer *)tap {
    (void)tap;
    // The menu is on the zone (showsMenuAsPrimaryAction while editing); this recognizer exists
    // only so a tap in the editor is not also a press, which -zoneChanged: already refuses.
}
- (void)addAbilityZoneTapped {
    NSUInteger count = _preferences.abilityZones.count;
    NSString *element = [self nextZoneElement];
    CGFloat x = 0.44 + 0.06 * (CGFloat)count;
    if ([_preferences addAbilityZoneForElement:element atX:x y:0.47]) {
        [_preferences save];
        [self syncAbilityZones];
        [self updateSettingsZoneCount];
    }
}
- (void)clearAbilityZonesTapped {
    [_preferences clearAbilityZones];
    [_preferences save];
    [self syncAbilityZones];
    [self updateSettingsZoneCount];
}
- (void)updateSettingsZoneCount {
    if (!_addZoneButton) return;
    NSUInteger count = _preferences.abilityZones.count;
    _addZoneButton.enabled = count < 6;
    _clearZoneButton.enabled = count > 0;
    _clearZoneButton.accessibilityValue = AKHostLocalizedFormat(@"touch.settings.abilityZones.count", count);
}

#pragma mark - The arrangement, from the settings panel

- (void)simpleLayoutChanged:(UISwitch *)sender {
    [self reset];
    [_preferences setModeName:sender.on ? AKLayoutModeSimple : AKLayoutModeFull];
    [_preferences save];
    [self updateSwapShouldersRow];
    [self updateAppearance];
}
// The trigger order is only in force where triggers are drawn.
- (void)updateSwapShouldersRow {
    if (!_swapShouldersSwitch) return;
    BOOL simple = _preferences.mode == AKGamepadLayoutModeSimple;
    _swapShouldersSwitch.enabled = !simple;
    _swapShouldersSwitch.accessibilityHint = simple ? AKHostLocalized(@"touch.settings.outerTriggers.simple") : nil;
}
- (void)stickButtonsChanged:(UISwitch *)sender {
    [self releaseStickButton:@"disabled"];
    _preferences.stickButtonsEnabled = sender.on;
    [_preferences save];
}
- (void)layoutDidChange:(NSNotification *)notification {
    (void)notification;
    [self reloadLayout];
}
- (void)reloadLayout {
    _preferences = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    [self releaseStickButton:@"layout"];
    [self syncAbilityZones];
    [self updateAppearance];
    [self setNeedsLayout];
}
- (void)setControlsVisible:(BOOL)visible { _controlsVisible = visible; [self updateAppearance]; }
- (void)updateAppearance {
    self.hidden = !_controlsVisible && !self.configuring;
    for (UIView *item in _items.allValues) {
        item.hidden = !_controlsVisible && !self.configuring;
        item.alpha = _editing ? MAX(0.5,_preferences.opacity) : _preferences.opacity;
        item.layer.borderWidth = _editing ? 1 : ([item isKindOfClass:AKGamepadButton.class] ? 1 : 0);
        item.layer.borderColor = (_editing ? UIColor.systemYellowColor : [UIColor colorWithWhite:1 alpha:0.3]).CGColor;
    }
    // Sticks only keeps A, under the camera stick, as the jump: the game's gamepad mode
    // binds A to Jump, and a phone game always has its jump there. It is a mobile-interface
    // arrangement only: Standard keeps every button wherever its layout put it.
    BOOL sticksOnly = _preferences.sticksOnly && !self.configuring && AKInterfaceModeIsMobile();
    NSArray<UIView *> *placed = _items.allValues;
    for (AKGamepadButton *button in _buttons.allValues) {
        BOOL jump = [button.slot isEqualToString:GCInputButtonA];
        if (sticksOnly) button.hidden = !jump;
        else if (![placed containsObject:button]) button.hidden = NO;
        if (jump) [button setTitle:sticksOnly ? AKHostLocalized(@"touch.gamepad.jump") : @"A" forState:UIControlStateNormal];
    }
    // Simple is the same layout with fewer controls drawn: both sticks, the four face buttons,
    // the two shoulders and the menu. The triggers and the D-pad sectors are not there, and
    // nothing is deleted from the layout - turning Simple off draws them again exactly where
    // they were saved. Sticks-only wins where both apply, because it is the smaller arrangement.
    if (_preferences.mode == AKGamepadLayoutModeSimple && !sticksOnly) {
        for (NSString *slot in @[GCInputLeftTrigger, GCInputRightTrigger,
                                 @"dpad.up", @"dpad.right", @"dpad.down", @"dpad.left"]) {
            AKGamepadButton *button = _slots[slot];
            if (button) button.hidden = YES;
        }
    }
    // An enabled UIControl is needed for its own pan recognizer to receive
    // touches. The manager suppresses game input throughout configuration.
    for (AKGamepadButton *button in _buttons.allValues) button.enabled = !self.configuring || _editing;
    for (AKGamepadButton *zone in _zoneButtons) {
        zone.hidden = !_controlsVisible && !self.configuring;
        zone.alpha = _editing ? MAX(0.5,_preferences.opacity) : _preferences.opacity;
        zone.enabled = !self.configuring || _editing;
    }
    _leftStick.enabled = _rightStick.enabled = !self.configuring;
    _editDone.hidden = _hint.hidden = !_editing;
    _editGrid.hidden = _editAxes.hidden = !_editing;
    BOOL floating = [self floatingActive];
    // Leaving the floating arrangement - the switch, the settings, a mode change - lets go of
    // every stick, so nothing stays held and no auto-run keeps going.
    if (!floating && (_leftStick.floating || _rightStick.floating)) [self reset];
    _leftStick.floating = _rightStick.floating = floating;
    _leftStick.autoRunAllowed = floating;
    _leftStick.activeAlpha = _rightStick.activeAlpha = _preferences.opacity;
    _leftStick.idleAlpha = _rightStick.idleAlpha = AKFloatIdleAlpha;
    if (floating && !_leftStick.held) _items[@"left"].alpha = AKFloatIdleAlpha;
    if (floating && !_rightStick.held) _items[@"right"].alpha = AKFloatIdleAlpha;
    if (!floating) { _autoLock.hidden = YES; _autoBadge.hidden = YES; }
    [self setNeedsLayout];
}
// Whether the floating arrangement is the one on screen. It is a mobile-interface arrangement,
// so AKInterfaceModeIsMobile() is the only thing that decides it: a hand-edited or saved
// preference cannot turn it on in Standard.
- (BOOL)floatingActive {
    return AKInterfaceModeIsMobile() && _preferences.floatingSticks && _preferences.sticksOnly &&
        _controlsVisible && !self.configuring;
}
- (void)showAutoRun:(NSInteger)stage {
    UIView *ring = _items[@"left"];
    CGFloat stickSize = 104 * ring.transform.d;
    _autoLock.frame = CGRectMake(ring.center.x - 24, ring.center.y - stickSize / 2 - AKAutoRunArm - 24, 48, 48);
    _autoLock.hidden = !(stage == 1 || stage == 2);
    _autoLock.backgroundColor = stage == 2 ? [UIColor colorWithRed:0.85 green:0.65 blue:0.15 alpha:0.9]
                                           : [UIColor colorWithWhite:0.1 alpha:0.7];
    _autoLock.transform = stage == 2 ? CGAffineTransformMakeScale(1.15, 1.15) : CGAffineTransformIdentity;
    CGSize size = self.bounds.size;
    _autoBadge.frame = CGRectMake(size.width * 0.12, size.height * 0.80, 96, 26);
    _autoBadge.hidden = stage != 3;
    if (stage == 3) AKGamepadLog(@"touch gamepad: auto-run on");
}
// A stick that believes it is held with no finger on it would steer for ever: let it go, and
// say so once, so a lost touch is visible in a device log rather than felt as a drift.
- (void)hideIdleRings {
    [_leftStick pollAutoRun:NSProcessInfo.processInfo.systemUptime];
    if (![self floatingActive]) return;
    NSArray *pairs = @[@[_leftStick, @"left"], @[_rightStick, @"right"]];
    for (NSArray *pair in pairs) {
        AKGamepadStick *stick = pair[0]; UIView *ring = _items[pair[1]];
        if (!stick.held && ring.alpha > AKFloatIdleAlpha + 0.01) {
            AKGamepadLog(@"touch gamepad: %@ ring visible (alpha %.2f) with no finger on it; hidden", pair[1], ring.alpha);
            ring.alpha = AKFloatIdleAlpha;
        }
    }
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if ([self floatingActive]) return [self floatingHit:point event:event];
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.configuring) return hit; // Editing/settings must never click the game.
    if (hit == self || hit == _items[@"left"] || hit == _items[@"right"]) {
        AKGamepadButton *jump = [self jumpAround:point event:event];
        return jump;
    }
    return hit;
}
- (BOOL)stickHeld:(AKGamepadStick *)stick event:(UIEvent *)event {
    if (!stick.held) return NO;
    if (!event) return YES;
    for (UITouch *touch in event.allTouches)
        if (touch.view == stick && touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return YES;
    AKGamepadLog(@"touch gamepad: %@ stick was held with no finger on it; released", stick == _leftStick ? @"left" : @"right");
    [stick cancelTrackingWithEvent:nil];
    return NO;
}
// A press in a thumb's half is that stick's; the corner beyond the camera stick is the jump;
// everywhere else - including any area the player reserved - is not ours, so the touch goes on
// to whatever is underneath. Nothing here forwards a touch by hand: returning nil is the app's
// own hit-testing doing it.
- (UIView *)floatingHit:(CGPoint)point event:(UIEvent *)event {
    CGSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0) return nil;
    CGFloat h = size.height;
    CGFloat fx = point.x / size.width, fy = point.y / h;
    // The areas the player reserved come first and win outright: a touch there belongs to the
    // game, or to whatever was installed in it.
    for (NSDictionary<NSString *, NSNumber *> *area in _preferences.keepFree) {
        CGFloat ax = area[@"x"].doubleValue, ay = area[@"y"].doubleValue;
        CGFloat aw = area[@"w"].doubleValue, ah = area[@"h"].doubleValue;
        if (fx >= ax && fx <= ax + aw && fy >= ay && fy <= ay + ah) return nil;
    }
    // An ability zone is the player's own surface and sits inside a thumb's half, so it is
    // answered before the halves are: a zone under the camera thumb is still the zone.
    for (AKGamepadButton *zone in _zoneButtons) {
        if (zone.hidden) continue;
        if (CGRectContainsPoint(zone.frame, point)) return zone;
    }
    CGFloat corner = hypot(size.width - point.x, h - point.y);
    if (corner <= AKFloatJumpRadius * h) {
        AKGamepadButton *jump = _jumpButton;
        return jump.enabled ? jump : nil;
    }
    if (fx <= AKFloatLeftMaxX && (fy >= AKFloatLeftLowY || (fx >= AKFloatLeftMinX && fy >= AKFloatLeftMinY)))
        return [self stickHeld:_leftStick event:event] ? _sink : _leftStick;
    if (fx >= AKFloatRightMinX && fy >= AKFloatRightMinY && fy <= AKFloatRightMaxY)
        return [self stickHeld:_rightStick event:event] ? _sink : _rightStick;
    return nil;
}
// With sticks only, the jump is the one button under the camera stick, and a thumb that is
// steering does not aim: it lands in the gap next to the stick or just under the drawn ring,
// and that touch used to fall through to the game as a camera drag. B, X and Y are hidden in
// this mode, so the lower half of the space around the camera stick, out to 1.4 times the
// ring, is the jump's. Each touch caught this way is logged once, with how far it was from
// the stick, so a device run shows whether the drawn ring was too small.
static const CGFloat AKJumpReachOuter = 146, AKJumpReachInner = 50, AKJumpReachAngle = M_PI / 3;
- (AKGamepadButton *)jumpAround:(CGPoint)point event:(UIEvent *)event {
    if (!AKInterfaceModeIsMobile() || !_preferences.sticksOnly || self.configuring) return nil;
    AKGamepadButton *jump = _jumpButton;
    UIView *ring = _items[@"right"];
    if (!jump || jump.hidden || !jump.enabled || !ring || ring.hidden) return nil;
    CGPoint local = [self convertPoint:point toView:ring];
    CGFloat dx = local.x - ring.bounds.size.width / 2, dy = local.y - ring.bounds.size.height / 2;
    CGFloat distance = hypot(dx, dy), fromDown = fabs(atan2(dy, dx) - M_PI_2);
    if (distance < AKJumpReachInner || distance > AKJumpReachOuter || fromDown > AKJumpReachAngle) return nil;
    static NSTimeInterval logged;
    if (event && event.timestamp != logged) {
        logged = event.timestamp;
        AKGamepadLog(@"touch gamepad: jump caught %.0f pt from the camera stick, outside its drawn ring", distance);
    }
    return jump;
}
- (CGRect)usableBounds { return UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets); }
- (NSString *)positionName:(NSString *)name {
    if (!_preferences.swapShoulders) return name;
    return @{@"LT":@"LB",@"LB":@"LT",@"RT":@"RB",@"RB":@"RT"}[name] ?: name;
}
- (void)place:(NSString *)name frame:(CGRect)frame baseSize:(CGSize)base safe:(CGRect)safe {
    UIView *item = _items[[self positionName:name]];
    CGRect placed = [_preferences frameForItem:name defaultFrame:frame inBounds:safe];
    item.transform = CGAffineTransformIdentity; item.bounds = (CGRect){CGPointZero,base};
    item.center = CGPointMake(CGRectGetMidX(placed),CGRectGetMidY(placed));
    item.transform = CGAffineTransformMakeScale(placed.size.width/base.width,placed.size.height/base.height);
}
// The same placement without the shoulder swap, for the one arrangement that has nothing to
// swap: Simple draws no triggers, so a "swapped" LB would be a hidden trigger and the shoulder
// would vanish. The control a person presses is named by its slot and placed by its slot.
- (void)placeSlot:(NSString *)slot frame:(CGRect)frame baseSize:(CGSize)base safe:(CGRect)safe {
    // _items is keyed by the *slot* a control sits in ("LB"), not by the element it sends.
    NSString *name = @{GCInputLeftShoulder:@"LB", GCInputRightShoulder:@"RB",
                       GCInputLeftTrigger:@"LT", GCInputRightTrigger:@"RT"}[slot] ?: slot;
    UIView *item = _items[name];
    if (!item) return;
    CGRect placed = [_preferences frameForItem:name defaultFrame:frame inBounds:safe];
    item.transform = CGAffineTransformIdentity; item.bounds = (CGRect){CGPointZero,base};
    item.center = CGPointMake(CGRectGetMidX(placed),CGRectGetMidY(placed));
    item.transform = CGAffineTransformMakeScale(placed.size.width/base.width,placed.size.height/base.height);
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGRect safe = [self usableBounds];
    if (_editing) [self layoutEditGridInBounds:safe];
    CGFloat side = MIN(216*_preferences.frontScale,MIN(safe.size.height-70,safe.size.width/2-12));
    side = MAX(44,side);
    CGFloat w = 56*_preferences.rearScale, h = 44*_preferences.rearScale;
    CGFloat left = CGRectGetMinX(safe)+6, right = CGRectGetMaxX(safe)-6;
    CGFloat bottom = CGRectGetMaxY(safe)-6, top = CGRectGetMinY(safe)+8;
    BOOL floating = [self floatingActive];
    if (!(floating && _leftStick.held))
        [self place:@"left" frame:CGRectMake(left,bottom-side,side,side) baseSize:CGSizeMake(216,216) safe:safe];
    if (!(floating && _rightStick.held))
        [self place:@"right" frame:CGRectMake(right-side,bottom-side,side,side) baseSize:CGSizeMake(216,216) safe:safe];
    _leftStick.frame = _rightStick.frame = CGRectMake(56,56,104,104);
    NSArray *leftNames = @[@"dpad.up",@"dpad.right",@"dpad.down",@"dpad.left"];
    NSArray *rightNames = @[GCInputButtonY,GCInputButtonB,GCInputButtonA,GCInputButtonX];
    for (NSUInteger i=0; i<4; i++) {
        AKGamepadButton *a = _slots[leftNames[i]], *b = _slots[rightNames[i]];
        if (a.sector != (NSInteger)i) a.sector = i;
        if (b.sector != (NSInteger)i) b.sector = i;
        a.frame = b.frame = CGRectMake(0,0,216,216);
    }
    if (_preferences.mode == AKGamepadLayoutModeSimple) {
        // Simple draws no triggers, so its two shoulders take the far corners - where an index
        // finger already rests on a phone held in landscape - and keep their own saved places:
        // moving a shoulder in Simple never moves the one in Full, and the other way round.
        [self placeSlot:GCInputLeftShoulder frame:CGRectMake(left,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
        [self placeSlot:GCInputRightShoulder frame:CGRectMake(right-w,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    } else {
        [self place:@"LT" frame:CGRectMake(left,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
        [self place:@"LB" frame:CGRectMake(left+w+8,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
        [self place:@"RT" frame:CGRectMake(right-w,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
        [self place:@"RB" frame:CGRectMake(right-w*2-8,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    }
    // Ability zones: a circle at the centre the layout saved, kept inside the safe area so a
    // zone dragged to the edge can still be reached and dragged back.
    CGFloat zoneSide = MAX(44,52*_preferences.frontScale);
    NSArray<NSDictionary<NSString *, id> *> *zones = _preferences.abilityZones;
    for (NSUInteger index = 0; index < _zoneButtons.count && index < zones.count; index++) {
        CGFloat fx = [zones[index][@"x"] doubleValue], fy = [zones[index][@"y"] doubleValue];
        CGPoint centre = CGPointMake(CGRectGetMinX(safe) + fx * safe.size.width,
                                     CGRectGetMinY(safe) + fy * safe.size.height);
        CGFloat x = MIN(MAX(centre.x - zoneSide/2,CGRectGetMinX(safe)),CGRectGetMaxX(safe)-zoneSide);
        CGFloat y = MIN(MAX(centre.y - zoneSide/2,CGRectGetMinY(safe)),CGRectGetMaxY(safe)-zoneSide);
        _zoneButtons[index].frame = CGRectMake(x,y,zoneSide,zoneSide);
        _zoneButtons[index].layer.cornerRadius = zoneSide/2;
    }
    // Mobile: the app's toolbar sits at the bottom centre (TouchControls, 44 pt tall and 8 pt
    // up), so the full layout's menu button waits just above it rather than under it.
    // Standard: the menu button stays where the layout has always put it, above the bottom.
    [self place:@"menu" frame:(AKInterfaceModeIsMobile()
            ? CGRectMake(CGRectGetMidX(self.bounds)-22,CGRectGetMaxY(safe)-8-44-8-44,44,44)
            : CGRectMake(CGRectGetMidX(self.bounds)-22,bottom-side+190*side/216-22,44,44))
        baseSize:CGSizeMake(44,44) safe:safe];
    _editDone.frame = CGRectMake(CGRectGetMidX(safe)-70,CGRectGetMinY(safe)+60,140,40);
    _hint.frame = CGRectMake(CGRectGetMidX(safe)-150,CGRectGetMinY(safe)+103,300,22);
    if (_settings) {
        // Mobile: the fixed toolbar sits at the bottom, so the sheet hangs from the top.
        // Standard: it hangs from the bottom, below the toolbar that is at the top.
        // Wide screens use two columns; smaller windows retain a scrollable single column and
        // a fixed Done button.
        BOOL wide = safe.size.width >= 620;
        CGFloat width = MIN(wide ? 700 : 390,safe.size.width-24), height = MIN(wide ? 350 : 470,safe.size.height-68);
        _settingsColumns.axis = wide ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
        _settingsColumns.alignment = wide ? UIStackViewAlignmentTop : UIStackViewAlignmentFill;
        _settingsColumns.distribution = wide ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
        _settings.frame = AKInterfaceModeIsMobile()
            ? CGRectMake(CGRectGetMidX(safe)-width/2,CGRectGetMinY(safe)+8,width,height)
            : CGRectMake(CGRectGetMidX(safe)-width/2,CGRectGetMaxY(safe)-height-8,width,height);
    }
}
- (void)layoutEditGridInBounds:(CGRect)safe {
    // Symmetric spacing about the safe-area center. Layers are visual guides
    // only: they cannot intercept drags or change a saved control position.
    UIBezierPath *grid = [UIBezierPath bezierPath], *axes = [UIBezierPath bezierPath];
    CGFloat x = CGRectGetMidX(safe), y = CGRectGetMidY(safe), step = 24;
    for (NSInteger column = -(NSInteger)floor(safe.size.width / (2*step)); column*step <= safe.size.width/2; column++) {
        CGFloat line = x + column*step;
        [grid moveToPoint:CGPointMake(line,CGRectGetMinY(safe))]; [grid addLineToPoint:CGPointMake(line,CGRectGetMaxY(safe))];
    }
    for (NSInteger row = -(NSInteger)floor(safe.size.height / (2*step)); row*step <= safe.size.height/2; row++) {
        CGFloat line = y + row*step;
        [grid moveToPoint:CGPointMake(CGRectGetMinX(safe),line)]; [grid addLineToPoint:CGPointMake(CGRectGetMaxX(safe),line)];
    }
    [axes moveToPoint:CGPointMake(x,CGRectGetMinY(safe))]; [axes addLineToPoint:CGPointMake(x,CGRectGetMaxY(safe))];
    [axes moveToPoint:CGPointMake(CGRectGetMinX(safe),y)]; [axes addLineToPoint:CGPointMake(CGRectGetMaxX(safe),y)];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _editGrid.frame = _editAxes.frame = self.bounds;
    _editGrid.path = grid.CGPath; _editAxes.path = axes.CGPath;
    [CATransaction commit];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _hostPinch) return YES;
    return _editing;
}
// The camera pinch is the host's, and a pinch that begins on one of our controls is not a
// gesture over the game: the sticks and the jump keep their fingers.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == _hostPinch) return ![touch.view isDescendantOfView:self];
    return YES;
}
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (!AKInterfaceModeIsMobile()) return;
    for (UIGestureRecognizer *gesture in self.superview.gestureRecognizers) {
        if ([gesture isKindOfClass:UIPinchGestureRecognizer.class] && !gesture.delegate) {
            gesture.delegate = self; _hostPinch = gesture;
            AKGamepadLog(@"touch gamepad: the camera pinch ignores fingers on the controls");
        }
    }
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    // An ability zone is dragged like any other control: its place is fractions of the screen,
    // and the layout it belongs to is the one that is in force.
    NSUInteger zone = [_zoneButtons indexOfObject:(AKGamepadButton *)pan.view];
    BOOL isZone = pan.view && [_zoneButtons containsObject:(AKGamepadButton *)pan.view];
    NSString *name = isZone ? [NSString stringWithFormat:@"zone.%lu",(unsigned long)zone]
                            : [_items allKeysForObject:pan.view].firstObject;
    if (!name || !_editing) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        [_dragOrigins setObject:[NSValue valueWithCGRect:pan.view.frame] forKey:name]; [self reset];
    }
    NSValue *origin = _dragOrigins[name];
    if (!origin) return;
    CGRect frame = origin.CGRectValue;
    if (pan.state != UIGestureRecognizerStateCancelled) {
        CGPoint delta = [pan translationInView:self];
        frame.origin.x += delta.x; frame.origin.y += delta.y;
    }
    CGRect safe = [self usableBounds];
    if (isZone) {
        CGFloat fx = safe.size.width > 0 ? (CGRectGetMidX(frame)-CGRectGetMinX(safe))/safe.size.width : 0;
        CGFloat fy = safe.size.height > 0 ? (CGRectGetMidY(frame)-CGRectGetMinY(safe))/safe.size.height : 0;
        [_preferences moveAbilityZoneAtIndex:zone toX:fx y:fy];
    } else {
        [_preferences moveItem:[self positionName:name] toFrame:frame inBounds:safe];
    }
    [self setNeedsLayout]; [self layoutIfNeeded];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [_preferences save]; [_dragOrigins removeObjectForKey:name];
    }
}
- (UILabel *)label:(NSString *)text {
    UILabel *label = [UILabel new]; label.text = text; label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]; label.numberOfLines = 0;
    return label;
}
- (void)toggleSettings {
    if (_settings || _editing) { [self finishConfiguration]; return; }
    // What is on screen may have been changed from the launcher since this overlay was built.
    [self reloadLayout];
    [self reset];
    _settings = [UIView new]; _settings.backgroundColor = [UIColor colorWithRed:.06 green:.08 blue:.11 alpha:1];
    _settings.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _settings.layer.cornerRadius = 20; _settings.layer.borderWidth = 1;
    _settings.layer.borderColor = [UIColor colorWithWhite:1 alpha:.2].CGColor;
    _settings.accessibilityIdentifier = @"wolkaraforever.controls.settings";
    [self addSubview:_settings];
    UIScrollView *scroll = [UIScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_settings addSubview:scroll];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.title")]]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    UIStackView *sizes = [UIStackView new], *options = [UIStackView new];
    sizes.axis = options.axis = UILayoutConstraintAxisVertical; sizes.spacing = 6; options.spacing = 8;
    _settingsColumns = [[UIStackView alloc] initWithArrangedSubviews:@[sizes,options]];
    _settingsColumns.spacing = 24; _settingsColumns.alignment = UIStackViewAlignmentTop;
    [stack addArrangedSubview:_settingsColumns];
    NSMutableArray *sliders = [NSMutableArray new], *values = [NSMutableArray new];
    NSArray *names = @[AKHostLocalized(@"touch.settings.transparency"), AKHostLocalized(@"touch.settings.shoulderSize"),
                       AKHostLocalized(@"touch.settings.stickSize")];
    CGFloat initial[] = {1-_preferences.opacity,_preferences.rearScale,_preferences.frontScale};
    CGFloat min[] = {0,0.8,0.65}, max[] = {0.95,1.5,1.4};
    for (NSUInteger i=0; i<3; i++) {
        UILabel *value = [self label:@""]; [values addObject:value]; [sizes addArrangedSubview:value];
        UISlider *slider = [UISlider new]; slider.tag = i; slider.minimumValue = min[i]; slider.maximumValue = max[i]; slider.value = initial[i];
        slider.accessibilityLabel = names[i]; slider.accessibilityIdentifier = [@"wolkaraforever.controls." stringByAppendingString:@[@"transparency",@"rearScale",@"frontScale"][i]];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [sliders addObject:slider]; [sizes addArrangedSubview:slider];
    }
    _sliders = sliders; _values = values; [self updateValues];
    // A switch for an arrangement Standard does not use would be a control that does
    // nothing, so it exists only where sticks-only does.
    if (AKInterfaceModeIsMobile()) {
        _sticksOnlySwitch = [UISwitch new]; _sticksOnlySwitch.on = _preferences.sticksOnly;
        _sticksOnlySwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.sticksOnly");
        _sticksOnlySwitch.accessibilityIdentifier = @"wolkaraforever.controls.sticksOnly";
        [_sticksOnlySwitch addTarget:self action:@selector(sticksOnlyChanged:) forControlEvents:UIControlEventValueChanged];
        UIStackView *sticksRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.sticksOnly")],_sticksOnlySwitch]];
        sticksRow.axis = UILayoutConstraintAxisHorizontal; sticksRow.alignment = UIStackViewAlignmentCenter;
        [options addArrangedSubview:sticksRow];
        // The floating arrangement belongs to the same interface, so its switch is here too.
        _floatingSwitch = [UISwitch new]; _floatingSwitch.on = _preferences.floatingSticks;
        _floatingSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.floatingSticks");
        _floatingSwitch.accessibilityIdentifier = @"wolkaraforever.controls.floatingSticks";
        [_floatingSwitch addTarget:self action:@selector(floatingChanged:) forControlEvents:UIControlEventValueChanged];
        UIStackView *floatingRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.floatingSticks")],_floatingSwitch]];
        floatingRow.axis = UILayoutConstraintAxisHorizontal; floatingRow.alignment = UIStackViewAlignmentCenter;
        [options addArrangedSubview:floatingRow];
    }
    // Triggers on the outside is a choice about two controls Simple does not draw, so in Simple
    // the row stays where it is and its switch is not usable. A row that vanished and came back
    // would move every row under it; a switch that is greyed says the same thing and stays put.
    _swapShouldersSwitch = [UISwitch new]; _swapShouldersSwitch.on = !_preferences.swapShoulders;
    _swapShouldersSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.outerTriggers");
    _swapShouldersSwitch.accessibilityIdentifier = @"wolkaraforever.controls.swapShoulders";
    [self updateSwapShouldersRow];
    [_swapShouldersSwitch addTarget:self action:@selector(swapShouldersChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *shouldersRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.outerTriggers")],_swapShouldersSwitch]];
    shouldersRow.axis = UILayoutConstraintAxisHorizontal; shouldersRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:shouldersRow];
    _hapticsSwitch = [UISwitch new]; _hapticsSwitch.on = _preferences.hapticsEnabled;
    _hapticsSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.haptics");
    _hapticsSwitch.accessibilityIdentifier = @"wolkaraforever.controls.haptics";
    [_hapticsSwitch addTarget:self action:@selector(hapticsChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *hapticsRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.haptics")],_hapticsSwitch]];
    hapticsRow.axis = UILayoutConstraintAxisHorizontal; hapticsRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:hapticsRow];
    // The optional performance HUD. It is a display preference, not a layout or
    // input one: turning it on does not move, resize or rebind any control.
    _overlaySwitch = [UISwitch new]; _overlaySwitch.on = _preferences.performanceOverlayEnabled;
    _overlaySwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.overlay");
    _overlaySwitch.accessibilityIdentifier = @"wolkaraforever.controls.performanceOverlay";
    [_overlaySwitch addTarget:self action:@selector(overlayChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *overlayRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.overlay.detail")],_overlaySwitch]];
    overlayRow.axis = UILayoutConstraintAxisHorizontal; overlayRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:overlayRow];
    _editSwitch = [UISwitch new]; _editSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.edit");
    _editSwitch.accessibilityIdentifier = @"wolkaraforever.controls.edit";
    [_editSwitch addTarget:self action:@selector(beginEditing:) forControlEvents:UIControlEventValueChanged];
    UIStackView *editRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.edit")],_editSwitch]];
    editRow.axis = UILayoutConstraintAxisHorizontal; editRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:editRow];
    [options addArrangedSubview:[self label:AKHostLocalized(@"touch.settings.edit.detail")]];
    // --- the Touch Controller 2 rows, appended: every row above keeps its place and its name ---
    _simpleSwitch = [UISwitch new]; _simpleSwitch.on = _preferences.mode == AKGamepadLayoutModeSimple;
    _simpleSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.simpleLayout");
    _simpleSwitch.accessibilityHint = AKHostLocalized(@"touch.settings.simpleLayout.hint");
    _simpleSwitch.accessibilityIdentifier = @"wolkaraforever.controls.simpleLayout";
    [_simpleSwitch addTarget:self action:@selector(simpleLayoutChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *simpleRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.simpleLayout")],_simpleSwitch]];
    simpleRow.axis = UILayoutConstraintAxisHorizontal; simpleRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:simpleRow];
    [options addArrangedSubview:[self label:AKHostLocalized(@"touch.settings.simpleLayout.detail")]];
    // A stick button is a gesture, so it is a switch of its own - off, as it has always been.
    _stickButtonsSwitch = [UISwitch new];
    _stickButtonsSwitch.on = _preferences.stickButtonsEnabled && self.stickButtonsAvailable;
    _stickButtonsSwitch.enabled = self.stickButtonsAvailable;
    _stickButtonsSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.stickButtons");
    _stickButtonsSwitch.accessibilityHint = AKHostLocalized(@"touch.settings.stickButtons.hint");
    _stickButtonsSwitch.accessibilityIdentifier = @"wolkaraforever.controls.stickButtons";
    if (!self.stickButtonsAvailable)
        _stickButtonsSwitch.accessibilityHint = AKHostLocalized(@"touch.settings.stickButtons.unsupported");
    [_stickButtonsSwitch addTarget:self action:@selector(stickButtonsChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *stickButtonsRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.stickButtons")],_stickButtonsSwitch]];
    stickButtonsRow.axis = UILayoutConstraintAxisHorizontal; stickButtonsRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:stickButtonsRow];
    _addZoneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_addZoneButton setTitle:AKHostLocalized(@"touch.settings.abilityZones.add") forState:UIControlStateNormal];
    _addZoneButton.accessibilityIdentifier = @"wolkaraforever.controls.addAbilityZone";
    [_addZoneButton addTarget:self action:@selector(addAbilityZoneTapped) forControlEvents:UIControlEventTouchUpInside];
    _clearZoneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_clearZoneButton setTitle:AKHostLocalized(@"touch.settings.abilityZones.clear") forState:UIControlStateNormal];
    _clearZoneButton.accessibilityIdentifier = @"wolkaraforever.controls.clearAbilityZones";
    [_clearZoneButton addTarget:self action:@selector(clearAbilityZonesTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *zonesRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.abilityZones")],_addZoneButton,_clearZoneButton]];
    zonesRow.axis = UILayoutConstraintAxisHorizontal; zonesRow.alignment = UIStackViewAlignmentCenter; zonesRow.distribution = UIStackViewDistributionFillEqually;
    [options addArrangedSubview:zonesRow];
    [options addArrangedSubview:[self label:AKHostLocalized(@"touch.settings.abilityZones.detail")]];
    [self updateSettingsZoneCount];
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem]; [reset setTitle:AKHostLocalized(@"touch.settings.reset") forState:UIControlStateNormal];
    reset.accessibilityIdentifier = @"wolkaraforever.controls.reset";
    [reset addTarget:self action:@selector(resetLayout) forControlEvents:UIControlEventTouchUpInside];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem]; [done setTitle:AKHostLocalized(@"common.done") forState:UIControlStateNormal];
    done.accessibilityIdentifier = @"wolkaraforever.controls.done";
    [done addTarget:self action:@selector(finishConfiguration) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *footer = [[UIStackView alloc] initWithArrangedSubviews:@[reset,done]];
    footer.axis = UILayoutConstraintAxisHorizontal; footer.distribution = UIStackViewDistributionFillEqually;
    footer.translatesAutoresizingMaskIntoConstraints = NO; [_settings addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [footer.bottomAnchor constraintEqualToAnchor:_settings.bottomAnchor constant:-8], [footer.heightAnchor constraintEqualToConstant:44],
        [footer.leadingAnchor constraintEqualToAnchor:_settings.leadingAnchor constant:18], [footer.trailingAnchor constraintEqualToAnchor:_settings.trailingAnchor constant:-18],
        [scroll.topAnchor constraintEqualToAnchor:_settings.topAnchor constant:16], [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-8],
        [scroll.leadingAnchor constraintEqualToAnchor:_settings.leadingAnchor constant:18], [scroll.trailingAnchor constraintEqualToAnchor:_settings.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)updateValues {
    _values[0].text = AKHostLocalizedFormat(@"touch.settings.transparency.value", (1-_preferences.opacity)*100);
    _values[1].text = AKHostLocalizedFormat(@"touch.settings.shoulderSize.value", _preferences.rearScale*100);
    _values[2].text = AKHostLocalizedFormat(@"touch.settings.stickSize.value", _preferences.frontScale*100);
    for (NSUInteger i=0; i<_sliders.count; i++) _sliders[i].accessibilityValue = _values[i].text;
}
- (void)sliderChanged:(UISlider *)slider {
    if (slider.tag == 0) _preferences.opacity = 1-slider.value;
    else if (slider.tag == 1) _preferences.rearScale = slider.value;
    else if (slider.tag == 2) _preferences.frontScale = slider.value;
    [_preferences save]; [self updateValues]; [self updateAppearance];
}
- (void)swapShouldersChanged:(UISwitch *)sender {
    [self reset]; _preferences.swapShoulders = !sender.on; [_preferences save];
    [self updateAppearance];
}
- (void)sticksOnlyChanged:(UISwitch *)sender {
    [self reset]; _preferences.sticksOnly = sender.on; [_preferences save];
    [self updateAppearance];
}
- (void)floatingChanged:(UISwitch *)sender {
    [self reset]; _preferences.floatingSticks = sender.on; [_preferences save];
    [self updateAppearance];
}
- (void)hapticsChanged:(UISwitch *)sender {
    _preferences.hapticsEnabled = sender.on; [_preferences save];
    if (self.configurationChanged) self.configurationChanged();
}
- (void)overlayChanged:(UISwitch *)sender {
    _preferences.performanceOverlayEnabled = sender.on; [_preferences save];
    if (self.configurationChanged) self.configurationChanged();
}
- (void)beginEditing:(UISwitch *)sender {
    if (!sender.on) return;
    [self reset]; _editing = YES; [_settings removeFromSuperview]; _settings = nil;
    _sliders = nil; _values = nil; _editSwitch = nil; _hapticsSwitch = nil; _overlaySwitch = nil; _swapShouldersSwitch = nil; _sticksOnlySwitch = nil; _floatingSwitch = nil; _settingsColumns = nil;
    _simpleSwitch = nil; _stickButtonsSwitch = nil; _addZoneButton = nil; _clearZoneButton = nil;
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
    // The zones' own menus (which button each sends) belong to the editor.
    [self syncAbilityZones];
}
- (void)resetLayout {
    [self reset]; [_preferences reset];
    _sliders[0].value = 1-_preferences.opacity; _sliders[1].value = _preferences.rearScale; _sliders[2].value = _preferences.frontScale;
    _hapticsSwitch.on = _preferences.hapticsEnabled; _swapShouldersSwitch.on = !_preferences.swapShoulders;
    _overlaySwitch.on = _preferences.performanceOverlayEnabled;
    _sticksOnlySwitch.on = _preferences.sticksOnly; _floatingSwitch.on = _preferences.floatingSticks;
    _simpleSwitch.on = _preferences.mode == AKGamepadLayoutModeSimple;
    _stickButtonsSwitch.on = _preferences.stickButtonsEnabled;
    [self syncAbilityZones]; [self updateSettingsZoneCount];
    [self updateValues]; [self updateAppearance];
}
- (void)finishConfiguration {
    [self reset]; [_preferences save]; _editing = NO; [_dragOrigins removeAllObjects];
    [_settings removeFromSuperview]; _settings = nil; _sliders = nil; _values = nil; _editSwitch = nil; _hapticsSwitch = nil; _overlaySwitch = nil; _swapShouldersSwitch = nil; _sticksOnlySwitch = nil; _floatingSwitch = nil; _settingsColumns = nil;
    _simpleSwitch = nil; _stickButtonsSwitch = nil; _addZoneButton = nil; _clearZoneButton = nil;
    [self syncAbilityZones];
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)reset {
    // Every reset releases everything this overlay can be holding: the stick button, the zones'
    // presses and the buttons' own. A press without its release is the one thing a virtual
    // controller must never be left with.
    [self releaseStickButton:@"reset"];
    for (AKGamepadButton *zone in _zoneButtons) [zone releaseInput];
    for (AKGamepadButton *button in _buttons.allValues) [button releaseInput];
    [_leftStick reset]; [_rightStick reset];
}
@end

@implementation AKTouchGamepad {
    __weak UIView *_host;
    GCVirtualController *_virtualController;
    AKGamepadOverlay *_overlay;
    AKTouchHaptics *_haptics;
    // How many surfaces are holding each element. Two fingers may press one button (a button
    // and an ability zone that sends it); the virtual controller's value is 1 while any is
    // down and returns to 0 only when the last one lets go, so a release can never cut another
    // finger's press short.
    NSMutableDictionary<NSString *, NSNumber *> *_holds;
    BOOL _active, _connecting, _cancelConnect, _failed, _invalidated;
    BOOL _controllerArrived;
    BOOL _spaceDown;
}
- (instancetype)initWithHostView:(UIView *)host {
    if ((self = [super init])) {
        _host = host; _enabled = YES;
        _holds = [NSMutableDictionary new];
        _haptics = [self makeHaptics];
        _overlay = [[AKGamepadOverlay alloc] initWithFrame:host.bounds];
        _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [host addSubview:_overlay];
        __weak AKTouchGamepad *weakSelf = self;
        _overlay.configurationChanged = ^{
            AKTouchGamepad *self = weakSelf;
            [self updateHaptics];
            if (self.visibilityChanged) self.visibilityChanged(self.visible);
        };
        // The stick buttons and the ability zones reach the controller through the same counted
        // path every other control uses.
        _overlay.elementPress = ^(NSString *element, BOOL pressed, NSString *control, NSString *reason) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            if (pressed) [self pressElement:element control:control];
            else [self releaseElement:element control:control reason:reason];
        };
        for (AKGamepadButton *button in _overlay.buttons.allValues)
            [button addTarget:self action:@selector(buttonChanged:) forControlEvents:UIControlEventValueChanged];
        [_overlay.leftStick addTarget:self action:@selector(stickChanged:) forControlEvents:UIControlEventValueChanged];
        [_overlay.rightStick addTarget:self action:@selector(stickChanged:) forControlEvents:UIControlEventValueChanged];
        _active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification,
                                 UIWindowDidBecomeKeyNotification, UIWindowDidResignKeyNotification,
                                 UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeHiddenNotification])
            [center addObserver:self selector:@selector(environmentChanged:) name:name object:nil];
        [center addObserver:self selector:@selector(activate:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(deactivate:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (NSArray<GCController *> *)connectedControllers { return GCController.controllers; }
- (AKTouchHaptics *)makeHaptics { return [AKTouchHaptics new]; }
- (void)updateHaptics { _haptics.enabled = _visible && !_overlay.configuring && _overlay.preferences.hapticsEnabled; }
- (GCVirtualController *)makeController {
    GCVirtualControllerConfiguration *configuration = [GCVirtualControllerConfiguration new];
    configuration.hidden = YES;
    // The configuration still applies the standard overlay's restrictions:
    // declaring D-pad plus left stick (or Menu/Options) throws even when hidden.
    // The connected extended profile provides D-pad and Menu nonetheless;
    // the public setters for both are covered by the real-controller fixture.
    configuration.elements = [NSSet setWithArray:@[GCInputLeftThumbstick,GCInputRightThumbstick,
        GCInputLeftThumbstickButton,GCInputRightThumbstickButton,
        GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,
        GCInputLeftShoulder,GCInputRightShoulder,GCInputLeftTrigger,GCInputRightTrigger]];
    return [[GCVirtualController alloc] initWithConfiguration:configuration];
}
- (BOOL)hostIsActive {
    UIWindow *window = _host.window;
    return _active && window.isKeyWindow && !window.hidden && !_host.hidden;
}
- (BOOL)hasPhysicalController {
    GCController *own = _virtualController.controller;
    for (GCController *controller in [self connectedControllers]) {
        // Snapshots are app-created state, not connected hardware. Our own
        // connection notification must not cause us to disconnect ourselves.
        if (controller != own && !controller.isSnapshot &&
            (controller.extendedGamepad || controller.microGamepad)) return YES;
    }
    return NO;
}
- (BOOL)wantsController {
    return !_invalidated && _enabled && !_keyboardVisible && [self hostIsActive];
}
- (void)setVisible:(BOOL)visible {
    if (!visible) {
        [self holdSpace:NO];
        // A stick button is a press with a timer: hiding the controls takes the gesture away,
        // so it is let go of here rather than by a timer that may never run.
        [_overlay releaseTransientInput:@"hidden"];
    }
    if (_visible == visible) return;
    _visible = visible; _overlay.controlsVisible = visible;
    _overlay.stickButtonsAvailable = [self stickButtonsAvailable];
    [self updateHaptics];
    if (self.visibilityChanged) self.visibilityChanged(visible);
}
// With sticks only, the one button is "Saut", and it jumps with the game's own jump key,
// Space, which the game's default bindings always have. Whether its gamepad layout binds A
// to Jump was never checked: on 2026-11-05 the controller received A 48 times while the
// player ran, 20 to 179 ms each, and the character did not jump once. The key is held as long
// as the finger is (a held Space swims or flies up), and a release always goes out, even if
// the controls were hidden meanwhile. A host without the key method keeps the gamepad's A.
// Apple's virtual controller has no stick click: its extended profile is A/B/X/Y, the
// shoulders, the triggers, the menu, the D-pad and the two sticks' directions - and nothing
// else. Measured on the iPad Pro 13-inch (M5) simulator, 2026-11-13: the profile's button list
// has no stick-button element, `-leftThumbstickButton` is nil, and a value set for it is
// dropped. So a press for it is refused, and the settings row says so.
- (BOOL)stickButtonsAvailable {
    // A controller's profile is asked politely: a test's stand-in is not a real one, and a
    // capability question must never be able to end the process.
    GCController *controller = _virtualController.controller;
    if (![controller isKindOfClass:GCController.class]) return NO;
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (![pad isKindOfClass:GCExtendedGamepad.class]) return NO;
    return pad.leftThumbstickButton != nil && pad.rightThumbstickButton != nil;
}
- (BOOL)isStickButtonElement:(NSString *)element {
    return [element isEqualToString:GCInputLeftThumbstickButton] ||
           [element isEqualToString:GCInputRightThumbstickButton];
}
- (BOOL)jumpsWithSpace:(AKGamepadButton *)button {
    return [button.slot isEqualToString:GCInputButtonA] && _overlay.preferences.sticksOnly &&
        [_host respondsToSelector:@selector(touchKey:characters:pressed:)];
}
- (void)holdSpace:(BOOL)down {
    if (_spaceDown == down) return;
    _spaceDown = down;
    [(id<AKTouchControlsDelegate>)_host touchKey:49 characters:@" " pressed:down];
}
- (void)buttonChanged:(AKGamepadButton *)button {
    if ([self jumpsWithSpace:button]) {
        if (!button.pressed) { [self holdSpace:NO]; return; }
        if (!_visible || _overlay.configuring) return;
        [_haptics buttonPressed];
        [self holdSpace:YES];
        return;
    }
    // The D-pad is one axis recomputed from four sectors, so it is not counted per element:
    // its value follows whichever sectors are down right now.
    if ([button.element hasPrefix:@"dpad."]) {
        if (!button.pressed) {
            [self updateDirectionPad];
            AKTouchControllerLog(AKTouchControllerEventRelease, @"sent",
                                 @{@"control": @"button", @"element": AKGamepadElementToken(button.element), @"reason": @"lifted"});
            return;
        }
        if (!_visible || _overlay.configuring) {
            AKTouchControllerLog(AKTouchControllerEventPress, @"refused",
                                 @{@"control": @"button", @"element": AKGamepadElementToken(button.element), @"reason": @"hidden"});
            return;
        }
        [_haptics buttonPressed];
        [self updateDirectionPad];
        AKTouchControllerLog(AKTouchControllerEventPress, @"sent",
                             @{@"control": @"button", @"element": AKGamepadElementToken(button.element)});
        return;
    }
    // A release always goes out, whatever the controls are doing by then: a press whose
    // release is dropped is a button the game believes is still held. The feedback is the
    // press's, exactly as before: one pulse per press, none for a release or a refusal.
    if (button.pressed) {
        if (_visible && !_overlay.configuring) [_haptics buttonPressed];
        [self pressElement:button.element control:@"button"];
    } else {
        [self releaseElement:button.element control:@"button" reason:@"lifted"];
    }
}
- (void)updateDirectionPad {
    NSString *right = _overlay.buttons[@"dpad.right"].pressed ? @"1" : @"0";
    NSString *left = _overlay.buttons[@"dpad.left"].pressed ? @"1" : @"0";
    NSString *up = _overlay.buttons[@"dpad.up"].pressed ? @"1" : @"0";
    NSString *down = _overlay.buttons[@"dpad.down"].pressed ? @"1" : @"0";
    CGPoint value = CGPointMake(right.integerValue - left.integerValue,
                                up.integerValue - down.integerValue);
    [_virtualController setPosition:value forDirectionPadElement:GCInputDirectionPad];
}
// One counted hold per element. `count` is how many surfaces are on it, and the controller only
// hears about the first press and the last release.
- (void)pressElement:(NSString *)element control:(NSString *)control {
    if (!element.length) return;
    if (!_visible || _overlay.configuring) {
        AKTouchControllerLog(AKTouchControllerEventPress, @"refused",
                             @{@"control": control, @"element": AKGamepadElementToken(element),
                               @"reason": _visible ? @"configuring" : @"hidden"});
        return;
    }
    if ([self isStickButtonElement:element] && ![self stickButtonsAvailable]) {
        AKTouchControllerLog(AKTouchControllerEventPress, @"refused",
                             @{@"control": control, @"element": AKGamepadElementToken(element),
                               @"reason": @"unsupported"});
        return;
    }
    NSUInteger count = [_holds[element] unsignedIntegerValue];
    _holds[element] = @(count + 1);
    if (count == 0) [_virtualController setValue:1 forButtonElement:[self buttonElementForElement:element]];
    AKTouchControllerLog(AKTouchControllerEventPress, @"sent",
                         @{@"control": control, @"element": AKGamepadElementToken(element),
                           @"count": [@(count + 1) stringValue]});
}
- (void)releaseElement:(NSString *)element control:(NSString *)control reason:(NSString *)reason {
    if (!element.length) return;
    NSUInteger count = [_holds[element] unsignedIntegerValue];
    if (!count) {
        // A release with nothing held is refused and said so: it is the shape a doubled release
        // would take, and a fixture reads this line to prove there is only ever one.
        AKTouchControllerLog(AKTouchControllerEventRelease, @"refused",
                             @{@"control": control, @"element": AKGamepadElementToken(element),
                               @"reason": reason ?: @"unknown"});
        return;
    }
    _holds[element] = @(count - 1);
    if (count == 1) [_virtualController setValue:0 forButtonElement:[self buttonElementForElement:element]];
    AKTouchControllerLog(AKTouchControllerEventRelease, @"sent",
                         @{@"control": control, @"element": AKGamepadElementToken(element),
                           @"count": [@(count - 1) stringValue], @"reason": reason ?: @"lifted"});
}
// Everything this manager is holding, released once each. Used at teardown, where the virtual
// controller is about to go away and nothing may be left pressed.
- (void)releaseAllElements:(NSString *)reason {
    NSArray<NSString *> *elements = _holds.allKeys;
    for (NSString *element in elements) {
        if (![_holds[element] unsignedIntegerValue]) continue;
        _holds[element] = @0;
        [_virtualController setValue:0 forButtonElement:[self buttonElementForElement:element]];
        AKTouchControllerLog(AKTouchControllerEventRelease, @"sent",
                             @{@"control": @"button", @"element": AKGamepadElementToken(element), @"reason": reason ?: @"teardown"});
    }
    [_holds removeAllObjects];
}
- (void)reloadLayout {
    // The controller may have come or gone since the overlay last looked, so what it can send
    // is re-read here too: the settings row and the gesture both depend on it.
    _overlay.stickButtonsAvailable = [self stickButtonsAvailable];
    [_overlay reloadLayout];
    [self updateHaptics];
}
// A stick's click is not the stick. The direction is GCInputLeftThumbstick and the button a
// controller calls L3 is GCInputLeftThumbstickButton; the virtual controller refuses the
// direction as a button, and says so by throwing, so the two are never mixed up here.
- (NSString *)buttonElementForElement:(NSString *)element {
    return AKGamepadStickButtonElement(element);
}
- (void)stickChanged:(AKGamepadStick *)stick {
    if (_visible && !_overlay.configuring) {
        [_haptics stickMoved:stick.position left:stick == _overlay.leftStick];
        [_virtualController setPosition:stick.position forDirectionPadElement:stick.element];
    }
}
- (void)disconnectController {
    [self holdSpace:NO];
    GCVirtualController *controller = _virtualController;
    // Explicitly release our held controls before removing the virtual device.
    // No value or handler on a physical controller is changed.
    [_overlay releaseTransientInput:@"teardown"];
    [_overlay reset];
    [self releaseAllElements:@"teardown"];
    _virtualController = nil;
    [controller disconnect];
    [self setVisible:NO];
}
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"Touch controller lifecycle belongs on the main thread");
    // A physical controller hides the on-screen gamepad, so a settings or layout
    // surface that is open has nothing left to configure and must close. Close it
    // when a controller actually connects: keyboard, window and application
    // notifications reach -refresh too, and closing on those made the panel vanish
    // while it was being used on any device that already had a controller.
    BOOL physical = [self hasPhysicalController];
    if (physical && !_controllerArrived && _overlay.configuring) [_overlay finishConfiguration];
    _controllerArrived = physical;
    if (_connecting) {
        // Wait for this attempt's reply before starting another one. A late
        // successful connect must not bring controls back after suspension.
        if (![self wantsController]) { _cancelConnect = YES; [_virtualController disconnect]; }
        return;
    }
    if (![self wantsController] || [self hasPhysicalController]) {
        [self disconnectController]; return;
    }
    if (_virtualController || _failed) return;
    _virtualController = [self makeController];
    _connecting = YES; _cancelConnect = NO;
    GCVirtualController *connecting = _virtualController;
    __weak AKTouchGamepad *weakSelf = self;
    [connecting connectWithReplyHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AKTouchGamepad *self = weakSelf;
            if (!self) { [connecting disconnect]; return; }
            self->_connecting = NO;
            BOOL cancelled = self->_cancelConnect;
            self->_cancelConnect = NO;
            if (error || cancelled || ![self wantsController] || [self hasPhysicalController]) {
                if (error) NSLog(@"[TouchGamepad] Connection failed: %@ (%ld)",error.domain,(long)error.code);
                self->_failed = error != nil;
                [self disconnectController];
                if (cancelled && !error) [self refresh];
                return;
            }
            [self setVisible:YES];
        });
    }];
}
- (void)environmentChanged:(NSNotification *)note {
    (void)note;
    // GC notifications can precede connect's reply or arrive off-main. Defer
    // enumeration until the system finishes the connection transaction.
    __weak AKTouchGamepad *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}
- (void)activate:(NSNotification *)note {
    (void)note; _active = YES; _failed = NO; [self refresh];
}
- (void)deactivate:(NSNotification *)note {
    (void)note; [_overlay finishConfiguration]; _active = NO; [self refresh];
}
- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled; _failed = NO; [self refresh];
}
- (void)setKeyboardVisible:(BOOL)visible {
    _keyboardVisible = visible; [self refresh];
}
- (BOOL)configuring { return _overlay.configuring; }
- (void)toggleSettings { [_overlay toggleSettings]; }
- (void)invalidate {
    [_overlay finishConfiguration];
    _invalidated = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self refresh];
    [self releaseAllElements:@"teardown"];
    [_overlay removeFromSuperview];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_virtualController disconnect];
}
@end
