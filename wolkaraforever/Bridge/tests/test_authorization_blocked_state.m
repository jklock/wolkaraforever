#import <Foundation/Foundation.h>
#import "AuthorizationBlockedState.h"

// Every developer-service state must reach the launch UI as its own sentence, and
// an unrecognised state must never be promoted to a launch. No device, route,
// pairing record or game file is involved: this is the mapping alone.

static void require(BOOL value,NSString *message) { if(!value) { NSLog(@"FAIL: %@",message); exit(1); } }

int main(void) {
    @autoreleasepool {
        NSArray<NSString *> *states=@[WKAuthorizationBlockedNotEnrolled,WKAuthorizationBlockedUntrustedPeer,
            WKAuthorizationBlockedDeveloperImage,WKAuthorizationBlockedServiceUnavailable,
            WKAuthorizationBlockedPreparationIncomplete];
        NSMutableSet<NSString *> *messages=[NSMutableSet new];
        for(NSString *state in states) {
            require([WKAuthorizationBlockedState(state) isEqualToString:state],
                [NSString stringWithFormat:@"state %@ must round-trip",state]);
            NSString *message=WKAuthorizationBlockedMessage(state);
            require(message.length>0,[NSString stringWithFormat:@"state %@ needs a sentence",state]);
            // Two different causes that read the same are one cause to the user.
            require(![messages containsObject:message],
                [NSString stringWithFormat:@"state %@ repeats another state's sentence",state]);
            [messages addObject:message];
        }
        // Anything the helper did not name is not a specific cause.
        for(id value in @[@"",@"notEnrolled-but-not-really",[NSNull null],@(1),@[@"notEnrolled"]])
            require(WKAuthorizationBlockedState(value)==nil,@"an unknown blockedState must not be classified");
        require(WKAuthorizationBlockedState(nil)==nil,@"an absent blockedState must not be classified");
        // The generic sentence still has to exist and be distinct.
        NSString *generic=WKAuthorizationBlockedMessage(nil);
        require(generic.length>0,@"a missing state needs a sentence");
        require(![messages containsObject:generic],@"the generic sentence must differ from every state's");
        require([WKAuthorizationBlockedMessage(@"somethingElse") isEqualToString:generic],
            @"an unknown state falls back to the generic sentence");

        // Pre-flight: this is what stops a route from being started for a device
        // that cannot possibly succeed.
        for(id value in @[@"",[NSNull null],@(7),@[@""],[@"" mutableCopy]])
            require([WKAuthorizationPreflightState(value) isEqualToString:WKAuthorizationBlockedNotEnrolled],
                @"a missing device identifier must block before any route starts");
        NSString *overlong=[@"" stringByPaddingToLength:1025 withString:@"a" startingAtIndex:0];
        require([WKAuthorizationPreflightState(overlong) isEqualToString:WKAuthorizationBlockedNotEnrolled],
            @"an overlong device identifier must block");
        require(WKAuthorizationPreflightState(@"00008103-000E09A10EC3001E")==nil,
            @"a usable device identifier must not block");
        NSString *atLimit=[@"" stringByPaddingToLength:1024 withString:@"a" startingAtIndex:0];
        require(WKAuthorizationPreflightState(atLimit)==nil,@"the helper's own bound is inclusive");

        printf("PASS: 5 blocked states, each with its own sentence; unknown states are not classified; "
               "a missing, overlong or non-string device identifier blocks before a route starts\n");
    }
    return 0;
}
