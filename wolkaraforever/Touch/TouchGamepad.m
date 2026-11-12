#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "AKHostLocalization.h"
#import "InterfaceMode.h"
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
- (void)pollAutoRun:(NSTimeInterval)now;
- (void)reset;
@end
static const NSTimeInterval AKAutoRunHold = 2;
static const CGFloat AKAutoRunArm = 60;
@implementation AKGamepadStick {
    UIView *_knob;
    NSTimeInterval _forwardSince;
    NSInteger _autoStage;
    BOOL _autoRunning, _stoppedRun;
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
    if (_autoRunning) { _autoRunning = NO; [self setAutoStage:0]; }
    if (_floating && ring.superview) {
        ring.center = [touch locationInView:ring.superview];
        ring.alpha = _activeAlpha > 0 ? _activeAlpha : 1;
    }
    [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self],self.bounds.size)]; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self],self.bounds.size)];
    [self trackAutoRun:touch];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)touch; (void)event;
    _held = NO;
    if (_autoStage == 2 && _autoRunAllowed) {
        // Confirmed: the run stays on with the stick held forward, and the ring goes away.
        _autoRunning = YES;
        [self setAutoStage:3];
        [self updatePosition:CGPointMake(0, 1)];
        [self fadeOut];
        return;
    }
    [self reset]; [self fadeOut];
    if (_stoppedRun) { _stoppedRun = NO; return; }
}
- (void)cancelTrackingWithEvent:(UIEvent *)event { (void)event; _held = NO; [self reset]; [self fadeOut]; }
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
- (void)reset;
- (void)toggleSettings;
- (void)finishConfiguration;
@end
// The floating arrangement's geometry, in fractions of the overlay. The two halves are the
// thumbs' own: a press there is a stick push, not a tap on the game. The corner beyond the
// camera stick is the jump, and the gaps around it are the add-on's own controls, which a
// floating stick must never take: the quick bar down the left, the chat strip at the bottom
// centre, and the wheels' tabs between them.
static const CGFloat AKFloatIdleAlpha = 0.02;
static const CGFloat AKFloatJumpRadius = 0.16, AKFloatFanRadius = 0.36;
static const CGFloat AKFloatIslandRadius = 0.43, AKFloatIslandSize = 0.056;
static const CGFloat AKFloatIslandAngles[] = {58, 82};
static const CGFloat AKFloatInnerRadius = 0.20, AKFloatInnerSize = 0.05;
static const CGFloat AKFloatInnerAngles[] = {13, 45};
static const CGFloat AKFloatLeftMinX = 0.10, AKFloatLeftMaxX = 0.42;
static const CGFloat AKFloatLeftMinY = 0.42, AKFloatLeftLowY = 0.86;
static const CGFloat AKFloatRightMinX = 0.64, AKFloatRightMinY = 0.25, AKFloatRightMaxY = 0.92;
static const CGFloat AKChatButtonHalfWidth = 0.068, AKChatButtonTop = 0.925;
@implementation AKGamepadOverlay {
    NSDictionary<NSString *,UIView *> *_items;
    NSMutableDictionary<NSString *,NSValue *> *_dragOrigins;
    UIView *_settings;
    UIButton *_editDone;
    UILabel *_hint;
    UISwitch *_editSwitch, *_hapticsSwitch, *_overlaySwitch, *_swapShouldersSwitch, *_sticksOnlySwitch;
    UISwitch *_floatingSwitch;
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
        UIView *left = [UIView new], *right = [UIView new];
        left.multipleTouchEnabled = right.multipleTouchEnabled = YES;
        [self addSubview:left]; [self addSubview:right];
        for (NSUInteger i=0; i<elements.count; i++) {
            AKGamepadButton *button = [AKGamepadButton new]; button.element = elements[i];
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.accessibilityLabel = AKHostLocalizedFormat(@"touch.gamepad.button", elements[i]);
            button.accessibilityIdentifier = [@"tolkara.gamepad." stringByAppendingString:elements[i]];
            buttons[elements[i]] = button;
            [(i<4 ? right : i>=9 ? left : self) addSubview:button];
        }
        _buttons = buttons;
        _leftStick = [AKGamepadStick new]; _rightStick = [AKGamepadStick new];
        _leftStick.element = GCInputLeftThumbstick; _rightStick.element = GCInputRightThumbstick;
        _leftStick.accessibilityLabel = AKHostLocalized(@"touch.gamepad.leftStick");
        _rightStick.accessibilityLabel = AKHostLocalized(@"touch.gamepad.rightStick");
        _leftStick.accessibilityIdentifier = @"tolkara.gamepad.leftStick"; _rightStick.accessibilityIdentifier = @"tolkara.gamepad.rightStick";
        [left addSubview:_leftStick]; [right addSubview:_rightStick];
        _items = @{@"left":left,@"right":right,@"LB":buttons[GCInputLeftShoulder],@"LT":buttons[GCInputLeftTrigger],
            @"RB":buttons[GCInputRightShoulder],@"RT":buttons[GCInputRightTrigger],@"menu":buttons[GCInputButtonMenu]};
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
        // Common modes, because the guest drives the main run loop in modes of its own while it
        // runs; a default-mode timer would wait for the game to return to the default mode.
        __weak AKGamepadOverlay *weakSelf = self;
        NSTimer *idle = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            AKGamepadOverlay *overlay = weakSelf;
            if (!overlay) { [timer invalidate]; return; }
            [overlay hideIdleRings];
        }];
        [NSRunLoop.mainRunLoop addTimer:idle forMode:NSRunLoopCommonModes];
        [self updateAppearance];
    }
    return self;
}
- (BOOL)configuring { return _settings != nil || _editing; }
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
        BOOL jump = [button.element isEqualToString:GCInputButtonA];
        if (sticksOnly) button.hidden = !jump;
        else if (![placed containsObject:button]) button.hidden = NO;
        if (jump) [button setTitle:sticksOnly ? AKHostLocalized(@"touch.gamepad.jump") : @"A" forState:UIControlStateNormal];
    }
    // An enabled UIControl is needed for its own pan recognizer to receive
    // touches. The manager suppresses game input throughout configuration.
    for (AKGamepadButton *button in _buttons.allValues) button.enabled = !self.configuring || _editing;
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
// everywhere else - including the add-on's own controls - is not ours, so the touch goes on to
// whatever is underneath. Nothing here forwards a touch by hand: returning nil is the app's own
// hit-testing doing it.
- (UIView *)floatingHit:(CGPoint)point event:(UIEvent *)event {
    CGSize size = self.bounds.size;
    if (size.width <= 0 || size.height <= 0) return nil;
    CGFloat h = size.height, corner = hypot(size.width - point.x, size.height - point.y);
    CGFloat fx = point.x / size.width, fy = point.y / h;
    // The add-on's own chat strip at the bottom centre: a press there is the add-on's, and
    // nothing here takes it.
    if (fabs(fx - 0.5) <= AKChatButtonHalfWidth && fy >= AKChatButtonTop) return nil;
    for (size_t i = 0; i < sizeof(AKFloatInnerAngles) / sizeof(AKFloatInnerAngles[0]); i++) {
        CGFloat angle = AKFloatInnerAngles[i] * M_PI / 180;
        CGFloat x = size.width - AKFloatInnerRadius * h * cos(angle), y = size.height - AKFloatInnerRadius * h * sin(angle);
        if (hypot(point.x - x, point.y - y) <= AKFloatInnerSize * h) return nil;
    }
    if (corner <= AKFloatJumpRadius * h) {
        AKGamepadButton *jump = _buttons[GCInputButtonA];
        return jump.enabled ? jump : nil;
    }
    if (corner <= AKFloatFanRadius * h) return nil;
    for (size_t i = 0; i < sizeof(AKFloatIslandAngles) / sizeof(AKFloatIslandAngles[0]); i++) {
        CGFloat angle = AKFloatIslandAngles[i] * M_PI / 180;
        CGFloat x = size.width - AKFloatIslandRadius * h * cos(angle), y = size.height - AKFloatIslandRadius * h * sin(angle);
        if (hypot(point.x - x, point.y - y) <= AKFloatIslandSize * h) return nil;
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
    AKGamepadButton *jump = _buttons[GCInputButtonA];
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
        AKGamepadButton *a = _buttons[leftNames[i]], *b = _buttons[rightNames[i]];
        if (a.sector != (NSInteger)i) a.sector = i;
        if (b.sector != (NSInteger)i) b.sector = i;
        a.frame = b.frame = CGRectMake(0,0,216,216);
    }
    [self place:@"LT" frame:CGRectMake(left,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"LB" frame:CGRectMake(left+w+8,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"RT" frame:CGRectMake(right-w,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
    [self place:@"RB" frame:CGRectMake(right-w*2-8,top,w,h) baseSize:CGSizeMake(56,44) safe:safe];
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
    NSString *name = [_items allKeysForObject:pan.view].firstObject;
    if (!name || !_editing) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        [_dragOrigins setObject:[NSValue valueWithCGRect:pan.view.frame] forKey:name]; [self reset];
    }
    CGRect frame = [_dragOrigins[name] CGRectValue];
    if (pan.state == UIGestureRecognizerStateCancelled) {
        [_preferences moveItem:[self positionName:name] toFrame:frame inBounds:[self usableBounds]];
    } else {
        CGPoint delta = [pan translationInView:self];
        frame.origin.x += delta.x; frame.origin.y += delta.y;
        [_preferences moveItem:[self positionName:name] toFrame:frame inBounds:[self usableBounds]];
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
    _swapShouldersSwitch = [UISwitch new]; _swapShouldersSwitch.on = !_preferences.swapShoulders;
    _swapShouldersSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.outerTriggers");
    _swapShouldersSwitch.accessibilityIdentifier = @"wolkaraforever.controls.swapShoulders";
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
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)resetLayout {
    [self reset]; [_preferences reset];
    _sliders[0].value = 1-_preferences.opacity; _sliders[1].value = _preferences.rearScale; _sliders[2].value = _preferences.frontScale;
    _hapticsSwitch.on = _preferences.hapticsEnabled; _swapShouldersSwitch.on = !_preferences.swapShoulders;
    _overlaySwitch.on = _preferences.performanceOverlayEnabled;
    _sticksOnlySwitch.on = _preferences.sticksOnly; _floatingSwitch.on = _preferences.floatingSticks;
    [self updateValues]; [self updateAppearance];
}
- (void)finishConfiguration {
    [self reset]; [_preferences save]; _editing = NO; [_dragOrigins removeAllObjects];
    [_settings removeFromSuperview]; _settings = nil; _sliders = nil; _values = nil; _editSwitch = nil; _hapticsSwitch = nil; _overlaySwitch = nil; _swapShouldersSwitch = nil; _sticksOnlySwitch = nil; _floatingSwitch = nil; _settingsColumns = nil;
    [self updateAppearance]; if (self.configurationChanged) self.configurationChanged();
}
- (void)reset {
    for (AKGamepadButton *button in _buttons.allValues) [button releaseInput];
    [_leftStick reset]; [_rightStick reset];
}
@end

@implementation AKTouchGamepad {
    __weak UIView *_host;
    GCVirtualController *_virtualController;
    AKGamepadOverlay *_overlay;
    AKTouchHaptics *_haptics;
    BOOL _active, _connecting, _cancelConnect, _failed, _invalidated;
    BOOL _controllerArrived;
    BOOL _spaceDown;
}
- (instancetype)initWithHostView:(UIView *)host {
    if ((self = [super init])) {
        _host = host; _enabled = YES;
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
    if (!visible) [self holdSpace:NO];
    if (_visible == visible) return;
    _visible = visible; _overlay.controlsVisible = visible;
    [self updateHaptics];
    if (self.visibilityChanged) self.visibilityChanged(visible);
}
// With sticks only, the one button is "Saut", and it jumps with the game's own jump key,
// Space, which the game's default bindings always have. Whether its gamepad layout binds A
// to Jump was never checked: on 2026-11-05 the controller received A 48 times while the
// player ran, 20 to 179 ms each, and the character did not jump once. The key is held as long
// as the finger is (a held Space swims or flies up), and a release always goes out, even if
// the controls were hidden meanwhile. A host without the key method keeps the gamepad's A.
- (BOOL)jumpsWithSpace:(AKGamepadButton *)button {
    return [button.element isEqualToString:GCInputButtonA] && _overlay.preferences.sticksOnly &&
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
    if (!_visible || _overlay.configuring) return;
    if (button.pressed) [_haptics buttonPressed];
    if ([button.element hasPrefix:@"dpad."]) {
        CGPoint value = CGPointMake(_overlay.buttons[@"dpad.right"].pressed - _overlay.buttons[@"dpad.left"].pressed,
                                    _overlay.buttons[@"dpad.up"].pressed - _overlay.buttons[@"dpad.down"].pressed);
        [_virtualController setPosition:value forDirectionPadElement:GCInputDirectionPad];
    } else [_virtualController setValue:button.pressed ? 1 : 0 forButtonElement:button.element];
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
    [_overlay reset];
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
    [_overlay removeFromSuperview];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_virtualController disconnect];
}
@end
