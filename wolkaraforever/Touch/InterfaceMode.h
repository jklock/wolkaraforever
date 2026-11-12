#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The interface the user asked for. One key, read wherever a decision depends on
/// it, so the launcher's selector and the guest's own controls cannot disagree about
/// which one is on.
///
/// Four spellings are understood: "ipados" (Standard), "ios" (an ordinary phone), "iosduo" (the
/// Duo), and "auto" - whatever this device is, from its own hardware class.
///
/// A missing value, "ipados", or a value this build does not recognise means Standard:
/// the interface every installation had, so adding "auto" changes nothing for an
/// existing one.
extern NSString *const AKInterfaceModeDefaultsKey;   // "WolkaraForeverInterfaceModeV1"
extern NSString *const AKInterfaceModeIPadOS;        // "ipados"
extern NSString *const AKInterfaceModeIOS;           // "ios"
extern NSString *const AKInterfaceModeIOSDuo;        // "iosduo"
extern NSString *const AKInterfaceModeAuto;          // "auto"

/// Whether the mobile (iPhone/Duo) interface is on. The hardware is read here and nowhere
/// else in the app.
FOUNDATION_EXPORT BOOL AKInterfaceModeIsMobile(void);

/// Whether the stored choice is "auto", so the launcher can mark it as such.
FOUNDATION_EXPORT BOOL AKInterfaceModeIsAutomatic(void);

/// What "auto" resolves to on this device, whatever is chosen now, so the selector can say
/// "Automatic (iOS on Duo)" on a Duo while iPadOS is what is in force.
FOUNDATION_EXPORT NSString *AKInterfaceModeAutomaticName(void);

/// What the stored choice resolves to: "ipados", "ios" or "iosduo".
FOUNDATION_EXPORT NSString *AKInterfaceModeName(void);

/// The stored choice itself: "auto", "ipados", "ios" or "iosduo", never the resolution.
FOUNDATION_EXPORT NSString *AKInterfaceModeStoredName(void);

NS_ASSUME_NONNULL_END
