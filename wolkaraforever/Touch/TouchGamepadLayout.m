#import "TouchGamepadLayout.h"
#import "InterfaceMode.h"
#import "LayoutStore.h"
#import "TouchControllerLog.h"
#import <GameController/GameController.h>
#include <math.h>

static NSString *const LayoutKey = @"WolkaraForeverTouchLayoutV1";
// Named arrangements the user saved, kept apart from the live one so saving never changes what
// is on screen until the user asks for it. The key itself lives in LayoutStore, which is what
// the launcher uses too; a macro because an extern NSString's value is not a C constant.
#define AKProfilesDefaultsKey AKLayoutProfilesKey
// Simple's own control positions, so Full and Simple are independent: dragging a shoulder in
// one never moves it in the other. Full keeps the key every release through v1.0.10 wrote.
static NSString *const SimplePositionsKey = @"simplePositions";
NSNotificationName const AKGamepadLayoutDidChangeNotification = @"AKGamepadLayoutDidChange";
static CGFloat Clamp(CGFloat value, CGFloat minimum, CGFloat maximum, CGFloat fallback) {
    return isfinite(value) ? MAX(minimum,MIN(maximum,value)) : fallback;
}
static CGFloat Number(id value, CGFloat fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}
// The framework's element names are phrases ("Button A", "Left Shoulder"), and the log carries
// words: this is the one place they are turned into one.
NSString *AKGamepadElementToken(NSString *element) {
    if (![element isKindOfClass:NSString.class] || !element.length) return @"element";
    static NSDictionary<NSString *, NSString *> *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = @{GCInputButtonA:@"buttonA", GCInputButtonB:@"buttonB",
                   GCInputButtonX:@"buttonX", GCInputButtonY:@"buttonY",
                   GCInputLeftShoulder:@"leftShoulder", GCInputLeftTrigger:@"leftTrigger",
                   GCInputRightTrigger:@"rightTrigger", GCInputRightShoulder:@"rightShoulder",
                   GCInputButtonMenu:@"menu",
                   GCInputLeftThumbstick:@"leftThumbstick", GCInputRightThumbstick:@"rightThumbstick",
                   GCInputLeftThumbstickButton:@"leftThumbstickButton",
                   GCInputRightThumbstickButton:@"rightThumbstickButton"};
    });
    NSString *token = tokens[element];
    if (token) return token;
    // The D-pad directions are named by this build, so they are already in the shape wanted.
    return [element hasPrefix:@"dpad."] ? element : @"element";
}
NSString *AKGamepadStickButtonElement(NSString *element) {
    if ([element isEqualToString:GCInputLeftThumbstick]) return GCInputLeftThumbstickButton;
    if ([element isEqualToString:GCInputRightThumbstick]) return GCInputRightThumbstickButton;
    return element;
}
@implementation AKGamepadLayout {
    NSUserDefaults *_defaults;
    // Full's positions and Simple's, so each arrangement keeps where its own controls were put.
    NSMutableDictionary *_positionsFull, *_positionsSimple;
    NSArray<NSDictionary<NSString *, id> *> *_abilityZones;
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
        NSDictionary *stored = [saved isKindOfClass:NSDictionary.class] ? saved : @{};
        id declared = stored[@"version"];
        _storedVersion = [declared isKindOfClass:NSNumber.class] ? [declared integerValue] : 0;
        // A dictionary a later build wrote is read as defaults and never written over. Losing
        // a newer layout to an older build is the mistake a schema version exists to stop.
        if (_storedVersion > AKLayoutSchemaVersion) {
            _newerThanThisBuild = YES;
            AKTouchControllerLog(AKTouchControllerEventLayout, @"refused",
                @{@"reason": @"newer-schema", @"version": [@(_storedVersion) stringValue]});
            stored = @{};
            _storedVersion = AKLayoutSchemaVersion;
        }
        NSDictionary *values = stored;
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
        id kept = values[@"keepFree"];
        if ([kept isKindOfClass:NSArray.class]) for (id entry in (NSArray *)kept) {
            NSDictionary *area = [self validArea:entry];
            if (area && areas.count < 16) [areas addObject:area];
        }
        _keepFree = areas;
        NSMutableDictionary<NSString *, NSString *> *mapping = [NSMutableDictionary new];
        id mapped = values[@"elements"];
        if ([mapped isKindOfClass:NSDictionary.class]) for (NSString *slot in (NSDictionary *)mapped) {
            NSString *element = ((NSDictionary *)mapped)[slot];
            if ([self knownElement:element] && [self knownSlot:slot]) mapping[slot] = element;
        }
        _elements = mapping;
        _positionsFull = [self positionsFrom:values[@"positions"]];
        _positionsSimple = [self positionsFrom:values[SimplePositionsKey]];
        // The arrangement: Full for anything that predates the key, and the whole point of
        // the migration - no installation changes what it draws because of an update.
        id mode = values[@"mode"];
        _mode = AKGamepadLayoutModeFull;
        if ([mode isKindOfClass:NSString.class]) {
            if ([mode isEqual:@"simple"] && _storedVersion >= AKLayoutSchemaVersion) _mode = AKGamepadLayoutModeSimple;
            else if (![mode isEqual:@"full"])
                AKTouchControllerLog(AKTouchControllerEventLayout, @"refused",
                    @{@"reason": @"unknown-mode", @"mode": @"full"});
        }
        _stickButtonsEnabled = Number(values[@"stickButtons"],0) != 0;
        _abilityZones = [self zonesFrom:values[@"abilityZones"]];
        if (_storedVersion < AKLayoutSchemaVersion) {
            // One write, at the moment an old dictionary is understood: the same values, now
            // stamped with the version and saying out loud that they are the Full layout.
            //
            // Only when there *is* a dictionary. Writing one for an installation that had none
            // would turn "no saved layout" into "a saved layout", and every default that
            // depends on that - the shoulder order among them - would change for a new player
            // on the strength of an update.
            if (stored.count) {
                AKTouchControllerLog(AKTouchControllerEventLayout, @"migrated",
                    @{@"from": [@(_storedVersion) stringValue], @"to": [@(AKLayoutSchemaVersion) stringValue],
                      @"mode": @"full"});
                NSMutableDictionary *upgraded = [stored mutableCopy];
                upgraded[@"version"] = @(AKLayoutSchemaVersion);
                if (!upgraded[@"mode"]) upgraded[@"mode"] = @"full";
                [defaults setObject:[upgraded copy] forKey:LayoutKey];
            }
            _storedVersion = AKLayoutSchemaVersion;
        }
    }
    return self;
}
// One mode's saved control positions, read through the same rules for both.
- (NSMutableDictionary *)positionsFrom:(id)stored {
    NSMutableDictionary *positions = [NSMutableDictionary new];
    if (![stored isKindOfClass:NSDictionary.class]) return positions;
    for (NSString *key in (NSDictionary *)stored) {
        id point = ((NSDictionary *)stored)[key];
        if (![key isKindOfClass:NSString.class] || ![point isKindOfClass:NSArray.class] || [point count] != 2) continue;
        CGFloat x = Number(point[0],NAN), y = Number(point[1],NAN);
        if (isfinite(x) && isfinite(y)) positions[key] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
    }
    return positions;
}
- (NSMutableDictionary *)positions { return _mode == AKGamepadLayoutModeSimple ? _positionsSimple : _positionsFull; }
// Down to 5%: sticks that are barely there still work, and some players want exactly that.
- (void)setOpacity:(CGFloat)value { _opacity = Clamp(value,0.05,1,0.8); }
- (void)setRearScale:(CGFloat)value { _rearScale = Clamp(value,0.8,1.5,1); }
- (void)setFrontScale:(CGFloat)value { _frontScale = Clamp(value,0.65,1.4,1); }
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds {
    CGFloat width = MAX(0,MIN(frame.size.width,bounds.size.width));
    CGFloat height = MAX(0,MIN(frame.size.height,bounds.size.height));
    CGFloat dx = MAX(0,bounds.size.width-width), dy = MAX(0,bounds.size.height-height);
    NSArray *point = [self positions][item];
    CGFloat x = point ? [point[0] doubleValue]*dx : frame.origin.x-bounds.origin.x;
    CGFloat y = point ? [point[1] doubleValue]*dy : frame.origin.y-bounds.origin.y;
    return CGRectMake(bounds.origin.x+Clamp(x,0,dx,0),bounds.origin.y+Clamp(y,0,dy,0),width,height);
}
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds {
    CGFloat dx = MAX(0,bounds.size.width-frame.size.width), dy = MAX(0,bounds.size.height-frame.size.height);
    CGFloat x = dx > 0 ? (frame.origin.x-bounds.origin.x)/dx : 0;
    CGFloat y = dy > 0 ? (frame.origin.y-bounds.origin.y)/dy : 0;
    [self positions][item] = @[@(Clamp(x,0,1,0)),@(Clamp(y,0,1,0))];
}
- (void)save {
    // A newer build's dictionary is left exactly as it is: this build cannot describe it, and
    // overwriting it would be the update that loses a layout.
    if (_newerThanThisBuild) {
        AKTouchControllerLog(AKTouchControllerEventLayout, @"refused",
                             @{@"reason": @"newer-schema"});
        return;
    }
    [_defaults setObject:@{@"version":@(AKLayoutSchemaVersion), @"mode":[self modeName],
        @"stickButtons":@(_stickButtonsEnabled), @"abilityZones":_abilityZones,
        @"opacity":@(_opacity),@"rearScale":@(_rearScale),
        @"frontScale":@(_frontScale),@"hapticsEnabled":@(_hapticsEnabled),@"swapShoulders":@(_swapShoulders),
        @"performanceOverlayEnabled":@(_performanceOverlayEnabled),@"sticksOnly":@(_sticksOnly),
        @"floatingSticks":@(_floatingSticks),@"keepFree":_keepFree,@"elements":_elements,
        @"positions":[_positionsFull copy], SimplePositionsKey:[_positionsSimple copy]} forKey:LayoutKey];
    [NSNotificationCenter.defaultCenter postNotificationName:AKGamepadLayoutDidChangeNotification object:_defaults];
}
- (void)reset {
    self.opacity = 0.8; self.rearScale = 1; self.frontScale = 1;
    self.hapticsEnabled = YES; self.swapShoulders = YES;
    self.performanceOverlayEnabled = NO;
    self.sticksOnly = AKInterfaceModeIsMobile();
    self.floatingSticks = NO;
    self.keepFree = @[];
    self.elements = @{};
    // Reset is the one control that means "as a fresh install": Full, no stick buttons, no
    // zones. Turning a feature off is the switch, which keeps what the other arrangement holds.
    _mode = AKGamepadLayoutModeFull;
    _stickButtonsEnabled = NO;
    _abilityZones = @[];
    [_positionsFull removeAllObjects]; [_positionsSimple removeAllObjects]; [self save];
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

#pragma mark - The arrangement

// Full is what every installation has had; Simple is only ever what the user chose.
- (NSString *)modeName { return _mode == AKGamepadLayoutModeSimple ? @"simple" : @"full"; }
- (void)setMode:(AKGamepadLayoutMode)mode {
    [self setModeName:(mode == AKGamepadLayoutModeSimple ? @"simple" : @"full")];
}
- (BOOL)setModeName:(NSString *)name {
    if (![name isKindOfClass:NSString.class] ||
        (![name isEqualToString:@"full"] && ![name isEqualToString:@"simple"])) {
        AKTouchControllerLog(AKTouchControllerEventLayout, @"refused",
                             @{@"reason": @"unknown-mode", @"mode": @"full"});
        return NO;
    }
    AKGamepadLayoutMode mode = [name isEqualToString:@"simple"] ? AKGamepadLayoutModeSimple : AKGamepadLayoutModeFull;
    if (_mode == mode) return YES;
    _mode = mode;
    // A mode change moves nothing: each arrangement keeps its own positions, and the other
    // one's are not touched, which is what makes turning Simple off a rollback.
    AKTouchControllerLog(AKTouchControllerEventLayout, @"changed",
                         @{@"mode": [self modeName], @"source": @"controls"});
    return YES;
}

#pragma mark - Stick buttons and ability zones

- (void)setStickButtonsEnabled:(BOOL)enabled {
    if (_stickButtonsEnabled == enabled) return;
    _stickButtonsEnabled = enabled;
    AKTouchControllerLog(AKTouchControllerEventLayout, enabled ? @"enabled" : @"disabled",
                         @{@"control": @"stickButtons"});
}

// The most zones one layout may carry. Six is a thumb's worth on a phone, and it bounds what a
// hand-edited arrangement can put on the screen.
static const NSUInteger AKGamepadMaximumZones = 6;

// A zone is an element, a centre and nothing else. The element list is the shared one, so a
// hand-edited file cannot point a zone at a stick, at a D-pad direction, or at a name of its
// own invention.
- (NSArray<NSDictionary<NSString *, id> *> *)zonesFrom:(id)stored {
    NSMutableArray *zones = [NSMutableArray new];
    if (![stored isKindOfClass:NSArray.class]) return zones;
    NSArray *allowed = AKLayoutZoneElements();
    for (id entry in (NSArray *)stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *element = ((NSDictionary *)entry)[@"element"];
        CGFloat x = Number(((NSDictionary *)entry)[@"x"], NAN);
        CGFloat y = Number(((NSDictionary *)entry)[@"y"], NAN);
        if (![element isKindOfClass:NSString.class] || ![allowed containsObject:element]) continue;
        if (!isfinite(x) || !isfinite(y)) continue;
        if (zones.count >= AKGamepadMaximumZones) break;
        [zones addObject:@{@"element": element, @"x": @(Clamp(x,0,1,0)), @"y": @(Clamp(y,0,1,0))}];
    }
    return zones;
}
- (NSArray<NSDictionary<NSString *, id> *> *)abilityZones { return _abilityZones ?: @[]; }
- (BOOL)addAbilityZoneForElement:(NSString *)element atX:(CGFloat)x y:(CGFloat)y {
    if (![element isKindOfClass:NSString.class] || ![AKLayoutZoneElements() containsObject:element]) return NO;
    if (!isfinite(x) || !isfinite(y)) return NO;
    if (_abilityZones.count >= AKGamepadMaximumZones) return NO;
    NSDictionary *zone = @{@"element": element, @"x": @(Clamp(x,0,1,0)), @"y": @(Clamp(y,0,1,0))};
    _abilityZones = [( _abilityZones ?: @[]) arrayByAddingObject:zone];
    AKTouchControllerLog(AKTouchControllerEventLayout, @"added",
                         @{@"control": @"abilityZone", @"element": AKGamepadElementToken(element),
                           @"count": [@(_abilityZones.count) stringValue], @"source": @"controls"});
    return YES;
}
- (BOOL)setAbilityZoneElement:(NSString *)element atIndex:(NSUInteger)index {
    if (![element isKindOfClass:NSString.class] || ![AKLayoutZoneElements() containsObject:element]) return NO;
    if (index >= _abilityZones.count) return NO;
    NSMutableArray *zones = [_abilityZones mutableCopy];
    NSMutableDictionary *zone = [zones[index] mutableCopy];
    zone[@"element"] = element;
    zones[index] = [zone copy];
    _abilityZones = [zones copy];
    AKTouchControllerLog(AKTouchControllerEventLayout, @"changed",
                         @{@"control": @"abilityZone", @"element": AKGamepadElementToken(element),
                           @"zone": [@(index + 1) stringValue]});
    return YES;
}
- (BOOL)moveAbilityZoneAtIndex:(NSUInteger)index toX:(CGFloat)x y:(CGFloat)y {
    if (index >= _abilityZones.count || !isfinite(x) || !isfinite(y)) return NO;
    NSMutableArray *zones = [_abilityZones mutableCopy];
    zones[index] = @{@"element": _abilityZones[index][@"element"],
                     @"x": @(Clamp(x,0,1,0)), @"y": @(Clamp(y,0,1,0))};
    _abilityZones = [zones copy];
    return YES;
}
- (void)removeAbilityZoneAtIndex:(NSUInteger)index {
    if (index >= _abilityZones.count) return;
    NSMutableArray *zones = [_abilityZones mutableCopy];
    [zones removeObjectAtIndex:index];
    _abilityZones = [zones copy];
    AKTouchControllerLog(AKTouchControllerEventLayout, @"removed",
                         @{@"control": @"abilityZone", @"count": [@(_abilityZones.count) stringValue]});
}
- (void)clearAbilityZones {
    if (!_abilityZones.count) return;
    _abilityZones = @[];
    AKTouchControllerLog(AKTouchControllerEventLayout, @"cleared", @{@"control": @"abilityZone"});
}

#pragma mark - Which gamepad element each control sends

// The slots this build places, and the elements they may send. The element names are the ones
// the game already understands; nothing here invents a button.
- (NSArray<NSString *> *)knownSlotsList {
    static NSArray *slots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        slots = @[GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                  GCInputLeftShoulder, GCInputLeftTrigger, GCInputRightTrigger, GCInputRightShoulder,
                  GCInputButtonMenu, @"dpad.up", @"dpad.right", @"dpad.down", @"dpad.left"];
    });
    return slots;
}
- (BOOL)knownSlot:(NSString *)slot {
    return [slot isKindOfClass:NSString.class] && [self.knownSlotsList containsObject:slot];
}
- (BOOL)knownElement:(NSString *)element {
    if (![element isKindOfClass:NSString.class] || !element.length) return NO;
    NSSet *allowed = [NSSet setWithArray:[self.knownSlotsList arrayByAddingObjectsFromArray:
        @[GCInputLeftThumbstick, GCInputRightThumbstick]]];
    return [allowed containsObject:element];
}
- (NSString *)elementForSlot:(NSString *)slot {
    NSString *element = _elements[slot];
    return [self knownElement:element] ? element : slot;
}
// One element per control: mapping two controls onto the same button would make one of them
// unreachable, so the second is refused instead of silently winning.
- (BOOL)setElement:(NSString *)element forSlot:(NSString *)slot {
    if (![self knownSlot:slot] || ![self knownElement:element]) return NO;
    NSMutableDictionary *mapping = [NSMutableDictionary dictionaryWithDictionary:_elements];
    for (NSString *other in mapping) {
        if (![other isEqualToString:slot] && [mapping[other] isEqualToString:element]) return NO;
    }
    if ([slot isEqualToString:element]) [mapping removeObjectForKey:slot];
    else mapping[slot] = element;
    _elements = [mapping copy];
    return YES;
}
- (void)clearElementMapping { _elements = @{}; }

#pragma mark - Arrangements, templates and saved profiles
// Everything this layout is, as property-list data. Used for the built-in starting points, for
// a profile the user saves, and for the values the config file carries.
- (NSDictionary<NSString *, id> *)arrangement {
    return @{@"mode":[self modeName], @"stickButtons":@(_stickButtonsEnabled),
             @"abilityZones":[self abilityZones],
             @"opacity":@(_opacity), @"rearScale":@(_rearScale), @"frontScale":@(_frontScale),
             @"hapticsEnabled":@(_hapticsEnabled), @"swapShoulders":@(_swapShoulders),
             @"performanceOverlayEnabled":@(_performanceOverlayEnabled),
             @"sticksOnly":@(_sticksOnly), @"floatingSticks":@(_floatingSticks),
             @"keepFree":_keepFree, @"elements":_elements,
             @"positions":[_positionsFull copy], SimplePositionsKey:[_positionsSimple copy]};
}
- (void)applyArrangement:(NSDictionary<NSString *, id> *)arrangement {
    if (![arrangement isKindOfClass:NSDictionary.class]) return;
    NSDictionary *values = arrangement;
    // The mode first: the positions below belong to whichever arrangement this leaves on.
    if ([values[@"mode"] isKindOfClass:NSString.class]) [self setModeName:values[@"mode"]];
    if ([values[@"stickButtons"] isKindOfClass:NSNumber.class])
        self.stickButtonsEnabled = [values[@"stickButtons"] boolValue];
    if ([values[@"abilityZones"] isKindOfClass:NSArray.class])
        _abilityZones = [self zonesFrom:values[@"abilityZones"]];
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
    NSMutableDictionary<NSString *, NSString *> *mappedElements = [NSMutableDictionary new];
    if ([values[@"elements"] isKindOfClass:NSDictionary.class]) {
        for (NSString *slot in (NSDictionary *)values[@"elements"]) {
            NSString *element = ((NSDictionary *)values[@"elements"])[slot];
            if ([self knownElement:element] && [self knownSlot:slot]) mappedElements[slot] = element;
        }
    }
    _elements = mappedElements;
    // Each arrangement's positions are replaced only when the arrangement carries them, so a
    // template that changes the mode never empties the other one's saved places.
    if ([values[@"positions"] isKindOfClass:NSDictionary.class])
        _positionsFull = [self positionsFrom:values[@"positions"]];
    if ([values[SimplePositionsKey] isKindOfClass:NSDictionary.class])
        _positionsSimple = [self positionsFrom:values[SimplePositionsKey]];
}
// The built-in starting points, from the one place they are defined.
+ (NSArray<NSString *> *)templateNames { return AKLayoutTemplateNames(); }
- (void)applyTemplateNamed:(NSString *)name {
    NSDictionary *payload = AKLayoutTemplatePayload(name);
    if (payload) [self applyArrangement:payload];
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
