// The device-profile table, resolved without UIKit so it can run on this Mac.
//
// What is checked is the part that has a right answer: every shipped model identifier resolves
// to its own record and nothing else, an unlisted device resolves to the conservative fallback
// rather than to nil or to a guessed profile, and a profile that was never measured cannot be
// asked for native-size rendering. The hardware itself is not measured here - that is what
// PERFORMANCE_THERMAL.md records and what the device self-test reports.

#import <Foundation/Foundation.h>
#import "../launcher/WoW/DeviceProfile.h"

static NSUInteger checks;

static void Check(BOOL condition, NSString *what) {
    checks++;
    if (condition) return;
    fprintf(stderr, "FAIL %s\n", what.UTF8String);
    abort();
}

int main(void) {
    @autoreleasepool {
        NSArray<TKDeviceProfile *> *profiles=TKDeviceProfile.profiles;
        Check(profiles.count>0, @"the table has records");

        // --- the table itself is coherent
        NSMutableSet<NSString *> *identifiers=[NSMutableSet new], *models=[NSMutableSet new];
        for (TKDeviceProfile *profile in profiles) {
            Check(profile.identifier.length>0, @"every record has a stable identifier");
            Check([identifiers containsObject:profile.identifier]==NO,
                  [NSString stringWithFormat:@"%@ is not used twice", profile.identifier]);
            [identifiers addObject:profile.identifier];
            Check(profile.displayName.length>0,
                  [NSString stringWithFormat:@"%@ has a name a person can read", profile.identifier]);
            Check(profile.family!=TKDeviceFamilyUnknown,
                  [NSString stringWithFormat:@"%@ is a real family, not the fallback", profile.identifier]);
            Check(profile.modelIdentifiers.count>0,
                  [NSString stringWithFormat:@"%@ names the hardware it is for", profile.identifier]);
            for (NSString *model in profile.modelIdentifiers) {
                Check([models containsObject:model]==NO,
                      [NSString stringWithFormat:@"%@ is claimed by one record only", model]);
                [models addObject:model];
            }
            // Performance and Balanced are the same target on every device; only Quality varies,
            // and only where it was measured.
            Check([profile backingScaleForQuality:TKRenderQualityPerformance]==0.75,
                  [NSString stringWithFormat:@"%@ renders Performance at 0.75", profile.identifier]);
            Check([profile backingScaleForQuality:TKRenderQualityBalanced]==1.0,
                  [NSString stringWithFormat:@"%@ renders Balanced at 1.0", profile.identifier]);
            if (profile.highestQuality<TKRenderQualityQuality)
                Check([profile backingScaleForQuality:TKRenderQualityQuality]==0,
                      [NSString stringWithFormat:@"%@ does not offer Quality (%@)", profile.identifier,
                       profile.notes]);
            else
                Check([profile backingScaleForQuality:TKRenderQualityQuality]>=2.0,
                      [NSString stringWithFormat:@"%@ offers Quality at native size", profile.identifier]);
            Check(profile.recommendedQuality<profile.highestQuality || profile.highestQuality<TKRenderQualityQuality,
              [NSString stringWithFormat:@"%@ never defaults to a quality above what it measured", profile.identifier]);
        Check(profile.recommendedQuality<=profile.highestQuality,
                  [NSString stringWithFormat:@"%@ never recommends past its own ceiling", profile.identifier]);
            Check(profile.notes.length>0,
                  [NSString stringWithFormat:@"%@ says where its numbers came from", profile.identifier]);
        }

        // --- every identifier resolves to its own record, through the same path the app uses
        for (TKDeviceProfile *profile in profiles) {
            for (NSString *model in profile.modelIdentifiers) {
                TKDeviceProfile *resolved=[TKDeviceProfile profileForModelIdentifier:model];
                Check([resolved.identifier isEqual:profile.identifier],
                      [NSString stringWithFormat:@"%@ resolves to %@", model, profile.identifier]);
            }
        }

        // --- an unlisted device is not guessed at
        TKDeviceProfile *unknown=[TKDeviceProfile profileForModelIdentifier:@"iPad99,99"];
        Check([unknown.identifier isEqual:TKDeviceProfile.fallbackProfile.identifier],
              @"an unlisted iPad resolves to the fallback");
        Check(unknown.family==TKDeviceFamilyUnknown, @"and says it is unknown");
        Check(unknown.highestQuality==TKRenderQualityPerformance, @"and never offers more than Performance");
        Check(unknown.recommendedQuality==TKRenderQualityPerformance, @"and recommends Performance");
        Check([unknown backingScaleForQuality:TKRenderQualityQuality]==0, @"and cannot be asked for Quality");
        TKDeviceProfile *nothing=[TKDeviceProfile profileForModelIdentifier:nil];
        Check([nothing.identifier isEqual:TKDeviceProfile.fallbackProfile.identifier],
              @"no identifier at all resolves to the fallback");

        // --- the measured device, which is the one this project has numbers for
        TKDeviceProfile *dadpad=[TKDeviceProfile profileForModelIdentifier:@"iPad13,8"];
        Check([dadpad.identifier isEqual:@"ipad-pro-12.9-m1"], @"Dadpad is the measured 12.9-inch M1");
        Check(dadpad.measured, @"and is marked measured");
        Check(dadpad.recommendedQuality==TKRenderQualityBalanced,
              @"and its default is Balanced, not the thing that was measured to miss the budget");
        Check(dadpad.highestQuality==TKRenderQualityQuality, @"with Quality still offered as a choice");
        Check([dadpad backingScaleForQuality:TKRenderQualityQuality]==2.0, @"at native 2.0");
        Check([TKDeviceProfileSizeDescription(dadpad) isEqual:@"1366 × 1024"], @"and it renders at 1366 × 1024");
        Check([TKDeviceProfileSizeDescription(unknown) isEqual:@""], @"an unknown device states no size");

        // --- known but unmeasured hardware stops at Balanced
        TKDeviceProfile *unmeasured=[TKDeviceProfile profileForModelIdentifier:@"iPad16,5"];
        Check([unmeasured.identifier isEqual:@"ipad-pro-13-m4"], @"a 13-inch M4 is known");
        Check(unmeasured.measured==NO, @"but is not measured");
        Check(unmeasured.recommendedQuality==TKRenderQualityBalanced, @"so it recommends Balanced");
        Check(unmeasured.highestQuality==TKRenderQualityBalanced, @"and Quality is not offered at all");

        // --- an override is honoured, and a stale one falls back to this device
        TKDeviceProfile *override=[TKDeviceProfile resolvedProfileWithOverride:@"ipad-pro-11-m1"];
        Check([override.identifier isEqual:@"ipad-pro-11-m1"], @"a stored override wins");
        TKDeviceProfile *stale=[TKDeviceProfile resolvedProfileWithOverride:@"ipad-that-was-removed"];
        Check([[TKDeviceProfile profileForModelIdentifier:TKDeviceProfile.currentModelIdentifier].identifier
                isEqual:stale.identifier], @"a stale override falls back to the running device");
        TKDeviceProfile *automatic=[TKDeviceProfile resolvedProfileWithOverride:nil];
        Check([automatic.identifier isEqual:stale.identifier], @"and no override means the running device");

        // --- the stored names round-trip, and an unknown one is not silently taken as real
        for (NSNumber *quality in @[@(TKRenderQualityPerformance),@(TKRenderQualityBalanced),@(TKRenderQualityQuality)]) {
            NSString *name=[TKDeviceProfile nameForQuality:quality.integerValue];
            Check([TKDeviceProfile qualityForName:name].integerValue==quality.integerValue,
                  [NSString stringWithFormat:@"%@ round-trips", name]);
        }
        Check([TKDeviceProfile qualityForName:@"ultra"]==nil, @"an invented quality name reads as nothing");
        Check([TKDeviceProfile qualityForName:nil]==nil, @"and so does a missing one");

        // --- the migration boundary: what the settings written before this table mean
        Check([TKDeviceProfile qualityForBackingScale:0.75]==TKRenderQualityPerformance, @"0.75 was Performance");
        Check([TKDeviceProfile qualityForBackingScale:1.0]==TKRenderQualityBalanced, @"1.0 was Balanced");
        Check([TKDeviceProfile qualityForBackingScale:2.0]==TKRenderQualityQuality, @"2.0 was Quality");
        Check([TKDeviceProfile qualityForBackingScale:0.9]==TKRenderQualityBalanced, @"anything else is Balanced");

        // --- no iPhone record is claimed yet. The plan asks for the 17 and 18 families; nobody
        // has confirmed a model identifier for them here, so the table must not carry a guess.
        // This is the check that fails when one is added by hand without the hardware.
        NSUInteger phones=0;
        for (TKDeviceProfile *profile in profiles) if (profile.family==TKDeviceFamilyPhone) phones++;
        Check(phones==0, @"no iPhone record exists until one is confirmed");

        printf("DEVICE_PROFILE_PASS: %lu checks: every model resolves to its own record, an unknown device "
               "falls back to Performance, Quality is only offered where it was measured, an override is "
               "honoured and a stale one falls back to the running device, the stored names round-trip, and "
               "the settings written before this table still mean what they meant.\n",
               (unsigned long)checks);
    }
    return 0;
}
