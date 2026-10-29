#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A device the launcher knows how to render on, and what it may safely ask of it.
//
// The records are data, in one table in DeviceProfile.m, because the alternative - a chain of
// `if` statements in the page - is how a render target ends up claiming hardware the running
// device does not have. Nothing here measures anything: a record says what has been *tested*,
// and `measured` is the field that decides whether the highest quality may be offered at all.
//
// What this deliberately cannot do is predict frame rate. Thermal state, Low Power Mode, memory
// pressure, the game build and what is on screen are runtime variables, so a record is a safe
// target and never a promise.
typedef NS_ENUM(NSInteger, TKDeviceFamily) {
    TKDeviceFamilyPad,
    TKDeviceFamilyPhone,
    TKDeviceFamilyUnknown,
};

// The render qualities, in ascending order of load. The launcher's own backing scale is derived
// from the chosen quality and the device, which is why a quality and a scale are not two
// independent settings.
typedef NS_ENUM(NSInteger, TKRenderQuality) {
    TKRenderQualityPerformance,
    TKRenderQualityBalanced,
    TKRenderQualityQuality,
};

@interface TKDeviceProfile : NSObject

// Stable identifier, stored in defaults when a profile is chosen by hand. Never shown.
@property (nonatomic, readonly, copy) NSString *identifier;
// Apple's own model name, e.g. "iPad Pro 12.9-inch (M1)". A product name, not a sentence, so
// it is the same in every language.
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly) TKDeviceFamily family;
@property (nonatomic, readonly, copy) NSString *chip;
// The panel in points, for the row that says what a profile renders at.
@property (nonatomic, readonly) CGFloat nativeWidth;
@property (nonatomic, readonly) CGFloat nativeHeight;
// The highest quality this device may be offered. Quality is only here when someone measured
// it; a device that has not been measured is offered Balanced and no further.
@property (nonatomic, readonly) TKRenderQuality highestQuality;
// The backing scale for a quality, or 0 when this device may not be asked for it.
@property (nonatomic, readonly) CGFloat qualityBackingScale;
// Where the numbers come from, in a sentence a person could check.
@property (nonatomic, readonly, copy) NSString *notes;
// YES when this exact hardware was measured on this project rather than assumed.
@property (nonatomic, readonly) BOOL measured;
// `hw.machine` values that resolve to this record. Empty for the fallback.
@property (nonatomic, readonly, copy) NSArray<NSString *> *modelIdentifiers;

// Every measured or assumed record, in a stable order, excluding the fallback.
+ (NSArray<TKDeviceProfile *> *)profiles;

// The record for a `hw.machine` value, or the fallback when nothing matches. Never nil: an
// unknown device gets a conservative answer rather than no answer.
+ (TKDeviceProfile *)profileForModelIdentifier:(nullable NSString *)identifier;

// The conservative record used when the running device is not in the table: Performance scale,
// no Quality offered, and it says so.
+ (TKDeviceProfile *)fallbackProfile;

// This device's `hw.machine` value, or nil when it cannot be read.
+ (nullable NSString *)currentModelIdentifier;

// The record the launcher is actually rendering with: the stored override when there is one,
// else this device. An override is meant for comparison and for testing a profile on other
// hardware, so the caller is expected to say so on screen.
+ (TKDeviceProfile *)resolvedProfileWithOverride:(nullable NSString *)overrideIdentifier;

// The backing scale for a quality on this profile: the value the runtime is given.
- (CGFloat)backingScaleForQuality:(TKRenderQuality)quality;
// The quality this profile renders at when nothing else is chosen. This is deliberately not
// `highestQuality`: Quality is a choice a person makes, with a confirmation, and never the
// default - on the one device measured here, native rendering is what missed the frame budget.
- (TKRenderQuality)recommendedQuality;
// The quality nearest to `scale`, for the settings written before this table existed.
+ (TKRenderQuality)qualityForBackingScale:(CGFloat)scale;

// Stored values. `TKRenderQualityName` is what goes in defaults; an unknown name reads as nil.
+ (NSString *)nameForQuality:(TKRenderQuality)quality;
+ (nullable NSNumber *)qualityForName:(nullable NSString *)name;

@end

// "1366 × 1024" for the row that says what a profile renders at.
FOUNDATION_EXPORT NSString *TKDeviceProfileSizeDescription(TKDeviceProfile *profile);

NS_ASSUME_NONNULL_END
