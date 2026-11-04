// WolkaraForever layer: one controller model's remap profile.
//
// A profile answers exactly one question - "when this physical control moves, which
// control of the virtual pad does it drive?" - and it answers it per *model*, because
// GameController cannot tell two identical pads apart. Everything else about routing
// (discovery, lifecycle, injection, release) belongs to AKControllerManager; this file
// is only the table and its storage, so it can be exercised without any hardware.
//
// Element vocabulary: sources are the canonical physical ids from InputElement.h
// ("controller.button.a", "controller.axis.left.thumbstick", "dpad.dpad"). Targets are
// WolkaraForever's own ids ("virtual.button.a", "virtual.stick.left", "virtual.dpad")
// rather than GameController's GCInput* constants, so a profile written today does not
// depend on the framework's spelling and can be read on a screen without GameController.
// The adapter that talks to GCVirtualController owns the translation between the two.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The target that means "this source drives nothing". Stored rather than removing the
/// key, so "the user chose nothing here" and "the user never touched this" stay distinct.
FOUNDATION_EXPORT NSString *const AKControllerTargetNone;

typedef NS_ENUM(NSInteger, AKControllerTargetKind) {
    /// Driven with a value (0…1), like a button or a trigger.
    AKControllerTargetKindButton = 0,
    /// Driven with a position, like a thumbstick or the D-pad.
    AKControllerTargetKindAxis,
};

/// One control of the virtual pad.
@interface AKControllerTarget : NSObject
/// Every target the virtual pad actually has, in the order the page lists them.
@property (class, nonatomic, readonly) NSArray<AKControllerTarget *> *targets;
+ (nullable instancetype)targetWithIdentifier:(nullable NSString *)identifier;
@property (nonatomic, copy, readonly) NSString *identifier;   // "virtual.button.a"
@property (nonatomic, copy, readonly) NSString *display;      // "A"
@property (nonatomic, readonly) AKControllerTargetKind kind;
@end

/// One row of the mapping list: what the pad has, and what it drives.
@interface AKControllerBinding : NSObject
@property (nonatomic, copy, readonly) NSString *source;         // "controller.button.a"
@property (nonatomic, copy, readonly) NSString *target;         // "virtual.button.b", or none
@property (nonatomic, copy, readonly) NSString *sourceDisplay;  // "A"
@property (nonatomic, copy, readonly) NSString *targetDisplay;  // "B"
/// YES when the connected pad actually has this source. A stored profile outlives the
/// pad it was made on, so a row the pad cannot produce is shown as unavailable rather
/// than silently dropped - dropping it would lose the user's choice when they next use
/// that model.
@property (nonatomic, readonly) BOOL available;
/// YES when iPadOS keeps the press unless we ask for it, which the manager does only for
/// a source this profile actually routes.
@property (nonatomic, readonly) BOOL reserved;
/// YES for a control this model turned out to have beyond the standard layout - a button iOS
/// reports that the default table never heard of, or one that only ever arrived as an event. It
/// is a fact about the pad, remembered so the row survives a restart.
@property (nonatomic, readonly) BOOL discovered;
@end

@interface AKControllerProfile : NSObject

- (instancetype)initWithIdentity:(NSString *)identity
                      vendorName:(nullable NSString *)vendorName
                 productCategory:(nullable NSString *)productCategory
                        defaults:(NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, copy, readonly) NSString *identity;     // "xbox.bluetooth.gamepad.xbox.one"
@property (nonatomic, copy, readonly) NSString *displayName;  // "Xbox Bluetooth Gamepad — Xbox One"

/// The target a source drives, or AKControllerTargetNone. Never nil: a source the user
/// never touched answers with its one-to-one default.
- (NSString *)targetForSource:(NSString *)source;
/// Controls this model has beyond the standard layout, in the order they were seen. This is what
/// makes a pad's extra buttons exist as rows at all: the default layout cannot know them.
- (NSArray<NSString *> *)observedSources;
/// Remember a control this model produced. Called with any source that arrives in an event, so a
/// button iOS never lists still becomes mappable once it has been pressed.
- (void)noteObservedSource:(NSString *)source;

/// The source that drives a target, or nil. One target has at most one source, which is
/// what makes routing deterministic: two controls can never fight over the same virtual
/// button.
- (nullable NSString *)sourceForTarget:(NSString *)target;

/// Bind `source` to `target`. Any other source that used to drive `target` is unmapped,
/// so the table stays one-to-one. Passing AKControllerTargetNone unmaps.
- (void)bindSource:(NSString *)source toTarget:(NSString *)target;

/// The row the learn flow replaced, so cancelling can put it back. Returns the previous
/// target of `source`, which the caller may restore with -bindSource:toTarget:.
- (NSString *)unbindSource:(NSString *)source;

- (void)resetToDefault;
/// YES when anything differs from the one-to-one default.
@property (nonatomic, readonly) BOOL customised;

/// The complete list, sources in a stable display order.
- (NSArray<AKControllerBinding *> *)bindingsWithAvailability:(NSDictionary<NSString *, NSNumber *> *)available
                                                   reserved:(NSDictionary<NSString *, NSNumber *> *)reserved;

/// Write the table. Profile storage is WolkaraForever's own: nothing here reads or writes
/// WoW bindings, GamePadConfig_*.json or Config.wtf.
- (void)save;
+ (void)forgetIdentity:(NSString *)identity defaults:(NSUserDefaults *)defaults;

/// Every source the manager is able to route, in display order. Exposed so the manager
/// and the page agree about the list instead of each deriving it.
+ (NSArray<NSString *> *)sourceElements;

@end

NS_ASSUME_NONNULL_END
