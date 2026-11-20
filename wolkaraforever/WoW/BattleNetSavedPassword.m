#import "BattleNetSavedPassword.h"
#import "../App/WolkaraForeverLog.h"
#import <Security/Security.h>

// The launcher's experimental login switch. Read here rather than passed in: the login owns it,
// the keyboard reads it, and this class is the one place that joins the two.
static NSString *const LoginDefaultsKey = @"WoWBrowserLogin";
// Whether a password is kept. A flag, never the value, so "is one saved?" costs no Face ID.
static NSString *const SavedDefaultsKey = @"WolkaraForeverBattleNetSavedPassword";
// The Keychain item: one account, one service, one password.
static NSString *const DefaultService = @"local.wolkaraforever.game-password";
static NSString *const Account = @"battle.net";

// The keyboard's crossings, spelled out here for the same reason the Composer's are spelled out in
// the adapter: the keyboard is built into a compatibility library this layer does not link, so a
// call cannot exist. Touch/TouchControls.h declares these exact names and keys.
static NSNotificationName const AvailabilityNotification = @"AKTouchSavedPasswordAvailability";
static NSNotificationName const ReadRequestNotification = @"AKTouchSavedPasswordReadRequest";
static NSNotificationName const StoreRequestNotification = @"AKTouchSavedPasswordStoreRequest";
static NSNotificationName const ForgetRequestNotification = @"AKTouchSavedPasswordForgetRequest";
static NSString *const EnabledKey = @"enabled";
static NSString *const ReplyKey = @"reply";
static NSString *const ValueKey = @"password";

// Test seam only: the tests give the item a service of their own so a test run cannot touch the
// player's, and drop the access control because a macOS test host has no Face ID to answer. The
// app never sets either.
static NSString *ServiceOverride;
static BOOL PlainProtection;

static NSString *ServiceName(void) {
    return ServiceOverride ?: DefaultService;
}

// The item as queried, described once so the add, the update, the read and the delete cannot
// disagree about which password they mean.
static NSDictionary *ItemQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: ServiceName(),
             (__bridge id)kSecAttrAccount: Account,
             (__bridge id)kSecAttrSynchronizable: @NO};
}

static void SetSavedFlag(BOOL saved) {
    [NSUserDefaults.standardUserDefaults setBool:saved forKey:SavedDefaultsKey];
}

// Stores one password, replacing any earlier one. An existing item is updated rather than deleted
// and re-added: a store that is refused - no passcode, no keychain entitlement - must leave the
// password the player already had in place, not take it away. Returns the Keychain's own status.
static OSStatus StorePassword(NSString *password) {
    if (!password.length) return errSecParam;
    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return errSecParam;
    NSMutableDictionary *item = [ItemQuery() mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    if (PlainProtection) {
        item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    } else {
        CFErrorRef error = NULL;
        SecAccessControlRef access = SecAccessControlCreateWithFlags(NULL,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, kSecAccessControlUserPresence, &error);
        if (!access) {
            if (error) CFRelease(error);
            return errSecParam;
        }
        item[(__bridge id)kSecAttrAccessControl] = (__bridge_transfer id)access;
    }
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status != errSecDuplicateItem) return status;
    // The protection class of an item is fixed when it is added; only the secret changes here.
    return SecItemUpdate((__bridge CFDictionaryRef)ItemQuery(),
                         (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
}

// Reads it. Off the main thread, because with user presence the call is what shows Face ID and it
// waits for the answer. The completion always arrives on the main queue.
static void ReadPassword(void (^done)(NSString *password, OSStatus status)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary *query = [ItemQuery() mutableCopy];
        query[(__bridge id)kSecReturnData] = @YES;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        NSString *password = nil;
        if (status == errSecSuccess && result) {
            NSData *data = (__bridge_transfer NSData *)result;
            result = NULL;
            password = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if (result) CFRelease(result);
        dispatch_async(dispatch_get_main_queue(), ^{ done(password, status); });
    });
}

static OSStatus ForgetPassword(void) {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)ItemQuery());
    // Nothing saved is the state the caller asked for.
    return status == errSecItemNotFound ? errSecSuccess : status;
}

@implementation TKBattleNetSavedPassword
+ (BOOL)loginEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:LoginDefaultsKey];
}
+ (BOOL)hasSavedPassword {
    return [NSUserDefaults.standardUserDefaults boolForKey:SavedDefaultsKey];
}
+ (void)forget {
    OSStatus status = ForgetPassword();
    SetSavedFlag(NO);
    WKLog("battle-login", @"saved password forgotten status=%d", (int)status);
    [self postAvailability];
}
+ (void)postAvailability {
    [NSNotificationCenter.defaultCenter postNotificationName:AvailabilityNotification object:self
        userInfo:@{EnabledKey: @([self loginEnabled])}];
}
+ (void)useService:(NSString *)service plainProtection:(BOOL)plain {
    if (service.length) ServiceOverride = [service copy];
    PlainProtection = plain;
}

+ (void)begin {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        // Read: the player tapped the key. Answer with the password, or with nothing so the
        // keyboard can offer to save one. Refused while the feature is off.
        [center addObserverForName:ReadRequestNotification object:nil queue:NSOperationQueue.mainQueue
                         usingBlock:^(NSNotification *note) {
            void (^reply)(NSString *) = note.userInfo[ReplyKey];
            if (!reply) return;
            if (![self loginEnabled]) {
                WKLog("battle-login", @"saved password read refused: the experimental login is off");
                reply(nil);
                return;
            }
            ReadPassword(^(NSString *password, OSStatus status) {
                // The status and whether there was one; never the password itself.
                WKLog("battle-login", @"saved password read status=%d found=%d",
                      (int)status, password.length > 0);
                reply(password);
            });
        }];
        // Store: the player confirmed the save prompt.
        [center addObserverForName:StoreRequestNotification object:nil queue:NSOperationQueue.mainQueue
                         usingBlock:^(NSNotification *note) {
            void (^reply)(BOOL) = note.userInfo[ReplyKey];
            NSString *password = note.userInfo[ValueKey];
            BOOL allowed = [self loginEnabled] && [password isKindOfClass:NSString.class];
            OSStatus status = allowed ? StorePassword(password) : errSecParam;
            if (status == errSecSuccess) SetSavedFlag(YES);
            WKLog("battle-login", @"saved password store status=%d", (int)status);
            if (reply) reply(status == errSecSuccess);
            [self postAvailability];
        }];
        // Forget: held the key, or the setting went off.
        [center addObserverForName:ForgetRequestNotification object:nil queue:NSOperationQueue.mainQueue
                         usingBlock:^(NSNotification *note) {
            (void)note;
            [self forget];
        }];
        [self postAvailability];
    });
}
@end
