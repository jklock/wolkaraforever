#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// One game password, kept on this device, and only while the experimental Battle.net login is on.
//
// Why this lives in the login and not in the keyboard: the keyboard is a compatibility library the
// guest loads, and it must stay free of the app's storage. What a password is, whether the player
// may keep one, what happens when the Keychain refuses, and what forgets it are the login's
// decisions. The keyboard asks and types the answer into the game's own password field; it never
// holds a Keychain query.
//
// The item is a generic password in this device's Keychain, protected by
// kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly and user presence (Face ID or the passcode). It
// is therefore unreadable while the device is locked, never synchronised, never written to a
// preference, a file or a log - not its length, not a prefix - and it never leaves the device. A
// plain preference flag records that one exists, so asking whether one is kept never shows Face ID.
//
// The keyboard's crossings, by name because it is a dylib this layer does not link (the same
// reason the Composer's crossings exist). The names and keys are declared in
// Touch/TouchControls.h; they are repeated in the implementation.
//   AKTouchSavedPasswordReadRequest   userInfo "reply": void(^)(NSString *password)  -> read
//   AKTouchSavedPasswordStoreRequest  userInfo "password", "reply": void(^)(BOOL stored) -> store
//   AKTouchSavedPasswordForgetRequest                                              -> forget
// and this class posts AKTouchSavedPasswordAvailability with "enabled" whenever the answer to
// "may the key be offered?" changes, so the key follows the setting without a relaunch.
@interface TKBattleNetSavedPassword : NSObject
// Answers the keyboard for this process. Called once, from main(), before the first screen.
+ (void)begin;
// The experimental login's setting (`WoWBrowserLogin`). The saved password follows it: off means
// no key is offered and no item is kept.
+ (BOOL)loginEnabled;
// Whether a password is kept. Reads the flag, not the Keychain, so asking never shows Face ID.
+ (BOOL)hasSavedPassword;
// Forgets it: deletes the item and clears the flag. Safe when there is none.
+ (void)forget;
// Tells the keyboard whether the feature is on. Posted by this class after every change; the
// launcher calls it when it flips the setting, so the key appears or goes away at once.
+ (void)postAvailability;
// Test seam: the Keychain item's service name, and a mode that stores without a user-presence
// access control because a macOS test host has no Face ID to answer. Never called by the app.
+ (void)useService:(nullable NSString *)service plainProtection:(BOOL)plain;
@end
NS_ASSUME_NONNULL_END
