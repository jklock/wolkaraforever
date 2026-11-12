#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The interface the user asked for. One key, read wherever a decision depends on
/// it, so the launcher's selector (a later release) and the guest's own controls
/// cannot disagree about which one is on.
///
/// The default is iPadOS: a value that is missing, unrecognised, or hand-edited
/// to something else means the Standard interface, because that is the one every
/// installation had before this key existed.
extern NSString *const AKInterfaceModeDefaultsKey;   // "WolkaraForeverInterfaceModeV1"
extern NSString *const AKInterfaceModeIPadOS;        // "ipados"
extern NSString *const AKInterfaceModeIOS;           // "ios"

/// Whether the mobile (iPhone/Duo) interface is on. NO for iPadOS and for every
/// value this build does not recognise.
FOUNDATION_EXPORT BOOL AKInterfaceModeIsMobile(void);

/// The stored spelling of the mode, after the same resolution
/// AKInterfaceModeIsMobile applies: "ipados" or "ios".
FOUNDATION_EXPORT NSString *AKInterfaceModeName(void);

NS_ASSUME_NONNULL_END
