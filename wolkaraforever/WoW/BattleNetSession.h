#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Browser callback parsing is only format validation. Blizzard validates the ticket
// when the unmodified game signs in. No password or ticket is logged.
BOOL TKBattleNetTrustedURL(NSURL *url);
NSString * _Nullable TKBattleNetCallbackTicket(NSURL *url);
NSData * _Nullable TKBattleNetEncryptTicket(NSString *ticket, NSString *userName);
BOOL TKBattleNetWriteTicket(NSString *ticket, NSString *userName, NSString *region,
                          NSString *locale, NSString *domain);
void TKBattleNetClearTicket(NSString *domain);
@interface TKBattleNetSession : NSObject
+ (void)beginProcess;
+ (BOOL)acceptTicket:(NSString *)ticket region:(NSString *)region locale:(NSString *)locale;
+ (BOOL)isReady;
+ (void)clear;
+ (NSArray<NSString *> *)argumentsForProfile:(nullable NSString *)profile;
@end
NS_ASSUME_NONNULL_END
