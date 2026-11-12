#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The on-screen controls' arrangement as plain data, reachable without a class.
//
// It is here, as C functions, because two different binaries need it and must agree: the
// adapter that runs the controls, and the launcher that lets a person choose an arrangement
// before any guest exists. A class cannot be shared between them - the adapter is a dylib
// loaded into the same process - so the shared thing is a set of functions over the same
// stored dictionary. Nothing here draws anything, and nothing here touches the game.

/// The dictionary the controls read on their next use.
FOUNDATION_EXPORT NSString *const AKLayoutStoredKey;     // "WolkaraForeverTouchLayoutV1"
/// The named arrangements the user saved, kept apart from the live one.
FOUNDATION_EXPORT NSString *const AKLayoutProfilesKey;   // "WolkaraForeverProfilesV1"

/// The built-in starting points, by their stable names.
FOUNDATION_EXPORT NSArray<NSString *> *AKLayoutTemplateNames(void);
/// What a template writes, or nil when the name is not one we ship.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable AKLayoutTemplatePayload(NSString *name);

/// The names the user saved, sorted.
FOUNDATION_EXPORT NSArray<NSString *> *AKLayoutSavedNames(NSUserDefaults *defaults);
/// Keep the arrangement in force under `name`. The arrangement itself is not changed.
FOUNDATION_EXPORT BOOL AKLayoutSaveProfile(NSUserDefaults *defaults, NSString *name);
/// Put a saved arrangement in force. NO when there is no such name.
FOUNDATION_EXPORT BOOL AKLayoutApplyProfile(NSUserDefaults *defaults, NSString *name);
FOUNDATION_EXPORT BOOL AKLayoutDeleteProfile(NSUserDefaults *defaults, NSString *name);

/// Merge an arrangement into the one in force, keeping the stored dictionary's other keys - a
/// later version's additions, and anything this build does not know, survive a change here.
FOUNDATION_EXPORT void AKLayoutApplyPayload(NSUserDefaults *defaults, NSDictionary<NSString *, id> *payload);
/// Put a built-in starting point in force. NO when the name is not one we ship.
FOUNDATION_EXPORT BOOL AKLayoutApplyTemplate(NSUserDefaults *defaults, NSString *name);

NS_ASSUME_NONNULL_END
