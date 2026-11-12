#import "InterfaceMode.h"

NSString *const AKInterfaceModeDefaultsKey = @"WolkaraForeverInterfaceModeV1";
NSString *const AKInterfaceModeIPadOS = @"ipados";
NSString *const AKInterfaceModeIOS = @"ios";

/// Read on every call rather than cached: the launcher writes the key before a
/// guest starts, and a fixture writes it between two guests in one process, so a
/// cached copy would make the second read answer for the first.
static NSString *AKInterfaceModeStored(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:AKInterfaceModeDefaultsKey];
    return [value isKindOfClass:NSString.class] ? [(NSString *)value lowercaseString] : nil;
}

BOOL AKInterfaceModeIsMobile(void) {
    return [AKInterfaceModeStored() isEqual:AKInterfaceModeIOS];
}

NSString *AKInterfaceModeName(void) {
    return AKInterfaceModeIsMobile() ? AKInterfaceModeIOS : AKInterfaceModeIPadOS;
}
