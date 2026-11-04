#import "DeviceProfile.h"

#import <sys/sysctl.h>

// The table. One place, plain data, and no device is in it because it ought to exist: a record
// carries the `hw.machine` values Apple actually ships, and anything not in here resolves to
// the fallback instead of being guessed at. See the plan in
// development/uichanges/LAUNCHER_REORGANIZATION_PLAN.md for the coverage the matrix is meant to
// reach; the rows for hardware nobody has confirmed are deliberately absent rather than
// invented, and the fallback is what an unconfirmed device gets.

@interface TKDeviceProfile ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic) TKDeviceFamily family;
@property (nonatomic, copy, readwrite) NSString *chip;
@property (nonatomic) CGFloat nativeWidth;
@property (nonatomic) CGFloat nativeHeight;
@property (nonatomic) TKRenderQuality highestQuality;
@property (nonatomic) CGFloat qualityBackingScale;
@property (nonatomic, copy, readwrite) NSString *notes;
@property (nonatomic) BOOL measured;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *modelIdentifiers;
@end

@implementation TKDeviceProfile

+ (instancetype)record:(NSString *)identifier name:(NSString *)name family:(TKDeviceFamily)family
                  chip:(NSString *)chip width:(CGFloat)width height:(CGFloat)height
               highest:(TKRenderQuality)highest qualityScale:(CGFloat)qualityScale
              measured:(BOOL)measured notes:(NSString *)notes models:(NSArray<NSString *> *)models {
    TKDeviceProfile *profile=[TKDeviceProfile new];
    profile.identifier=identifier;
    profile.displayName=name;
    profile.family=family;
    profile.chip=chip;
    profile.nativeWidth=width;
    profile.nativeHeight=height;
    profile.highestQuality=highest;
    profile.qualityBackingScale=qualityScale;
    profile.measured=measured;
    profile.notes=notes;
    profile.modelIdentifiers=models;
    return profile;
}

+ (NSArray<TKDeviceProfile *> *)profiles {
    static NSArray<TKDeviceProfile *> *records;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        records=@[
            // Phone geometry is supplied by UIKit, never fixed to a model's panel.
            [self record:@"iphone-16-pro" name:@"iPhone 16 Pro" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model from Xcode's device catalogue. Uses the current window size; 2x is a readability default, not a measured frame-rate claim."
                  models:@[@"iPhone17,1"]],
            [self record:@"iphone-16-pro-max" name:@"iPhone 16 Pro Max" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model from Xcode's device catalogue. Uses the current window size; 2x is a readability default, not a measured frame-rate claim."
                  models:@[@"iPhone17,2"]],
            [self record:@"iphone-17-pro" name:@"iPhone 17 Pro" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model from Xcode's device catalogue. Uses the current window size; 2x is a readability default, not a measured frame-rate claim."
                  models:@[@"iPhone18,1"]],
            [self record:@"iphone-17-pro-max" name:@"iPhone 17 Pro Max" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model from Xcode's device catalogue. Uses the current window size; 2x is a readability default, not a measured frame-rate claim."
                  models:@[@"iPhone18,2"]],
            [self record:@"iphone-18-pro" name:@"iPhone 18 Pro" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model from Xcode's device catalogue. Uses the current window size; 2x is a readability default, not a measured frame-rate claim."
                  models:@[@"iPhone19,2"]],
            [self record:@"iphone-18-pro-max" name:@"iPhone 18 Pro Max" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model from Xcode's device catalogue. Uses the current window size; 2x is a readability default, not a measured frame-rate claim."
                  models:@[@"iPhone19,3"]],
            [self record:@"iphone-duo" name:@"iPhone Duo" family:TKDeviceFamilyPhone
                    chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Model confirmed on device and in Xcode. Uses the current window, including fold and orientation changes. Performance is not benchmarked."
                  models:@[@"iPhone19,4"]],
            // Measured on this project: the 12.9-inch M1 is "Dadpad", the device every
            // performance figure in development/technical/PERFORMANCE_THERMAL.md was taken on.
            // Native-size rendering is what those sessions measured missing the frame budget,
            // so Quality is offered here - a person may prefer it - and is not the default.
            //
            // The same sessions found the other half of it and this record has to carry that
            // too: dropping the backing scale to 0.75 made the drawable smaller and did not
            // reduce measured GPU time (9.9 ms against 9.0 ms). So Performance here means a
            // smaller drawable on this device, not a faster one, and nothing on the page may
            // promise a frame rate from it.
            [self record:@"ipad-pro-12.9-m1" name:@"iPad Pro 12.9-inch (M1)" family:TKDeviceFamilyPad
                    chip:@"M1" width:1366 height:1024
                 highest:TKRenderQualityQuality qualityScale:2.0 measured:YES
                   notes:@"Measured on Dadpad (iPadOS 27, 2026-10-22/23). Native 2732x2048 missed the 16.7 ms budget and then throttled, per PERFORMANCE_THERMAL.md. Its 0.75 backing scale measured no GPU saving there (9.9 ms against 9.0 ms), so Performance is a smaller drawable, not a faster frame."
                  models:@[@"iPad13,8",@"iPad13,9",@"iPad13,10",@"iPad13,11"]],
            // Everything below is the same conservative policy: native-size rendering is not
            // offered until someone measures it on that hardware, so Balanced is the ceiling.
            [self record:@"ipad-pro-11-m1" name:@"iPad Pro 11-inch (M1)" family:TKDeviceFamilyPad
                    chip:@"M1" width:1194 height:834
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad13,4",@"iPad13,5",@"iPad13,6",@"iPad13,7"]],
            [self record:@"ipad-air-11-m1" name:@"iPad Air 11-inch (M1)" family:TKDeviceFamilyPad
                    chip:@"M1" width:1180 height:820
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad13,16",@"iPad13,17"]],
            [self record:@"ipad-pro-11-m2" name:@"iPad Pro 11-inch (M2)" family:TKDeviceFamilyPad
                    chip:@"M2" width:1210 height:834
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad14,3",@"iPad14,4"]],
            [self record:@"ipad-pro-12.9-m2" name:@"iPad Pro 12.9-inch (M2)" family:TKDeviceFamilyPad
                    chip:@"M2" width:1366 height:1024
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad14,5",@"iPad14,6"]],
            [self record:@"ipad-air-11-m2" name:@"iPad Air 11-inch (M2)" family:TKDeviceFamilyPad
                    chip:@"M2" width:1180 height:820
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad14,8",@"iPad14,9"]],
            [self record:@"ipad-air-13-m2" name:@"iPad Air 13-inch (M2)" family:TKDeviceFamilyPad
                    chip:@"M2" width:1366 height:1024
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad14,10",@"iPad14,11"]],
            [self record:@"ipad-pro-11-m4" name:@"iPad Pro 11-inch (M4)" family:TKDeviceFamilyPad
                    chip:@"M4" width:1210 height:834
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad16,3",@"iPad16,4"]],
            [self record:@"ipad-pro-13-m4" name:@"iPad Pro 13-inch (M4)" family:TKDeviceFamilyPad
                    chip:@"M4" width:1376 height:1032
                 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
                   notes:@"Not measured here; Balanced is the ceiling until it is."
                  models:@[@"iPad16,5",@"iPad16,6"]],
        ];
    });
    return records;
}

+ (TKDeviceProfile *)fallbackProfile {
    static TKDeviceProfile *fallback;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The lowest setting that is safe to assume: smaller than native on anything, and no
        // Quality, because nothing about this device has been measured.
        fallback=[self record:@"unknown" name:@"" family:TKDeviceFamilyUnknown
                         chip:@"" width:0 height:0
                      highest:TKRenderQualityPerformance qualityScale:0 measured:NO
                        notes:@"Not a device this build has tested. Performance is the safe profile until it is."
                       models:@[]];
    });
    return fallback;
}

+ (TKDeviceProfile *)profileForModelIdentifier:(NSString *)identifier {
    if (identifier.length) {
        for (TKDeviceProfile *profile in self.profiles) {
            if ([profile.modelIdentifiers containsObject:identifier]) return profile;
        }
    }
    if ([identifier hasPrefix:@"iPhone"]) {
        return [self record:@"iphone" name:@"iPhone" family:TKDeviceFamilyPhone
            chip:@"" width:0 height:0 highest:TKRenderQualityBalanced qualityScale:0 measured:NO
            notes:@"Uses the current iPhone window. No model-specific performance measurement."
            models:@[identifier]];
    }
    return self.fallbackProfile;
}

+ (NSString *)currentModelIdentifier {
    // hw.machine on both platforms: the simulator reports the Mac's own value, which is exactly
    // why an unknown identifier has to resolve to something safe rather than to nil.
    size_t size=0;
    if (sysctlbyname("hw.machine",NULL,&size,NULL,0)!=0 || size==0) return nil;
    char *value=malloc(size);
    if (!value) return nil;
    NSString *identifier=nil;
    if (sysctlbyname("hw.machine",value,&size,NULL,0)==0) identifier=[NSString stringWithUTF8String:value];
    free(value);
    return identifier.length?identifier:nil;
}

+ (TKDeviceProfile *)resolvedProfileWithOverride:(NSString *)overrideIdentifier {
    if (overrideIdentifier.length) {
        for (TKDeviceProfile *profile in self.profiles) {
            if ([profile.identifier isEqual:overrideIdentifier]) return profile;
        }
        // A stored override that this build no longer has - an uninstalled record, or one
        // renamed - falls back to the device rather than to a stale scale.
    }
    return [self profileForModelIdentifier:self.currentModelIdentifier];
}

- (TKDeviceProfile *)profileWithWidth:(CGFloat)width height:(CGFloat)height {
    if (self.family!=TKDeviceFamilyPhone || !isfinite(width) || !isfinite(height) || width<=0 || height<=0) return self;
    return [TKDeviceProfile record:self.identifier name:self.displayName family:self.family chip:self.chip
        width:width height:height highest:self.highestQuality qualityScale:self.qualityBackingScale
        measured:self.measured notes:self.notes models:self.modelIdentifiers];
}

- (CGFloat)backingScaleForQuality:(TKRenderQuality)quality {
    if (self.family==TKDeviceFamilyPhone)
        return quality==TKRenderQualityPerformance ? 1.0 : quality==TKRenderQualityBalanced ? 2.0 : 0;

    if (quality>TKRenderQualityBalanced && self.qualityBackingScale<=0) return 0;
    switch (quality) {
        case TKRenderQualityPerformance: return 0.75;
        case TKRenderQualityBalanced: return 1.0;
        case TKRenderQualityQuality: return self.qualityBackingScale;
    }
    return 1.0;
}

- (TKRenderQuality)recommendedQuality {
    // The default is never the ceiling. Quality is only offered where the hardware was measured,
    // and on this project the thing that measurement found was native rendering missing the
    // frame budget - so Quality stays a choice that asks first, and Balanced is what a device
    // gets until its owner says otherwise. Unmeasured hardware has no Quality to offer at all.
    return self.highestQuality==TKRenderQualityQuality ? TKRenderQualityBalanced : self.highestQuality;
}

+ (TKRenderQuality)qualityForBackingScale:(CGFloat)scale {
    if (scale<=0.75) return TKRenderQualityPerformance;
    if (scale>=2.0) return TKRenderQualityQuality;
    return TKRenderQualityBalanced;
}

+ (NSString *)nameForQuality:(TKRenderQuality)quality {
    switch (quality) {
        case TKRenderQualityPerformance: return @"performance";
        case TKRenderQualityBalanced: return @"balanced";
        case TKRenderQualityQuality: return @"quality";
    }
    return @"balanced";
}

+ (NSNumber *)qualityForName:(NSString *)name {
    for (NSNumber *each in @[@(TKRenderQualityPerformance),@(TKRenderQualityBalanced),@(TKRenderQualityQuality)])
        if ([[self nameForQuality:each.integerValue] isEqual:name]) return each;
    return nil;
}

@end

NSString *TKDeviceProfileSizeDescription(TKDeviceProfile *profile) {
    if (profile.nativeWidth<=0 || profile.nativeHeight<=0) return @"";
    return [NSString stringWithFormat:@"%.0f × %.0f", profile.nativeWidth, profile.nativeHeight];
}
