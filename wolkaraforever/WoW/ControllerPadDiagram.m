#import "ControllerPadDiagram.h"

#import "../Controller/ControllerProfile.h"
#import "../App/WKLocalization.h"

// The drawing is laid out in one fixed space and scaled to whatever width the page gives it, so
// the ink and the hit areas can never disagree about where a button is.
static CGFloat const CMPadWidth = 1000;
static CGFloat const CMPadHeight = 660;

static UIColor *CMPadBody(void) { return [UIColor colorWithRed:0.06 green:0.09 blue:0.15 alpha:1]; }
static UIColor *CMPadEdge(void) { return [UIColor colorWithRed:0.16 green:0.21 blue:0.30 alpha:1]; }
static UIColor *CMPadInk(void) { return [UIColor colorWithRed:0.88 green:0.92 blue:0.97 alpha:1]; }
static UIColor *CMPadMuted(void) { return [UIColor colorWithRed:0.52 green:0.58 blue:0.66 alpha:1]; }
static UIColor *CMPadGold(void) { return [UIColor colorWithRed:0.88 green:0.73 blue:0.43 alpha:1]; }

// What a virtual control is called when it has to fit inside a button.
static NSString *CMPadShortTarget(NSString *identifier) {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{@"virtual.button.a": @"A", @"virtual.button.b": @"B",
                  @"virtual.button.x": @"X", @"virtual.button.y": @"Y",
                  @"virtual.button.left.shoulder": @"LB", @"virtual.button.right.shoulder": @"RB",
                  @"virtual.button.left.trigger": @"LT", @"virtual.button.right.trigger": @"RT",
                  @"virtual.button.menu": @"Menu",
                  @"virtual.stick.left": @"L stick", @"virtual.stick.right": @"R stick",
                  @"virtual.dpad": @"D-pad"};
    });
    return names[identifier];
}

#pragma mark - One control

@interface CMPadSpot : NSObject
@property (nonatomic, copy) NSString *source;
/// Drawn inside the shape: "A", "LB", "L". Empty when the shape speaks for itself.
@property (nonatomic, copy) NSString *label;
@property (nonatomic) CGPoint centre;
@property (nonatomic) CGFloat radius;
@property (nonatomic) CGRect box;
@property (nonatomic) BOOL round;
/// The D-pad, drawn as a cross.
@property (nonatomic) BOOL cross;
/// Menu, View, Home and the stick clicks: a dot with its name beside it.
@property (nonatomic) BOOL dot;
@end

@implementation CMPadSpot

- (BOOL)containsPoint:(CGPoint)point {
    if (!self.round) return CGRectContainsPoint(self.box, point);
    CGFloat dx = point.x - self.centre.x, dy = point.y - self.centre.y;
    return dx * dx + dy * dy <= self.radius * self.radius;
}

@end

@interface TKWoWControllerPadDiagram ()
@property (nonatomic, copy) NSArray<CMPadSpot *> *spots;
@end

@implementation TKWoWControllerPadDiagram

+ (NSArray<NSString *> *)drawnSources {
    return @[@"controller.button.a", @"controller.button.b", @"controller.button.x",
             @"controller.button.y", @"controller.button.left.shoulder",
             @"controller.button.right.shoulder", @"controller.button.left.trigger",
             @"controller.button.right.trigger", @"controller.axis.left.thumbstick",
             @"controller.axis.right.thumbstick", @"dpad.dpad",
             @"controller.button.left.thumbstick.button",
             @"controller.button.right.thumbstick.button", @"controller.button.menu",
             @"controller.button.options", @"controller.button.home"];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = NO;
        _bindings = @{};
        _withheld = [NSSet set];
        _spots = [self buildSpots];
    }
    return self;
}

- (CMPadSpot *)rectSpot:(NSString *)source label:(NSString *)label box:(CGRect)box {
    CMPadSpot *spot = [CMPadSpot new];
    spot.source = source;
    spot.label = label;
    spot.box = box;
    spot.centre = CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box));
    return spot;
}

- (CMPadSpot *)circleSpot:(NSString *)source label:(NSString *)label
                   centre:(CGPoint)centre radius:(CGFloat)radius dot:(BOOL)dot {
    CMPadSpot *spot = [CMPadSpot new];
    spot.source = source;
    spot.label = label;
    spot.centre = centre;
    spot.radius = radius;
    spot.round = YES;
    spot.dot = dot;
    spot.box = CGRectMake(centre.x - radius, centre.y - radius, radius * 2, radius * 2);
    return spot;
}

- (NSArray<CMPadSpot *> *)buildSpots {
    NSMutableArray<CMPadSpot *> *spots = [NSMutableArray array];
    [spots addObject:[self rectSpot:@"controller.button.left.trigger" label:@"LT"
                                box:CGRectMake(250, 30, 150, 48)]];
    [spots addObject:[self rectSpot:@"controller.button.right.trigger" label:@"RT"
                                box:CGRectMake(600, 30, 150, 48)]];
    [spots addObject:[self rectSpot:@"controller.button.left.shoulder" label:@"LB"
                                box:CGRectMake(250, 86, 150, 42)]];
    [spots addObject:[self rectSpot:@"controller.button.right.shoulder" label:@"RB"
                                box:CGRectMake(600, 86, 150, 42)]];
    CMPadSpot *dpad = [self rectSpot:@"dpad.dpad" label:@"D-pad" box:CGRectMake(265, 240, 140, 140)];
    dpad.cross = YES;
    [spots addObject:dpad];
    // Face buttons, Xbox arrangement: Y top, X left, B right, A bottom.
    [spots addObject:[self circleSpot:@"controller.button.y" label:@"Y"
                               centre:CGPointMake(700, 215) radius:38 dot:NO]];
    [spots addObject:[self circleSpot:@"controller.button.x" label:@"X"
                               centre:CGPointMake(618, 297) radius:38 dot:NO]];
    [spots addObject:[self circleSpot:@"controller.button.b" label:@"B"
                               centre:CGPointMake(782, 297) radius:38 dot:NO]];
    [spots addObject:[self circleSpot:@"controller.button.a" label:@"A"
                               centre:CGPointMake(700, 379) radius:38 dot:NO]];
    // Dots before the sticks, so a click inside a stick wins the touch.
    [spots addObject:[self circleSpot:@"controller.button.options" label:@"View"
                               centre:CGPointMake(452, 170) radius:22 dot:YES]];
    [spots addObject:[self circleSpot:@"controller.button.menu" label:@"Menu"
                               centre:CGPointMake(560, 170) radius:22 dot:YES]];
    [spots addObject:[self circleSpot:@"controller.button.home" label:@""
                               centre:CGPointMake(506, 104) radius:24 dot:YES]];
    [spots addObject:[self circleSpot:@"controller.button.left.thumbstick.button" label:@""
                               centre:CGPointMake(335, 500) radius:20 dot:YES]];
    [spots addObject:[self circleSpot:@"controller.button.right.thumbstick.button" label:@""
                               centre:CGPointMake(665, 500) radius:20 dot:YES]];
    [spots addObject:[self circleSpot:@"controller.axis.left.thumbstick" label:@"L"
                               centre:CGPointMake(335, 500) radius:60 dot:NO]];
    [spots addObject:[self circleSpot:@"controller.axis.right.thumbstick" label:@"R"
                               centre:CGPointMake(665, 500) radius:60 dot:NO]];
    return spots;
}

- (void)setBindings:(NSDictionary<NSString *, AKControllerBinding *> *)bindings {
    _bindings = [bindings copy] ?: @{};
    [self setNeedsDisplay];
}

- (void)setWithheld:(NSSet<NSString *> *)withheld {
    _withheld = [withheld copy] ?: [NSSet set];
    [self setNeedsDisplay];
}

- (void)setWaiting:(BOOL)waiting {
    _waiting = waiting;
    [self setNeedsDisplay];
}

#pragma mark - Ink

// The design space, scaled to fit and centred, computed the same way for the ink and for a touch.
- (CGAffineTransform)designTransform {
    CGFloat scale = MIN(CGRectGetWidth(self.bounds) / CMPadWidth,
                        CGRectGetHeight(self.bounds) / CMPadHeight);
    if (scale <= 0) scale = 1;
    CGFloat dx = (CGRectGetWidth(self.bounds) - CMPadWidth * scale) / 2;
    CGFloat dy = (CGRectGetHeight(self.bounds) - CMPadHeight * scale) / 2;
    return CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                  CGAffineTransformMakeTranslation(dx, dy));
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    CGContextSaveGState(context);
    CGContextConcatCTM(context, [self designTransform]);

    // The body: one slab and two grips, which is all a pad is.
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(200, 90, 600, 320)
                                                       cornerRadius:150];
    [body appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(160, 330, 250, 300)]];
    [body appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(590, 330, 250, 300)]];
    [CMPadBody() setFill];
    [body fill];
    [CMPadEdge() setStroke];
    body.lineWidth = 4;
    [body stroke];

    for (CMPadSpot *spot in self.spots) [self drawSpot:spot];

    NSString *hint = self.waiting ? WKLocalized(@"controller.learn.waiting")
                                  : WKLocalized(@"controller.diagram.hint");
    NSDictionary *attributes =
        @{NSFontAttributeName: [UIFont systemFontOfSize:self.waiting ? 26 : 21
                                                 weight:self.waiting ? UIFontWeightSemibold
                                                                    : UIFontWeightRegular],
          NSForegroundColorAttributeName: self.waiting ? CMPadGold() : CMPadMuted()};
    CGSize size = [hint sizeWithAttributes:attributes];
    [hint drawAtPoint:CGPointMake((CMPadWidth - size.width) / 2, 600) withAttributes:attributes];
    CGContextRestoreGState(context);
}

// What this control drives by default, in the same shorthand the drawing uses. A target equal to
// this is what the row already means, so it is not written twice.
- (BOOL)targetIsTheDefault:(NSString *)source target:(NSString *)target {
    NSDictionary<NSString *, NSString *> *defaults = @{
        @"controller.button.a": @"A", @"controller.button.b": @"B",
        @"controller.button.x": @"X", @"controller.button.y": @"Y",
        @"controller.button.left.shoulder": @"LB", @"controller.button.right.shoulder": @"RB",
        @"controller.button.left.trigger": @"LT", @"controller.button.right.trigger": @"RT",
        @"controller.button.menu": @"Menu",
        @"controller.axis.left.thumbstick": @"L stick",
        @"controller.axis.right.thumbstick": @"R stick",
        @"dpad.dpad": @"D-pad",
    };
    NSString *own = defaults[source];
    return own != nil && [own isEqualToString:target];
}

- (void)drawSpot:(CMPadSpot *)spot {
    BOOL kept = [self.withheld containsObject:spot.source];
    AKControllerBinding *binding = self.bindings[spot.source];
    BOOL missing = binding == nil || !binding.available;
    UIColor *ink = kept ? CMPadGold() : (missing ? CMPadMuted() : CMPadInk());
    NSString *target = [self targetTextForSource:spot.source kept:kept];
    // Written only when it says something the picture does not already say: a control that drives
    // the thing of the same name needs no second label.
    BOOL showTarget = kept || missing || ![self targetIsTheDefault:spot.source target:target];
    UIColor *valueInk = kept ? CMPadGold() : (missing ? CMPadMuted() : CMPadInk());

    if (spot.cross) {
        CGFloat cx = CGRectGetMidX(spot.box), cy = CGRectGetMidY(spot.box);
        CGFloat arm = CGRectGetWidth(spot.box) / 2, thick = 44;
        UIBezierPath *cross = [UIBezierPath bezierPath];
        [cross moveToPoint:CGPointMake(cx - thick / 2, cy - arm)];
        [cross addLineToPoint:CGPointMake(cx + thick / 2, cy - arm)];
        [cross addLineToPoint:CGPointMake(cx + thick / 2, cy - thick / 2)];
        [cross addLineToPoint:CGPointMake(cx + arm, cy - thick / 2)];
        [cross addLineToPoint:CGPointMake(cx + arm, cy + thick / 2)];
        [cross addLineToPoint:CGPointMake(cx + thick / 2, cy + thick / 2)];
        [cross addLineToPoint:CGPointMake(cx + thick / 2, cy + arm)];
        [cross addLineToPoint:CGPointMake(cx - thick / 2, cy + arm)];
        [cross addLineToPoint:CGPointMake(cx - thick / 2, cy + thick / 2)];
        [cross addLineToPoint:CGPointMake(cx - arm, cy + thick / 2)];
        [cross addLineToPoint:CGPointMake(cx - arm, cy - thick / 2)];
        [cross addLineToPoint:CGPointMake(cx - thick / 2, cy - thick / 2)];
        [cross closePath];
        [[ink colorWithAlphaComponent:0.14] setFill];
        [cross fill];
        [ink setStroke];
        cross.lineWidth = 4;
        [cross stroke];
        [self draw:spot.label font:22 weight:UIFontWeightSemibold colour:ink
            centre:CGPointMake(cx, cy - (showTarget ? 18 : 0))];
        if (showTarget)
            [self draw:target font:18 weight:UIFontWeightMedium colour:valueInk
                centre:CGPointMake(cx, cy + 20)];
        return;
    }

    if (spot.round) {
        UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:spot.box];
        [[ink colorWithAlphaComponent:spot.dot ? 0.20 : 0.12] setFill];
        [circle fill];
        [ink setStroke];
        circle.lineWidth = spot.dot ? 3 : 4;
        [circle stroke];
    } else {
        UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:spot.box cornerRadius:18];
        [[ink colorWithAlphaComponent:0.14] setFill];
        [box fill];
        [ink setStroke];
        box.lineWidth = 4;
        [box stroke];
    }

    if (spot.dot) {
        // A dot has room for one short word, so that is all it gets: no captions beside it, and
        // nothing at all when it drives what its own name says.
        if (spot.label.length) {
            [self draw:spot.label font:20 weight:UIFontWeightMedium colour:ink
                centre:CGPointMake(spot.centre.x, spot.centre.y - spot.radius - 20)];
            if (showTarget)
                [self draw:target font:16 weight:UIFontWeightMedium colour:valueInk
                    centre:CGPointMake(spot.centre.x, CGRectGetMaxY(spot.box) + 20)];
        } else if (showTarget && ![target isEqualToString:@"—"]) {
            [self draw:target font:13 weight:UIFontWeightSemibold colour:valueInk
                centre:spot.centre];
        }
        return;
    }

    if (spot.round) {
        BOOL stick = [spot.source hasPrefix:@"controller.axis."];
        [self draw:spot.label font:30 weight:UIFontWeightSemibold colour:ink
            centre:CGPointMake(spot.centre.x, spot.centre.y + (showTarget ? -16 : 0))];
        if (showTarget)
            [self draw:target font:17 weight:UIFontWeightMedium colour:valueInk
                centre:CGPointMake(spot.centre.x, spot.centre.y + 18)];
        return;
    }

    [self draw:spot.label font:26 weight:UIFontWeightSemibold colour:ink
        centre:CGPointMake(CGRectGetMidX(spot.box), CGRectGetMidY(spot.box) - (showTarget ? 12 : 0))];
    if (showTarget)
        [self draw:target font:18 weight:UIFontWeightMedium colour:valueInk
            centre:CGPointMake(CGRectGetMidX(spot.box), CGRectGetMidY(spot.box) + 18)];
}

- (void)draw:(NSString *)text font:(CGFloat)size weight:(UIFontWeight)weight colour:(UIColor *)colour
      centre:(CGPoint)centre {
    if (!text.length) return;
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:size weight:weight],
                                 NSForegroundColorAttributeName: colour};
    CGSize bounds = [text sizeWithAttributes:attributes];
    [text drawAtPoint:CGPointMake(centre.x - bounds.width / 2, centre.y - bounds.height / 2)
       withAttributes:attributes];
}

// Short on purpose: this is written inside a button on a drawing. "—" is the honest answer for a
// control that drives nothing, and it is the same glyph whether the pad has the control or not -
// the chip strip beneath says which.
- (NSString *)targetTextForSource:(NSString *)source kept:(BOOL)kept {
    AKControllerBinding *binding = self.bindings[source];
    if (kept) return WKLocalized(@"controller.diagram.kept");
    if (!binding || !binding.available) return @"—";
    if (!binding.target.length || [binding.target isEqualToString:AKControllerTargetNone]) return @"—";
    return CMPadShortTarget(binding.target) ?: binding.targetDisplay;
}

#pragma mark - Touching it

- (CMPadSpot *)spotAtPoint:(CGPoint)point {
    CGPoint design = CGPointApplyAffineTransform(point,
                                                CGAffineTransformInvert([self designTransform]));
    // A finger is wider than the ink, so the hit area grows a little: a small control is not
    // something to aim at.
    CGFloat slack = 14;
    for (CMPadSpot *spot in self.spots) {
        if (spot.round) {
            CGFloat reach = spot.radius + slack;
            CGFloat dx = design.x - spot.centre.x, dy = design.y - spot.centre.y;
            if (dx * dx + dy * dy <= reach * reach) return spot;
        } else if (CGRectContainsPoint(CGRectInset(spot.box, -slack, -slack), design)) {
            return spot;
        }
    }
    return nil;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (self.waiting) return;
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    CMPadSpot *spot = [self spotAtPoint:[touch locationInView:self]];
    if (!spot) return;
    void (^handler)(NSString *) = self.onSourceTapped;
    if (handler) handler(spot.source);
}

- (NSArray *)accessibilityElements {
    NSMutableArray *elements = [NSMutableArray array];
    CGAffineTransform transform = [self designTransform];
    for (CMPadSpot *spot in self.spots) {
        UIAccessibilityElement *element =
            [[UIAccessibilityElement alloc] initWithAccessibilityContainer:self];
        element.accessibilityFrameInContainerSpace =
            CGRectApplyAffineTransform(spot.box, transform);
        element.accessibilityIdentifier = [@"controllerPad." stringByAppendingString:spot.source];
        NSString *name = spot.label.length ? spot.label : spot.source;
        element.accessibilityLabel =
            [NSString stringWithFormat:@"%@, %@", name,
                [self targetTextForSource:spot.source
                                    kept:[self.withheld containsObject:spot.source]]];
        element.accessibilityTraits = UIAccessibilityTraitButton;
        [elements addObject:element];
    }
    return elements;
}

@end
