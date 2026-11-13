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

/// The shape of the stored dictionary this build writes.
///
/// 1 is what every release through v1.0.10 read: one arrangement, no mode. 2 adds the mode
/// (`AKLayoutMode`), the optional stick buttons, the ability zones and Simple's own control
/// positions. A dictionary with no `version` is a 1, and it is migrated to 2 - as Full, which
/// is what it was - the first time either binary looks at it. A dictionary with a *higher*
/// version is a later build's and is never rewritten by this one.
FOUNDATION_EXPORT NSInteger const AKLayoutSchemaVersion;  // 2

/// The two arrangements. Full is every control the app has ever drawn and the layout every
/// existing installation is migrated to; Simple is opt-in and drops the triggers and the
/// D-pad. The spelling is what the stored dictionary carries, so both binaries agree on it.
FOUNDATION_EXPORT NSString *const AKLayoutModeFull;      // "full"
FOUNDATION_EXPORT NSString *const AKLayoutModeSimple;    // "simple"

/// The stored arrangement. "full" when there is none, when it is not one we ship, or when the
/// stored dictionary belongs to a later build: an unknown mode never becomes an experiment.
FOUNDATION_EXPORT NSString *AKLayoutMode(NSUserDefaults *defaults);
/// Store an arrangement. NO for a name this build does not ship, which leaves the layout as it
/// was; nothing a hand-edited file says can turn Simple on.
FOUNDATION_EXPORT BOOL AKLayoutSetMode(NSUserDefaults *defaults, NSString *mode);

/// Whether a double tap on a stick presses that stick's own button. Off unless the user says
/// otherwise, which is what every release through v1.0.10 was.
FOUNDATION_EXPORT BOOL AKLayoutStickButtons(NSUserDefaults *defaults);
FOUNDATION_EXPORT void AKLayoutSetStickButtons(NSUserDefaults *defaults, BOOL enabled);

/// The elements an ability zone may send: the buttons, never a stick and never a D-pad
/// direction, because a zone sends one button value and nothing else.
FOUNDATION_EXPORT NSArray<NSString *> *AKLayoutZoneElements(void);
/// The zones, each `@{@"element", @"x", @"y"}` with the centre as fractions of the screen.
/// Empty - nothing reserved, nothing drawn - unless the user added one.
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, id> *> *AKLayoutAbilityZones(NSUserDefaults *defaults);
/// Add one. NO when the element is not one a zone may send, when the list is full, or when the
/// fractions are not finite; a refused zone changes nothing.
FOUNDATION_EXPORT BOOL AKLayoutAddAbilityZone(NSUserDefaults *defaults, NSString *element, CGFloat x, CGFloat y);
FOUNDATION_EXPORT BOOL AKLayoutSetAbilityZoneElement(NSUserDefaults *defaults, NSString *element, NSUInteger index);
FOUNDATION_EXPORT void AKLayoutClearAbilityZones(NSUserDefaults *defaults);

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
/// The controls this build places, and the elements any of them may send.
FOUNDATION_EXPORT NSArray<NSString *> *AKLayoutSlots(void);
FOUNDATION_EXPORT NSArray<NSString *> *AKLayoutElements(void);
/// Which element a control currently sends (its own name when unmapped).
FOUNDATION_EXPORT NSString *AKLayoutElementForSlot(NSUserDefaults *defaults, NSString *slot);
/// Point a control at another element. NO when either name is unknown, or another control
/// already sends that element - one button cannot be two controls.
FOUNDATION_EXPORT BOOL AKLayoutSetElement(NSUserDefaults *defaults, NSString *element, NSString *slot);

/// Reserve an area the controls must leave alone. Fractions of the screen, clamped into it,
/// refused when degenerate, and capped so a layout cannot grow without bound.
FOUNDATION_EXPORT BOOL AKLayoutAddKeepFreeArea(NSUserDefaults *defaults, CGFloat x, CGFloat y,
                                               CGFloat width, CGFloat height);
NS_ASSUME_NONNULL_END
