#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Browser callback parsing is only format validation. Blizzard validates the ticket
// when the unmodified game signs in. No password or ticket is logged.
//
// Ticket lifecycle (hardened local build):
//   1. The browser callback ticket is held in process memory only. It is never
//      written to NSUserDefaults, files, the Keychain or logs while waiting.
//   2. Immediately before the guest starts, the ticket is consumed exactly once:
//      it is encoded into the `net.battle` launch preferences the game reads,
//      and the in-memory copy is dropped.
//   3. The launch preferences (WEB_TOKEN, REGION, LOCALE, GAME_ACCOUNT, ACCOUNT_TS)
//      are cleared as soon as the game removes WEB_TOKEN, when the game returns,
//      when the ticket's lifetime ends, and on every process start.
BOOL TKBattleNetTrustedURL(NSURL *url);
// Federated identity pages may be outside Blizzard's domains. They are allowed only in the
// opt-in browser; only a Blizzard-origin page may deliver the game callback.
BOOL TKBattleNetFederatedURL(NSURL *url);
NSString * _Nullable TKBattleNetCallbackTicket(NSURL *url);
// The game's own handoff wire format (fixed-entropy PBKDF2 + AES-CBC, zero IV). The
// unmodified game decrypts WEB_TOKEN with exactly this, so it cannot be changed. It is
// an encoding, not protection: anyone holding the plist can decode it. Protection comes
// from the ticket never being written before launch and being removed right after.
NSData * _Nullable TKBattleNetEncodeLaunchTicket(NSString *ticket, NSString *userName);
BOOL TKBattleNetWriteTicket(NSString *ticket, NSString *userName, NSString *region,
                          NSString *locale, NSString *domain);
void TKBattleNetClearTicket(NSString *domain);
// Seconds a received ticket stays usable, and the longest launch preferences live.
extern const NSTimeInterval TKBattleNetTicketLifetime;
@interface TKBattleNetSession : NSObject
+ (void)beginProcess;
// Validates and keeps the ticket in memory only. Nothing is written to storage.
+ (BOOL)acceptTicket:(NSString *)ticket region:(NSString *)region locale:(NSString *)locale;
+ (BOOL)isReady;
// Drops the in-memory ticket and clears every launch preference.
+ (void)clear;
// Arguments the next start would add. Does not consume the ticket.
+ (NSArray<NSString *> *)argumentsForProfile:(nullable NSString *)profile;
// Consumes the ticket once: writes the launch preferences for this start, forgets the
// ticket, schedules their removal and returns the launcher-login arguments. Writes
// nothing and returns no arguments for other profiles or without a ready ticket.
+ (NSArray<NSString *> *)handOffForProfile:(nullable NSString *)profile;
// The game returned or could not start: remove the launch preferences now.
+ (void)gameEnded;
// Test seam: handOffForProfile: against an isolated preferences domain.
+ (NSArray<NSString *> *)handOffForProfile:(nullable NSString *)profile domain:(NSString *)domain
                                clearAfter:(NSTimeInterval)seconds;
@end
NS_ASSUME_NONNULL_END
