#import "ControllerProfile.h"

#import "../App/WolkaraForeverLog.h"

#import "../Input/InputElement.h"

NSString *const AKControllerTargetNone = @"virtual.none";

// Bumped when the vocabulary changes shape. A stored table with another version is
// ignored rather than half-read: the defaults are always a usable one-to-one pad, so
// losing an unreadable table costs the user a choice, not a working controller.
// 2 added claimed controls. Claims are gone: which inputs Tolkara keeps is its own fact,
// owned by the feature that uses them (Voice & Input for dictation), and this file stores
// only what each control drives. A version 2 table still loads - its "actions" key is now
// simply unknown and ignored, so its mappings survive and nothing is withheld by it.
static NSInteger const AKControllerProfileVersion = 2;
static NSInteger const AKControllerProfileOldestReadableVersion = 1;
static NSString *const AKControllerProfileKeyPrefix = @"WolkaraForeverControllerProfile.";

#pragma mark - Targets

@implementation AKControllerTarget

- (instancetype)initWithIdentifier:(NSString *)identifier display:(NSString *)display kind:(AKControllerTargetKind)kind {
    if ((self = [super init])) {
        _identifier = [identifier copy];
        _display = [display copy];
        _kind = kind;
    }
    return self;
}

// The list is exactly what AKTouchGamepad can drive on the hidden GCVirtualController:
// the elements it declares, plus the D-pad and Menu that the connected extended profile
// provides. Options, Home, Share, the stick clicks and the paddles have no target here -
// that is a property of Apple's virtual controller, not an omission - so the page shows
// them as unavailable rather than offering a choice that cannot work.
+ (NSArray<AKControllerTarget *> *)targets {
    static NSArray<AKControllerTarget *> *targets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        targets = @[
            [[self alloc] initWithIdentifier:@"virtual.button.a" display:@"A" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.b" display:@"B" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.x" display:@"X" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.y" display:@"Y" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.left.shoulder" display:@"Left shoulder" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.right.shoulder" display:@"Right shoulder" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.left.trigger" display:@"Left trigger" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.right.trigger" display:@"Right trigger" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.button.menu" display:@"Menu" kind:AKControllerTargetKindButton],
            [[self alloc] initWithIdentifier:@"virtual.stick.left" display:@"Left stick" kind:AKControllerTargetKindAxis],
            [[self alloc] initWithIdentifier:@"virtual.stick.right" display:@"Right stick" kind:AKControllerTargetKindAxis],
            [[self alloc] initWithIdentifier:@"virtual.dpad" display:@"D-pad" kind:AKControllerTargetKindAxis],
        ];
    });
    return targets;
}

+ (nullable instancetype)targetWithIdentifier:(nullable NSString *)identifier {
    if (!identifier.length || [identifier isEqualToString:AKControllerTargetNone]) return nil;
    for (AKControllerTarget *target in self.targets)
        if ([target.identifier isEqualToString:identifier]) return target;
    return nil;
}

- (NSString *)description { return self.identifier; }

@end

#pragma mark - Bindings

// The rows are built here and read everywhere else, so the write side stays private to
// this file rather than in the header.
@interface AKControllerBinding ()
@property (nonatomic, copy, readwrite) NSString *source;
@property (nonatomic, copy, readwrite) NSString *target;
@property (nonatomic, copy, readwrite) NSString *sourceDisplay;
@property (nonatomic, copy, readwrite) NSString *targetDisplay;
@property (nonatomic, readwrite) BOOL available;
@property (nonatomic, readwrite) BOOL reserved;
@property (nonatomic, readwrite) BOOL discovered;
@end

@implementation AKControllerBinding
@end

#pragma mark - Profile

// One-to-one: every physical control the virtual pad has a target for drives the
// obviously corresponding one. Nothing is moved, swapped or added, so switching the
// feature on changes where the pad's input comes from and nothing about what it means.
// A control with no target is mapped to AKControllerTargetNone explicitly, which is what
// lets the page say "not available" instead of pretending the row does not exist.
static NSArray<NSArray<NSString *> *> *AKControllerDefaultPairs(void) {
    static NSArray<NSArray<NSString *> *> *pairs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pairs = @[
            @[@"controller.button.a", @"virtual.button.a"],
            @[@"controller.button.b", @"virtual.button.b"],
            @[@"controller.button.x", @"virtual.button.x"],
            @[@"controller.button.y", @"virtual.button.y"],
            @[@"controller.button.left.shoulder", @"virtual.button.left.shoulder"],
            @[@"controller.button.right.shoulder", @"virtual.button.right.shoulder"],
            @[@"controller.button.left.trigger", @"virtual.button.left.trigger"],
            @[@"controller.button.right.trigger", @"virtual.button.right.trigger"],
            @[@"controller.button.menu", @"virtual.button.menu"],
            @[@"controller.button.options", AKControllerTargetNone],
            @[@"controller.button.home", AKControllerTargetNone],
            @[@"controller.button.share", AKControllerTargetNone],
            @[@"controller.button.left.thumbstick.button", AKControllerTargetNone],
            @[@"controller.button.right.thumbstick.button", AKControllerTargetNone],
            @[@"controller.button.paddle1", AKControllerTargetNone],
            @[@"controller.button.paddle2", AKControllerTargetNone],
            @[@"controller.button.paddle3", AKControllerTargetNone],
            @[@"controller.button.paddle4", AKControllerTargetNone],
            @[@"controller.axis.left.thumbstick", @"virtual.stick.left"],
            @[@"controller.axis.right.thumbstick", @"virtual.stick.right"],
            @[@"dpad.dpad", @"virtual.dpad"],
        ];
    });
    return pairs;
}

@implementation AKControllerProfile {
    NSMutableDictionary<NSString *, NSString *> *_map;
    // Controls this model has beyond the standard layout, in the order they were seen.
    NSMutableOrderedSet<NSString *> *_observed;
    NSUserDefaults *_defaults;
}

+ (NSArray<NSString *> *)sourceElements {
    NSMutableArray<NSString *> *sources = [NSMutableArray array];
    for (NSArray<NSString *> *pair in AKControllerDefaultPairs()) [sources addObject:pair[0]];
    return sources;
}

+ (NSString *)defaultsKeyForIdentity:(NSString *)identity {
    return [AKControllerProfileKeyPrefix stringByAppendingString:identity];
}

- (instancetype)initWithIdentity:(NSString *)identity
                      vendorName:(nullable NSString *)vendorName
                 productCategory:(nullable NSString *)productCategory
                        defaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _identity = [identity copy];
        _defaults = defaults ?: NSUserDefaults.standardUserDefaults;
        NSString *vendor = vendorName.length ? vendorName : @"Controller";
        _displayName = productCategory.length
            ? [NSString stringWithFormat:@"%@ — %@", vendor, productCategory] : vendor;
        _map = [NSMutableDictionary dictionary];
        for (NSArray<NSString *> *pair in AKControllerDefaultPairs()) _map[pair[0]] = pair[1];
        [self load];
    }
    return self;
}

- (void)load {
    id stored = [_defaults objectForKey:[AKControllerProfile defaultsKeyForIdentity:_identity]];
    if (![stored isKindOfClass:NSDictionary.class]) return;
    NSDictionary *table = stored[@"map"];
    NSInteger version = [stored[@"version"] isKindOfClass:NSNumber.class]
        ? [stored[@"version"] integerValue] : -1;
    if (version < AKControllerProfileOldestReadableVersion ||
        version > AKControllerProfileVersion ||
        ![table isKindOfClass:NSDictionary.class]) {
        // An older or larger table is not guessed at. The defaults are a working pad.
        WKLog("input", @"controller profile %@: stored version %ld is outside %ld-%ld, using the default",
              _identity, (long)version, (long)AKControllerProfileOldestReadableVersion,
              (long)AKControllerProfileVersion);
        return;
    }
    NSUInteger applied = 0, rejected = 0;
    for (NSString *source in table) {
        id target = table[source];
        if (![target isKindOfClass:NSString.class]) { rejected++; continue; }
        // A target the virtual pad no longer has would route a press into nothing we can
        // set, so it falls back to the default for that source - visible as "not changed".
        BOOL known = [target isEqualToString:AKControllerTargetNone] ||
                     [AKControllerTarget targetWithIdentifier:target] != nil;
        if (!known || !_map[source]) { rejected++; continue; }
        _map[source] = target;
        applied++;
    }
    // Controls this model was seen to have beyond the standard layout. They are what makes a
    // controller's extra buttons appear at all; without them a button iOS reports but the
    // default table never heard of has no row to be mapped on.
    NSArray *extras = stored[@"observed"];
    NSUInteger observed = 0;
    if ([extras isKindOfClass:NSArray.class]) {
        for (id source in extras) {
            if (![source isKindOfClass:NSString.class] || ![(NSString *)source length]) { rejected++; continue; }
            if (!_observed) _observed = [NSMutableOrderedSet orderedSet];
            [_observed addObject:source];
            observed++;
        }
    }
    if (applied || rejected || observed)
        WKLog("input", @"controller profile %@: %lu mapping(s) read, %lu discovered, %lu rejected",
              _identity, (unsigned long)applied, (unsigned long)observed, (unsigned long)rejected);
}

- (NSString *)targetForSource:(NSString *)source {
    return _map[source] ?: AKControllerTargetNone;
}

- (void)noteObservedSource:(NSString *)source {
    if (!source.length) return;
    if ([AKControllerProfile sourceElements] && [[AKControllerProfile sourceElements] containsObject:source]) return;
    if (!_observed) _observed = [NSMutableOrderedSet orderedSet];
    if ([_observed containsObject:source]) return;
    [_observed addObject:source];
}

- (NSArray<NSString *> *)observedSources {
    return _observed.array ?: @[];
}

- (NSString *)sourceForTarget:(NSString *)target {
    if (!target.length || [target isEqualToString:AKControllerTargetNone]) return nil;
    // AKControllerProfile.sourceElements is in display order, so the answer does not
    // depend on dictionary enumeration order when a stored table happens to collide.
    for (NSString *source in [AKControllerProfile sourceElements])
        if ([_map[source] isEqualToString:target]) return source;
    return nil;
}

- (void)bindSource:(NSString *)source toTarget:(NSString *)target {
    if (!source.length) return;
    // A discovered control is in the table the moment it is seen, so it can be mapped at once.
    if (!_map[source]) _map[source] = AKControllerTargetNone;
    NSString *wanted = target.length ? target : AKControllerTargetNone;
    if (![wanted isEqualToString:AKControllerTargetNone] && ![AKControllerTarget targetWithIdentifier:wanted]) return;
    if ([_map[source] isEqualToString:wanted]) return;
    // One virtual control, one source. Two sources writing the same button would leave
    // whichever moved last holding it, so the table is kept one-to-one instead.
    NSString *previous = [self sourceForTarget:wanted];
    if (previous && ![previous isEqualToString:source]) _map[previous] = AKControllerTargetNone;
    _map[source] = wanted;
    [self save];
    WKLog("input", @"controller profile %@: %@ -> %@", _identity, source, wanted);
}

- (NSString *)unbindSource:(NSString *)source {
    NSString *previous = [self targetForSource:source];
    _map[source] = AKControllerTargetNone;
    [self save];
    return previous;
}

- (void)resetToDefault {
    // The standard layout is the standard layout. What was discovered about the model stays:
    // it is a fact about the pad, not a choice the user made.
    [_map removeAllObjects];
    for (NSArray<NSString *> *pair in AKControllerDefaultPairs()) _map[pair[0]] = pair[1];
    [AKControllerProfile forgetIdentity:_identity defaults:_defaults];
    WKLog("input", @"controller profile %@: reset to the standard layout", _identity);
}

- (BOOL)customised {
    // Discovered controls are part of the stored profile: without this the rows a pad taught us
    // about would be forgotten the next time the page saved nothing.
    if (_observed.count) return YES;
    for (NSArray<NSString *> *pair in AKControllerDefaultPairs())
        if (![_map[pair[0]] isEqualToString:pair[1]]) return YES;
    return NO;
}

- (NSArray<AKControllerBinding *> *)bindingsWithAvailability:(NSDictionary<NSString *, NSNumber *> *)available
                                                   reserved:(NSDictionary<NSString *, NSNumber *> *)reserved {
    NSMutableArray<AKControllerBinding *> *rows = [NSMutableArray array];
    // The standard layout first, in its own order; then every control the attached pad says it
    // has, because iPadOS is the authority on its own hardware and a row is what makes a control
    // mappable; then anything this model produced as an event, which is the only way a control
    // iPadOS never lists can be mapped at all. Reported controls are sorted so the list does not
    // move about between launches.
    NSMutableArray<NSString *> *order = [[AKControllerProfile sourceElements] mutableCopy];
    for (NSString *source in [available.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if (![order containsObject:source]) [order addObject:source];
    for (NSString *source in _observed) if (![order containsObject:source]) [order addObject:source];
    for (NSString *source in order) {
        NSString *target = [self targetForSource:source];
        AKControllerBinding *row = [AKControllerBinding new];
        row.source = source;
        row.target = target;
        row.sourceDisplay = AKInputElementDisplay(source);
        row.targetDisplay = [AKControllerTarget targetWithIdentifier:target].display ?: @"Not assigned";
        row.available = available[source] ? available[source].boolValue : NO;
        row.reserved = reserved[source] ? reserved[source].boolValue : NO;
        // "Found on this controller" rather than "the standard layout": the row exists because
        // the pad has that control, whether iPadOS reported it or it only ever arrived as an
        // event.
        row.discovered = ![[AKControllerProfile sourceElements] containsObject:source];
        [rows addObject:row];
    }
    return rows;
}

- (void)save {
    NSString *key = [AKControllerProfile defaultsKeyForIdentity:_identity];
    if (!self.customised) { [_defaults removeObjectForKey:key]; return; }
    [_defaults setObject:@{@"version": @(AKControllerProfileVersion),
                           @"map": [_map copy],
                           @"observed": _observed.array ?: @[]} forKey:key];
}

+ (void)forgetIdentity:(NSString *)identity defaults:(NSUserDefaults *)defaults {
    [(defaults ?: NSUserDefaults.standardUserDefaults) removeObjectForKey:[self defaultsKeyForIdentity:identity]];
}

@end
