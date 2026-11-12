#import "LayoutStore.h"

NSString *const AKLayoutStoredKey = @"WolkaraForeverTouchLayoutV1";
NSString *const AKLayoutProfilesKey = @"WolkaraForeverProfilesV1";

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
    id stored = [defaults objectForKey:AKLayoutStoredKey];
    NSMutableDictionary *layout = [stored isKindOfClass:NSDictionary.class]
        ? [stored mutableCopy] : [NSMutableDictionary new];
    [layout addEntriesFromDictionary:payload];
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

BOOL AKLayoutDeleteProfile(NSUserDefaults *defaults, NSString *name) {
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:
        ([defaults dictionaryForKey:AKLayoutProfilesKey] ?: @{})];
    if (!all[name]) return NO;
    [all removeObjectForKey:name];
    [defaults setObject:[all copy] forKey:AKLayoutProfilesKey];
    return YES;
}
