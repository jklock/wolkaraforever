// Synthetic tickets only. Never access the user's real net.battle preferences.
#import <Foundation/Foundation.h>
#import "../launcher/WoW/BattleNetSession.h"
#include <assert.h>

static id Value(NSString *domain, NSString *name) {
    return CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)[@"Launch Options/WoW/" stringByAppendingString:name],
        (__bridge CFStringRef)domain));
}
int main(void) { @autoreleasepool {
    NSString *ticket=@"US-0123456789abcdef0123456789abcdef-123456789";
    NSString *callback=[@"http://localhost:0/?ST=" stringByAppendingString:ticket];
    assert([TKBattleNetCallbackTicket([NSURL URLWithString:callback]) isEqual:ticket]);
    for (NSString *bad in @[
        [callback stringByReplacingOccurrencesOfString:@"http:" withString:@"https:"],
        [callback stringByReplacingOccurrencesOfString:@"localhost" withString:@"localhost.evil.test"],
        [callback stringByReplacingOccurrencesOfString:@"localhost" withString:@"user@localhost"],
        [callback stringByReplacingOccurrencesOfString:@":0/" withString:@":80/"],
        [callback stringByReplacingOccurrencesOfString:@"/?" withString:@"/other?"],
        [callback stringByAppendingString:@"#fragment"],
        [callback stringByAppendingFormat:@"&ST=%@",ticket],
        @"http://localhost:0/?ST=", @"http://localhost:0/?ST=not-a-ticket",
        @"http://localhost:0/?ST=US-0123456789abcdef0123456789abcdef-0",
        [callback stringByAppendingString:[@"x" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0]]])
        assert(!TKBattleNetCallbackTicket([NSURL URLWithString:bad]));
    for (NSString *good in @[@"https://us.battle.net/login/en/", @"https://account.battle.net", @"https://blizzard.com:443/"])
        assert(TKBattleNetTrustedURL([NSURL URLWithString:good]));
    for (NSString *bad in @[@"http://us.battle.net", @"https://battle.net.evil.test", @"https://evilbattle.net", @"https://user@battle.net", @"https://battle.net:80", @"file:///battle.net"])
        assert(!TKBattleNetTrustedURL([NSURL URLWithString:bad]));
    NSData *encrypted=TKBattleNetEncryptTicket(ticket,@"testuser");
    NSMutableString *hex=[NSMutableString new];
    const unsigned char *bytes=encrypted.bytes;
    for (NSUInteger i=0;i<encrypted.length;i++) [hex appendFormat:@"%02x",bytes[i]];
    // Independent fixture from Waypoint's PBKDF2/AES algorithm.
    assert([hex isEqual:@"eaf1d64a585191b2d1544912b0041d0d34b9f4506cc2337d83bf0acb22397d6a4164b9bce5b47562d2de8c1b5c638d92"]);
    assert(!TKBattleNetEncryptTicket(@"",@"testuser"));
    NSData *emptyUserCipher=TKBattleNetEncryptTicket(ticket,@"");
    [hex setString:@""];
    bytes=emptyUserCipher.bytes;
    for (NSUInteger i=0;i<emptyUserCipher.length;i++) [hex appendFormat:@"%02x",bytes[i]];
    // Cross-checked with Python hashlib.pbkdf2_hmac and OpenSSL AES-CBC.
    assert([hex isEqual:@"ef20f055d515ead3a87eb4fc91ab460bcb100a6b61039ea260a762d1f21bd9b17eb8cfe547e0193a5c4d64c6e4fbc222"]);
    assert(![TKBattleNetEncryptTicket(ticket,@"another-user") isEqual:encrypted]);
    NSString *domain=[@"org.wolkaraforever.test.browser-login." stringByAppendingString:NSUUID.UUID.UUIDString];
    assert(TKBattleNetWriteTicket(ticket,@"testuser",@"US",@"enUS",domain));
    assert([Value(domain,@"WEB_TOKEN") isEqual:encrypted]);
    assert(![Value(domain,@"WEB_TOKEN") isEqual:[ticket dataUsingEncoding:NSUTF8StringEncoding]]);
    assert([Value(domain,@"REGION") isEqual:@"US"]);
    assert([Value(domain,@"LOCALE") isEqual:@"enUS"]);
    assert(!TKBattleNetWriteTicket(@"invalid",@"testuser",@"US",@"enUS",domain));
    assert(!TKBattleNetWriteTicket(ticket,@"testuser",@"INVALID",@"enUS",domain));
    assert(!TKBattleNetWriteTicket(ticket,@"testuser",@"US",@"invalid",domain));
    assert([Value(domain,@"WEB_TOKEN") isEqual:encrypted]);
    TKBattleNetClearTicket(domain);
    for (NSString *name in @[@"WEB_TOKEN",@"REGION",@"LOCALE",@"GAME_ACCOUNT",@"ACCOUNT_TS"])
        assert(!Value(domain,name));
    assert([TKBattleNetSession argumentsForProfile:@"wow-forever"].count==0);
    assert([TKBattleNetSession argumentsForProfile:@"another-app"].count==0);
    puts("PASS Battle.net callback, encryption fixture and isolated preference lifecycle");
} return 0; }
