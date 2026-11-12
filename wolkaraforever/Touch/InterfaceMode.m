#import "InterfaceMode.h"
#import <UIKit/UIKit.h>

NSString *const AKInterfaceModeDefaultsKey = @"WolkaraForeverInterfaceModeV1";
NSString *const AKInterfaceModeIPadOS = @"ipados";
NSString *const AKInterfaceModeIOS = @"ios";
NSString *const AKInterfaceModeAuto = @"auto";

/// Read on every call rather than cached: the launcher writes the key before a
/// guest starts, and a fixture writes it between two guests in one process, so a
/// cached copy would make the second read answer for the first.
static NSString *AKInterfaceModeStored(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:AKInterfaceModeDefaultsKey];
    return [value isKindOfClass:NSString.class] ? [(NSString *)value lowercaseString] : nil;
}

/// The device's own class, and the only thing "auto" reads: a phone gets the mobile
/// interface, a tablet - and anything else - the iPadOS one. Not a model number, not a
/// screen size, not a gamepad preference, and not an add-on: the hardware, exactly.
static BOOL AKInterfaceModeHardwareIsPhone(void) {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
}

BOOL AKInterfaceModeIsMobile(void) {
    NSString *stored = AKInterfaceModeStored();
    if ([stored isEqual:AKInterfaceModeIOS]) return YES;
    if ([stored isEqual:AKInterfaceModeAuto]) return AKInterfaceModeHardwareIsPhone();
    // "ipados", nothing at all, or something a hand edit invented: the interface every
    // installation had. Adding "auto" therefore changes no existing installation.
    return NO;
}

BOOL AKInterfaceModeIsAutomatic(void) {
    return [AKInterfaceModeStored() isEqual:AKInterfaceModeAuto];
}

NSString *AKInterfaceModeAutomaticName(void) {
    return AKInterfaceModeHardwareIsPhone() ? AKInterfaceModeIOS : AKInterfaceModeIPadOS;
}

NSString *AKInterfaceModeName(void) {
    return AKInterfaceModeIsMobile() ? AKInterfaceModeIOS : AKInterfaceModeIPadOS;
}

NSString *AKInterfaceModeStoredName(void) {
    NSString *stored = AKInterfaceModeStored();
    if ([stored isEqual:AKInterfaceModeIOS] || [stored isEqual:AKInterfaceModeAuto]) return stored;
    return AKInterfaceModeIPadOS;
}
