#import "LayoutStore.h"
#import <GameController/GameController.h>

NSString *const AKLayoutStoredKey = @"WolkaraForeverTouchLayoutV1";
NSString *const AKLayoutProfilesKey = @"WolkaraForeverProfilesV1";
NSInteger const AKLayoutSchemaVersion = 2;
NSString *const AKLayoutModeFull = @"full";
NSString *const AKLayoutModeSimple = @"simple";
// The most zones a layout may carry. Six is a thumb's worth on a phone and it bounds what a
// hand-edited or imported arrangement can put on the screen.
static const NSUInteger AKLayoutMaximumZones = 6;

// The stored dictionary, ready to be written: a mutable copy of whatever is there, with the
// schema version this build writes. Every writer below goes through it, so a writer can never
// leave a v1 dictionary behind that the next read would migrate back to Full - which is
// exactly how a choice made in the launcher would have been undone by the adapter.
static NSMutableDictionary *MutableLayout(NSUserDefaults *defaults) {
    id stored = [defaults objectForKey:AKLayoutStoredKey];
    NSMutableDictionary *layout = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy]
                                                                           : [NSMutableDictionary new];
    layout[@"version"] = @(AKLayoutSchemaVersion);
    return layout;
}
static NSMutableDictionary *StoredValues(NSUserDefaults *defaults) {
    id stored = [defaults objectForKey:AKLayoutStoredKey];
    return [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary new];
}

// The starting points. "plain" is the fixed rings every release through v1.0.9 had; "duo" is
// the mobile arrangement with nothing reserved; "duo-addon" reserves the left edge and the
// bottom centre, where an installed interface usually puts a bar and a chat strip.
static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *Templates(void) {
    static NSDictionary *templates;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        templates = @{
            @"plain": @{@"sticksOnly":@NO, @"floatingSticks":@NO, @"keepFree":@[]},
            @"duo": @{@"sticksOnly":@YES, @"floatingSticks":@YES, @"keepFree":@[]},
            @"duo-addon": @{@"sticksOnly":@YES, @"floatingSticks":@YES, @"keepFree":@[
                @{@"x":@0.0, @"y":@0.30, @"w":@0.13, @"h":@0.70},
                @{@"x":@0.28, @"y":@0.925, @"w":@0.44, @"h":@0.075},
            ]},
        };
    });
    return templates;
}

NSArray<NSString *> *AKLayoutTemplateNames(void) {
    return [Templates().allKeys sortedArrayUsingSelector:@selector(compare:)];
}
NSDictionary<NSString *, id> *AKLayoutTemplatePayload(NSString *name) {
    return [name isKindOfClass:NSString.class] ? Templates()[name] : nil;
}

void AKLayoutApplyPayload(NSUserDefaults *defaults, NSDictionary<NSString *, id> *payload) {
    if (![payload isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary *layout = MutableLayout(defaults);
    [layout addEntriesFromDictionary:payload];
    // A template carries the arrangement keys it is about and nothing else; the version is
    // this build's, so it is written after the merge rather than being taken from the payload.
    layout[@"version"] = @(AKLayoutSchemaVersion);
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
}

BOOL AKLayoutApplyTemplate(NSUserDefaults *defaults, NSString *name) {
    NSDictionary *payload = AKLayoutTemplatePayload(name);
    if (!payload) return NO;
    AKLayoutApplyPayload(defaults, payload);
    return YES;
}

NSArray<NSString *> *AKLayoutSavedNames(NSUserDefaults *defaults) {
    NSDictionary *all = [defaults dictionaryForKey:AKLayoutProfilesKey];
    return all ? [all.allKeys sortedArrayUsingSelector:@selector(compare:)] : @[];
}

BOOL AKLayoutSaveProfile(NSUserDefaults *defaults, NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length || name.length > 40) return NO;
    id stored = [defaults objectForKey:AKLayoutStoredKey];
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:
        ([defaults dictionaryForKey:AKLayoutProfilesKey] ?: @{})];
    all[name] = [stored isKindOfClass:NSDictionary.class] ? stored : @{};
    [defaults setObject:[all copy] forKey:AKLayoutProfilesKey];
    return YES;
}

BOOL AKLayoutApplyProfile(NSUserDefaults *defaults, NSString *name) {
    NSDictionary *all = [defaults dictionaryForKey:AKLayoutProfilesKey];
    id saved = [all isKindOfClass:NSDictionary.class] ? all[name] : nil;
    if (![saved isKindOfClass:NSDictionary.class]) return NO;
    AKLayoutApplyPayload(defaults, saved);
    return YES;
}

NSArray<NSString *> *AKLayoutSlots(void) {
    static NSArray *slots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        slots = @[GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                  GCInputLeftShoulder, GCInputLeftTrigger, GCInputRightTrigger, GCInputRightShoulder,
                  GCInputButtonMenu, @"dpad.up", @"dpad.right", @"dpad.down", @"dpad.left"];
    });
    return slots;
}
NSArray<NSString *> *AKLayoutElements(void) {
    static NSArray *elements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        elements = [AKLayoutSlots() arrayByAddingObjectsFromArray:
            @[GCInputLeftThumbstick, GCInputRightThumbstick]];
    });
    return elements;
}
static NSDictionary<NSString *, NSString *> *CurrentMapping(NSUserDefaults *defaults) {
    id stored = [defaults objectForKey:AKLayoutStoredKey];
    id mapping = [stored isKindOfClass:NSDictionary.class] ? ((NSDictionary *)stored)[@"elements"] : nil;
    return [mapping isKindOfClass:NSDictionary.class] ? mapping : @{};
}
NSString *AKLayoutElementForSlot(NSUserDefaults *defaults, NSString *slot) {
    NSString *element = CurrentMapping(defaults)[slot];
    return element && [AKLayoutElements() containsObject:element] ? element : slot;
}
BOOL AKLayoutSetElement(NSUserDefaults *defaults, NSString *element, NSString *slot) {
    if (![AKLayoutSlots() containsObject:slot] || ![AKLayoutElements() containsObject:element]) return NO;
    NSMutableDictionary *mapping = [NSMutableDictionary dictionaryWithDictionary:CurrentMapping(defaults)];
    for (NSString *other in mapping) {
        if (![other isEqualToString:slot] && [mapping[other] isEqualToString:element]) return NO;
    }
    if ([slot isEqualToString:element]) [mapping removeObjectForKey:slot];
    else mapping[slot] = element;
    NSMutableDictionary *layout = MutableLayout(defaults);
    layout[@"elements"] = [mapping copy];
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
    return YES;
}

BOOL AKLayoutAddKeepFreeArea(NSUserDefaults *defaults, CGFloat x, CGFloat y,
                             CGFloat width, CGFloat height) {
    CGFloat values[4] = {x, y, width, height};
    for (int i = 0; i < 4; i++) if (!isfinite(values[i])) return NO;
    if (width < 0.02 || height < 0.02) return NO;
    x = MAX(0, MIN(1, x)); y = MAX(0, MIN(1, y));
    width = MIN(MAX(0.02, width), 1 - x); height = MIN(MAX(0.02, height), 1 - y);
    NSMutableDictionary *layout = MutableLayout(defaults);
    NSMutableArray *areas = [NSMutableArray array];
    id existing = layout[@"keepFree"];
    if ([existing isKindOfClass:NSArray.class]) [areas addObjectsFromArray:existing];
    if (areas.count >= 16) return NO;
    [areas addObject:@{@"x":@(x), @"y":@(y), @"w":@(width), @"h":@(height)}];
    layout[@"keepFree"] = [areas copy];
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
    return YES;
}
BOOL AKLayoutDeleteProfile(NSUserDefaults *defaults, NSString *name) {
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:
        ([defaults dictionaryForKey:AKLayoutProfilesKey] ?: @{})];
    if (!all[name]) return NO;
    [all removeObjectForKey:name];
    [defaults setObject:[all copy] forKey:AKLayoutProfilesKey];
    return YES;
}

#pragma mark - The arrangement, its version, and what it carries

static BOOL AKLayoutKnownMode(NSString *mode) {
    return [mode isKindOfClass:NSString.class] &&
        ([mode isEqualToString:AKLayoutModeFull] || [mode isEqualToString:AKLayoutModeSimple]);
}

// A dictionary a later build wrote is not ours to interpret or to rewrite: everything it says
// reads as this build's defaults, and every writer below refuses rather than overwriting it.
// Losing a newer layout to an older build is the one mistake a schema version exists to stop.
static BOOL AKLayoutIsFromANewerBuild(NSDictionary *values) {
    id version = values[@"version"];
    return [version isKindOfClass:NSNumber.class] && [version integerValue] > AKLayoutSchemaVersion;
}

NSString *AKLayoutMode(NSUserDefaults *defaults) {
    NSDictionary *values = StoredValues(defaults);
    if (AKLayoutIsFromANewerBuild(values)) return AKLayoutModeFull;
    id mode = values[@"mode"];
    return [mode isKindOfClass:NSString.class] && [mode isEqualToString:AKLayoutModeSimple]
        ? AKLayoutModeSimple : AKLayoutModeFull;
}

BOOL AKLayoutSetMode(NSUserDefaults *defaults, NSString *mode) {
    if (!AKLayoutKnownMode(mode)) return NO;
    if (AKLayoutIsFromANewerBuild(StoredValues(defaults))) return NO;
    NSMutableDictionary *layout = MutableLayout(defaults);
    layout[@"mode"] = mode;
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
    return YES;
}

BOOL AKLayoutStickButtons(NSUserDefaults *defaults) {
    id stored = StoredValues(defaults)[@"stickButtons"];
    return [stored isKindOfClass:NSNumber.class] && [stored boolValue];
}

void AKLayoutSetStickButtons(NSUserDefaults *defaults, BOOL enabled) {
    if (AKLayoutIsFromANewerBuild(StoredValues(defaults))) return;
    NSMutableDictionary *layout = MutableLayout(defaults);
    layout[@"stickButtons"] = @(enabled);
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
}

NSArray<NSString *> *AKLayoutZoneElements(void) {
    static NSArray *elements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *buttons = [NSMutableArray new];
        // Every control but the D-pad directions: a zone presses one button, and a direction
        // is not a button.
        for (NSString *slot in AKLayoutSlots()) if (![slot hasPrefix:@"dpad."]) [buttons addObject:slot];
        elements = [buttons copy];
    });
    return elements;
}

static NSArray<NSDictionary<NSString *, id> *> *AKLayoutValidZones(id stored) {
    NSMutableArray *zones = [NSMutableArray new];
    if (![stored isKindOfClass:NSArray.class]) return zones;
    for (id entry in (NSArray *)stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id element = ((NSDictionary *)entry)[@"element"];
        id x = ((NSDictionary *)entry)[@"x"], y = ((NSDictionary *)entry)[@"y"];
        if (![element isKindOfClass:NSString.class] || ![AKLayoutZoneElements() containsObject:element]) continue;
        if (![x isKindOfClass:NSNumber.class] || ![y isKindOfClass:NSNumber.class]) continue;
        CGFloat fx = [x doubleValue], fy = [y doubleValue];
        if (!isfinite(fx) || !isfinite(fy)) continue;
        if (zones.count >= AKLayoutMaximumZones) break;
        [zones addObject:@{@"element": element,
                           @"x": @(MAX(0, MIN(1, fx))), @"y": @(MAX(0, MIN(1, fy)))}];
    }
    return zones;
}

NSArray<NSDictionary<NSString *, id> *> *AKLayoutAbilityZones(NSUserDefaults *defaults) {
    return AKLayoutValidZones(StoredValues(defaults)[@"abilityZones"]);
}

BOOL AKLayoutAddAbilityZone(NSUserDefaults *defaults, NSString *element, CGFloat x, CGFloat y) {
    if (![element isKindOfClass:NSString.class] || ![AKLayoutZoneElements() containsObject:element]) return NO;
    if (!isfinite(x) || !isfinite(y)) return NO;
    NSDictionary *values = StoredValues(defaults);
    if (AKLayoutIsFromANewerBuild(values)) return NO;
    NSArray *zones = AKLayoutValidZones(values[@"abilityZones"]);
    if (zones.count >= AKLayoutMaximumZones) return NO;
    NSMutableDictionary *layout = MutableLayout(defaults);
    layout[@"abilityZones"] = [zones arrayByAddingObject:
        @{@"element": element, @"x": @(MAX(0, MIN(1, x))), @"y": @(MAX(0, MIN(1, y)))}];
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
    return YES;
}

BOOL AKLayoutSetAbilityZoneElement(NSUserDefaults *defaults, NSString *element, NSUInteger index) {
    if (![element isKindOfClass:NSString.class] || ![AKLayoutZoneElements() containsObject:element]) return NO;
    NSDictionary *values = StoredValues(defaults);
    if (AKLayoutIsFromANewerBuild(values)) return NO;
    NSMutableArray *zones = [AKLayoutValidZones(values[@"abilityZones"]) mutableCopy];
    if (index >= zones.count) return NO;
    NSMutableDictionary *zone = [zones[index] mutableCopy];
    zone[@"element"] = element;
    zones[index] = [zone copy];
    NSMutableDictionary *layout = MutableLayout(defaults);
    layout[@"abilityZones"] = [zones copy];
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
    return YES;
}

void AKLayoutClearAbilityZones(NSUserDefaults *defaults) {
    if (AKLayoutIsFromANewerBuild(StoredValues(defaults))) return;
    NSMutableDictionary *layout = MutableLayout(defaults);
    [layout removeObjectForKey:@"abilityZones"];
    [defaults setObject:[layout copy] forKey:AKLayoutStoredKey];
}
