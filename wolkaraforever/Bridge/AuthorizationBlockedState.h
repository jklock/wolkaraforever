#pragma once
#import <Foundation/Foundation.h>

// The developer-service path refuses rather than falling back, and every refusal
// has to reach the person who tapped Play as a sentence that says what happened
// and what to do next. This is the single place that decides which sentence a
// state gets, so the launch UI and the tests cannot drift apart.
//
// The states are the helper's own vocabulary, not user text. A state is one of
// WKAuthorizationBlockedNotEnrolled and the constants below; anything else,
// including a missing value, is treated as "no state" and never as a reason to
// launch.

FOUNDATION_EXPORT NSString *const WKAuthorizationBlockedNotEnrolled;
FOUNDATION_EXPORT NSString *const WKAuthorizationBlockedUntrustedPeer;
FOUNDATION_EXPORT NSString *const WKAuthorizationBlockedDeveloperImage;
FOUNDATION_EXPORT NSString *const WKAuthorizationBlockedServiceUnavailable;
FOUNDATION_EXPORT NSString *const WKAuthorizationBlockedPreparationIncomplete;

// A helper reply's blockedState value, normalised. Returns nil when the value is
// absent, empty, not a string, or not one of the five states above - an
// unrecognised state must not be reported as a specific cause.
FOUNDATION_EXPORT NSString *WKAuthorizationBlockedState(id replyValue);

// The state that a launch must stop on before it starts a route at all.
// deviceIdentifier is what the app stored when enrolment was imported.
// Returns WKAuthorizationBlockedNotEnrolled for a missing, empty, overlong or
// non-string identifier, and nil when it looks usable. This says nothing about
// whether the helper still holds the record; only the helper can answer that.
FOUNDATION_EXPORT NSString *WKAuthorizationPreflightState(id deviceIdentifier);

// The sentence for a state, including the generic one for nil/unknown. Never
// empty, so a caller can show it unconditionally.
FOUNDATION_EXPORT NSString *WKAuthorizationBlockedMessage(NSString *state);
