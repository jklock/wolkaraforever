#import "AuthorizationBlockedState.h"

NSString *const WKAuthorizationBlockedNotEnrolled = @"notEnrolled";
NSString *const WKAuthorizationBlockedUntrustedPeer = @"untrustedPeer";
NSString *const WKAuthorizationBlockedDeveloperImage = @"developerImageUnavailable";
NSString *const WKAuthorizationBlockedServiceUnavailable = @"serviceUnavailable";
NSString *const WKAuthorizationBlockedPreparationIncomplete = @"preparationIncomplete";

// A device identifier is a short opaque string from enrolment. The bound is the
// helper's own (1024 bytes); anything longer is not one of ours.
static const NSUInteger WKAuthorizationMaximumIdentifier = 1024;

NSString *WKAuthorizationBlockedState(id replyValue) {
    if(![replyValue isKindOfClass:NSString.class]) return nil;
    NSString *value=(NSString *)replyValue;
    for(NSString *known in @[WKAuthorizationBlockedNotEnrolled,WKAuthorizationBlockedUntrustedPeer,
                             WKAuthorizationBlockedDeveloperImage,
                             WKAuthorizationBlockedServiceUnavailable,
                             WKAuthorizationBlockedPreparationIncomplete])
        if([value isEqualToString:known]) return known;
    return nil;
}

NSString *WKAuthorizationPreflightState(id deviceIdentifier) {
    if(![deviceIdentifier isKindOfClass:NSString.class]) return WKAuthorizationBlockedNotEnrolled;
    NSString *identifier=(NSString *)deviceIdentifier;
    if(!identifier.length || [identifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>WKAuthorizationMaximumIdentifier)
        return WKAuthorizationBlockedNotEnrolled;
    return nil;
}

NSString *WKAuthorizationBlockedMessage(NSString *state) {
    if([state isEqualToString:WKAuthorizationBlockedNotEnrolled])
        return @"This iPad is not enrolled for the developer service, so no memory was prepared and the game was not "
            "started. Enrolment is a one-time step from a Mac: run tools/enroll.sh with this iPad connected and "
            "unlocked, then reopen WolkaraForever.";
    if([state isEqualToString:WKAuthorizationBlockedUntrustedPeer])
        return @"This iPad answered, but its pairing identity did not verify, so nothing was prepared and the game was "
            "not started. Enrol again from the Mac with tools/enroll.sh if the iPad was erased, restored or paired "
            "from a different Mac.";
    if([state isEqualToString:WKAuthorizationBlockedDeveloperImage])
        return @"This iPad's developer service answered but did not offer a usable debugger service, so nothing was "
            "prepared and the game was not started. Confirm Developer Mode is on and the developer disk image is "
            "mounted, then try again.";
    if([state isEqualToString:WKAuthorizationBlockedServiceUnavailable])
        return @"This iPad's local developer service could not be reached, so nothing was prepared and the game was "
            "not started. Reopen WolkaraForever to retry; if it keeps happening, enrol again from the Mac with "
            "tools/enroll.sh.";
    if([state isEqualToString:WKAuthorizationBlockedPreparationIncomplete])
        return @"Memory preparation finished without a confirmed detach, so the game was not started. Reopen "
            "WolkaraForever to retry.";
    return @"The developer service could not prepare this launch, so the game was not started. The exact step is "
        "written to Documents/local-game-setup.txt; reopen WolkaraForever to retry.";
}
