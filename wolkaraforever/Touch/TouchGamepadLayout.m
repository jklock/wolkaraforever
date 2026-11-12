#import "TouchGamepadLayout.h"
#import "InterfaceMode.h"
#include <math.h>

static NSString *const LayoutKey = @"WolkaraForeverTouchLayoutV1";
// Named arrangements the user saved, kept apart from the live one so saving never changes what
// is on screen until the user asks for it.
static NSString *const AKProfilesDefaultsKey = @"WolkaraForeverProfilesV1";
NSNotificationName const AKGamepadLayoutDidChangeNotification = @"AKGamepadLayoutDidChange";
static CGFloat Clamp(CGFloat value, CGFloat minimum, CGFloat maximum, CGFloat fallback) {
    return isfinite(value) ? MAX(minimum,MIN(maximum,value)) : fallback;
}
static CGFloat Number(id value, CGFloat fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}
@implementation AKGamepadLayout {
    NSUserDefaults *_defaults;
    NSMutableDictionary *_positions;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _defaults = defaults;
        id saved = [defaults objectForKey:LayoutKey];
        // Import the former app's preferences once; current settings take priority.
        if (!saved) {
            id legacy = [defaults objectForKey:@"WowkaraTouchLayoutV1"];
            if ([legacy isKindOfClass:NSDictionary.class]) {
                saved = legacy;
                [defaults setObject:legacy forKey:LayoutKey];
            }
        }
        NSDictionary *values = [saved isKindOfClass:NSDictionary.class] ? saved : @{};
        self.opacity = Number(values[@"opacity"],0.8);
        self.rearScale = Number(values[@"rearScale"],1);
        self.frontScale = Number(values[@"frontScale"],1);
        self.hapticsEnabled = Number(values[@"hapticsEnabled"],1) != 0;
        // Keep existing layouts in their original order. New/reset layouts put
        // triggers inside; an explicit stored choice always takes precedence.
        self.swapShoulders = Number(values[@"swapShoulders"],values.count ? 0 : 1) != 0;
        self.performanceOverlayEnabled = Number(values[@"performanceOverlayEnabled"],0) != 0;
        // Only a mobile-interface default: Standard keeps every button, as every release
        // through v1.0.7 has, even for a layout saved before this key existed.
        self.sticksOnly = Number(values[@"sticksOnly"],AKInterfaceModeIsMobile() ? 1 : 0) != 0;
        // Off until the player asks for it: the fixed rings are what every release through
        // v1.0.9 has, and the corner jump reserves the space the fan's tab sits in, so turning
        // it on silently would move an arrangement someone already uses.
        self.floatingSticks = Number(values[@"floatingSticks"],0) != 0;
        // Only what the user stored: an empty list reserves nothing.
        NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *areas = [NSMutableArray new];
        id stored = values[@"keepFree"];
        if ([stored isKindOfClass:NSArray.class]) for (id entry in (NSArray *)stored) {
            NSDictionary *area = [self validArea:entry];
            if (area && areas.count < 16) [areas addObject:area];
        }
        _keepFree = areas;
        _positions = [NSMutableDictionary new];
        id positions = values[@"positions"];
        if ([positions isKindOfClass:NSDictionary.class]) for (NSString *key in positions) {
            id point = positions[key];
            if (![key isKindOfClass:NSString.class] || ![point isKindOfClass:NSArray.class] || [point count] != 2) continue;
            CGFloat x = Number(point[0],NAN), y = Number(point[1],NAN);
            if (isfinite(x) && isfinite(y)) _positions[key] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
        }
    }
    return self;
}
// Down to 5%: sticks that are barely there still work, and some players want exactly that.
- (void)setOpacity:(CGFloat)value { _opacity = Clamp(value,0.05,1,0.8); }
- (void)setRearScale:(CGFloat)value { _rearScale = Clamp(value,0.8,1.5,1); }
- (void)setFrontScale:(CGFloat)value { _frontScale = Clamp(value,0.65,1.4,1); }
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds {
    CGFloat width = MAX(0,MIN(frame.size.width,bounds.size.width));
    CGFloat height = MAX(0,MIN(frame.size.height,bounds.size.height));
    CGFloat dx = MAX(0,bounds.size.width-width), dy = MAX(0,bounds.size.height-height);
    NSArray *point = _positions[item];
    CGFloat x = point ? [point[0] doubleValue]*dx : frame.origin.x-bounds.origin.x;
    CGFloat y = point ? [point[1] doubleValue]*dy : frame.origin.y-bounds.origin.y;
    return CGRectMake(bounds.origin.x+Clamp(x,0,dx,0),bounds.origin.y+Clamp(y,0,dy,0),width,height);
}
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds {
    CGFloat dx = MAX(0,bounds.size.width-frame.size.width), dy = MAX(0,bounds.size.height-frame.size.height);
    CGFloat x = dx > 0 ? (frame.origin.x-bounds.origin.x)/dx : 0;
    CGFloat y = dy > 0 ? (frame.origin.y-bounds.origin.y)/dy : 0;
    _positions[item] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
}
- (void)save {
    [_defaults setObject:@{@"opacity":@(_opacity),@"rearScale":@(_rearScale),
        @"frontScale":@(_frontScale),@"hapticsEnabled":@(_hapticsEnabled),@"swapShoulders":@(_swapShoulders),
        @"performanceOverlayEnabled":@(_performanceOverlayEnabled),@"sticksOnly":@(_sticksOnly),
        @"floatingSticks":@(_floatingSticks),@"keepFree":_keepFree,@"positions":_positions} forKey:LayoutKey];
    [NSNotificationCenter.defaultCenter postNotificationName:AKGamepadLayoutDidChangeNotification object:_defaults];
}
- (void)reset {
    self.opacity = 0.8; self.rearScale = 1; self.frontScale = 1;
    self.hapticsEnabled = YES; self.swapShoulders = YES;
    self.performanceOverlayEnabled = NO;
    self.sticksOnly = AKInterfaceModeIsMobile();
    self.floatingSticks = NO;
    self.keepFree = @[];
    [_positions removeAllObjects]; [self save];
}
// A stored or proposed area, or nil when it is not four finite fractions of the screen. Kept
// inside the screen rather than rejected for a rounding error, and never smaller than 1%.
- (nullable NSDictionary<NSString *, NSNumber *> *)validArea:(id)entry {
    if (![entry isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *values = entry;
    CGFloat x = Number(values[@"x"], NAN), y = Number(values[@"y"], NAN);
    CGFloat w = Number(values[@"w"], NAN), h = Number(values[@"h"], NAN);
    if (!isfinite(x) || !isfinite(y) || !isfinite(w) || !isfinite(h)) return nil;
    if (w < 0.01 || h < 0.01) return nil;
    x = Clamp(x,0,1,0); y = Clamp(y,0,1,0);
    w = MIN(Clamp(w,0.01,1,0.01),1-x); h = MIN(Clamp(h,0.01,1,0.01),1-y);
    return @{@"x":@(x),@"y":@(y),@"w":@(w),@"h":@(h)};
}
- (void)addKeepFreeAreaWithX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w height:(CGFloat)h {
    NSDictionary *area = [self validArea:@{@"x":@(x),@"y":@(y),@"w":@(w),@"h":@(h)}];
    if (!area || _keepFree.count >= 16) return;
    _keepFree = [_keepFree arrayByAddingObject:area];
}
- (void)clearKeepFreeAreas { _keepFree = @[]; }

#pragma mark - Arrangements, templates and saved profiles

// Everything this layout is, as property-list data. Used for the built-in starting points, for
// a profile the user saves, and for the values the config file carries.
- (NSDictionary<NSString *, id> *)arrangement {
    return @{@"opacity":@(_opacity), @"rearScale":@(_rearScale), @"frontScale":@(_frontScale),
             @"hapticsEnabled":@(_hapticsEnabled), @"swapShoulders":@(_swapShoulders),
             @"performanceOverlayEnabled":@(_performanceOverlayEnabled),
             @"sticksOnly":@(_sticksOnly), @"floatingSticks":@(_floatingSticks),
             @"keepFree":_keepFree, @"positions":[_positions copy]};
}
- (void)applyArrangement:(NSDictionary<NSString *, id> *)arrangement {
    if (![arrangement isKindOfClass:NSDictionary.class]) return;
    NSDictionary *values = arrangement;
    self.opacity = Number(values[@"opacity"],_opacity);
    self.rearScale = Number(values[@"rearScale"],_rearScale);
    self.frontScale = Number(values[@"frontScale"],_frontScale);
    if ([values[@"hapticsEnabled"] isKindOfClass:NSNumber.class]) _hapticsEnabled = [values[@"hapticsEnabled"] boolValue];
    if ([values[@"swapShoulders"] isKindOfClass:NSNumber.class]) _swapShoulders = [values[@"swapShoulders"] boolValue];
    if ([values[@"performanceOverlayEnabled"] isKindOfClass:NSNumber.class]) _performanceOverlayEnabled = [values[@"performanceOverlayEnabled"] boolValue];
    if ([values[@"sticksOnly"] isKindOfClass:NSNumber.class]) _sticksOnly = [values[@"sticksOnly"] boolValue];
    if ([values[@"floatingSticks"] isKindOfClass:NSNumber.class]) _floatingSticks = [values[@"floatingSticks"] boolValue];
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *areas = [NSMutableArray new];
    id kept = values[@"keepFree"];
    if ([kept isKindOfClass:NSArray.class]) for (id entry in (NSArray *)kept) {
        NSDictionary *area = [self validArea:entry];
        if (area && areas.count < 16) [areas addObject:area];
    }
    _keepFree = areas;
    if ([values[@"positions"] isKindOfClass:NSDictionary.class]) {
        [_positions removeAllObjects];
        for (NSString *key in (NSDictionary *)values[@"positions"]) {
            id point = ((NSDictionary *)values[@"positions"])[key];
            if (![key isKindOfClass:NSString.class] || ![point isKindOfClass:NSArray.class] || [point count] != 2) continue;
            CGFloat x = Number(point[0],NAN), y = Number(point[1],NAN);
            if (isfinite(x) && isfinite(y)) _positions[key] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
        }
    }
}
// The built-in starting points. "duo" is the mobile arrangement with nothing reserved; the
// add-on one reserves the left edge and the bottom centre, where an installed interface usually
// puts a bar and a chat strip, so the thumbs' halves do not swallow them.
+ (NSArray<NSString *> *)templateNames { return @[@"plain", @"duo", @"duo-addon"]; }
- (void)applyTemplateNamed:(NSString *)name {
    if ([name isEqual:@"plain"]) {
        [self applyArrangement:@{@"sticksOnly":@NO, @"floatingSticks":@NO, @"keepFree":@[]}];
    } else if ([name isEqual:@"duo"]) {
        [self applyArrangement:@{@"sticksOnly":@YES, @"floatingSticks":@YES, @"keepFree":@[]}];
    } else if ([name isEqual:@"duo-addon"]) {
        [self applyArrangement:@{@"sticksOnly":@YES, @"floatingSticks":@YES, @"keepFree":@[
            @{@"x":@0.0, @"y":@0.30, @"w":@0.13, @"h":@0.70},      // a bar down the left edge
            @{@"x":@0.28, @"y":@0.925, @"w":@0.44, @"h":@0.075},    // the chat strip
        ]}];
    }
}
- (NSArray<NSString *> *)savedProfileNames {
    NSDictionary *all = [_defaults dictionaryForKey:AKProfilesDefaultsKey];
    return [[all.allKeys sortedArrayUsingSelector:@selector(compare:)] copy];
}
- (BOOL)saveAsProfileNamed:(NSString *)name {
    if (!name.length || name.length > 40) return NO;
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:
        ([_defaults dictionaryForKey:AKProfilesDefaultsKey] ?: @{})];
    all[name] = [self arrangement];
    [_defaults setObject:[all copy] forKey:AKProfilesDefaultsKey];
    return YES;
}
- (BOOL)applyProfileNamed:(NSString *)name {
    NSDictionary *all = [_defaults dictionaryForKey:AKProfilesDefaultsKey];
    id saved = [all isKindOfClass:NSDictionary.class] ? all[name] : nil;
    if (![saved isKindOfClass:NSDictionary.class]) return NO;
    [self applyArrangement:saved];
    return YES;
}
- (BOOL)deleteProfileNamed:(NSString *)name {
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:
        ([_defaults dictionaryForKey:AKProfilesDefaultsKey] ?: @{})];
    if (!all[name]) return NO;
    [all removeObjectForKey:name];
    [_defaults setObject:[all copy] forKey:AKProfilesDefaultsKey];
    return YES;
}
@end
