// WolkaraForever layer: how a controller is named when something has to be remembered
// about it.
//
// The identity is the *model*: vendor and product category, slugged. GameController
// exposes no serial number, so two identical pads are indistinguishable to this process
// and share one profile. That is stated to the reader in the Controller Manager page and
// in development/technical/CONTROLLER_PROFILES.md rather than papered over with a
// per-device claim the platform cannot support.
//
// It lives in a file of its own because two owners need it and neither may include the
// other's implementation: the inspector (which logs it) and the manager (which keys a
// profile on it). Declared here, implemented once.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GCController;

/// A controller's model identity: `slug(vendorName).slug(productCategory)`, for example
/// `xbox.bluetooth.gamepad.xbox.one`. Never the display name (a key should not be), and
/// never the player index (which moves as pads come and go).
FOUNDATION_EXPORT NSString *AKControllerIdentity(GCController * _Nullable pad);

/// The same identity from the two strings it is built from, so a caller that has already
/// read them does not have to keep the pad alive.
FOUNDATION_EXPORT NSString *AKControllerIdentityForNames(NSString * _Nullable vendorName,
                                                         NSString * _Nullable productCategory);

NS_ASSUME_NONNULL_END
