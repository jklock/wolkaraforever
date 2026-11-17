#import "BattleNetSession.h"
#import <CommonCrypto/CommonCrypto.h>
#include <string.h>

// macOS handoff format adapted from Waypoint (0BSD):
// https://github.com/wowlocal/waypoint-launcher/blob/main/Sources/WaypointCore/LaunchOptions.swift
// This creates a new handoff from the user's browser login. It never reads the
// desktop Battle.net application's credentials or changes the game executable.
static NSString *const Domain=@"net.battle";
static NSString *const Prefix=@"Launch Options/WoW/";
static NSDate *readyUntil;

BOOL TKBattleNetTrustedURL(NSURL *url) {
    if (![url.scheme.lowercaseString isEqual:@"https"] || url.user || url.password ||
        (url.port && url.port.integerValue!=443)) return NO;
    NSString *host=url.host.lowercaseString;
    return [host isEqual:@"battle.net"] || [host hasSuffix:@".battle.net"] ||
           [host isEqual:@"blizzard.com"] || [host hasSuffix:@".blizzard.com"];
}
static BOOL TicketValid(NSString *ticket) {
    if (!ticket.length || ticket.length>128) return NO;
    NSRange match=[ticket rangeOfString:@"\\A(?:US|EU|KR|TW|CN)-[0-9a-fA-F]{32}-[1-9][0-9]*\\z"
                                      options:NSRegularExpressionSearch];
    return match.location!=NSNotFound && match.length==ticket.length;
}
NSString *TKBattleNetCallbackTicket(NSURL *url) {
    if (url.absoluteString.length>8192 || ![url.scheme isEqual:@"http"] ||
        ![url.host isEqual:@"localhost"] || ![url.port isEqual:@0] ||
        (url.path.length && ![url.path isEqual:@"/"]) || url.user || url.password || url.fragment) return nil;
    NSArray *items=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems;
    NSString *ticket=nil;
    for (NSURLQueryItem *item in items) if ([item.name isEqual:@"ST"]) {
        if (ticket || !TicketValid(item.value?:@"")) return nil;
        ticket=item.value;
    }
    return ticket;
}
NSData *TKBattleNetEncryptTicket(NSString *ticket, NSString *userName) {
    if (!TicketValid(ticket)) return nil;
    uint8_t entropy[16]={200,118,244,174,76,149,46,254,242,250,15,84,25,192,156,67};
    for (NSUInteger i=0;i<MIN(userName.length,16);i++) entropy[i]^=(uint8_t)[userName characterAtIndex:i];
    const uint8_t salt[]="someSalt";
    uint8_t key[16]={0}, iv[16]={0};
    int status=CCKeyDerivationPBKDF(kCCPBKDF2,(const char *)entropy,sizeof entropy,
                                   salt,sizeof salt-1,kCCPRFHmacAlgSHA1,1000,key,sizeof key);
    memset_s(entropy,sizeof entropy,0,sizeof entropy);
    if (status!=kCCSuccess) { memset_s(key,sizeof key,0,sizeof key); return nil; }
    NSData *plain=[ticket dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *cipher=[NSMutableData dataWithLength:plain.length+kCCBlockSizeAES128];
    size_t written=0;
    status=CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key,sizeof key,iv,
                   plain.bytes,plain.length,cipher.mutableBytes,cipher.length,&written);
    memset_s(key,sizeof key,0,sizeof key);
    if (status!=kCCSuccess) return nil;
    cipher.length=written;
    return cipher;
}
void TKBattleNetClearTicket(NSString *domain) {
    for (NSString *name in @[@"WEB_TOKEN",@"REGION",@"LOCALE",@"GAME_ACCOUNT",@"ACCOUNT_TS"])
        CFPreferencesSetAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:name],NULL,(__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}
BOOL TKBattleNetWriteTicket(NSString *ticket, NSString *userName, NSString *region, NSString *locale, NSString *domain) {
    if (![@[@"US",@"EU",@"KR",@"TW"] containsObject:region] ||
        ![@[@"enUS",@"frFR",@"deDE",@"esES"] containsObject:locale]) return NO;
    NSData *encrypted=TKBattleNetEncryptTicket(ticket,userName);
    if (!encrypted) return NO;
    TKBattleNetClearTicket(domain);
    NSDictionary *values=@{@"WEB_TOKEN":encrypted,@"REGION":region,@"LOCALE":locale};
    for (NSString *name in values)
        CFPreferencesSetAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:name],
                                 (__bridge CFPropertyListRef)values[name],(__bridge CFStringRef)domain);
    BOOL saved=CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    NSData *readback=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:@"WEB_TOKEN"],(__bridge CFStringRef)domain));
    if (!saved || ![readback isEqual:encrypted]) { TKBattleNetClearTicket(domain); return NO; }
    return YES;
}
@implementation TKBattleNetSession
+ (void)beginProcess {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ [self clear]; });
}
+ (BOOL)acceptTicket:(NSString *)ticket region:(NSString *)region locale:(NSString *)locale {
    // Foundation returns an empty username in an iOS sandbox. The public
    // handoff algorithm accepts that: no username bytes are XORed into entropy.
    [self clear];
    NSString *name=NSUserName()?:@"";
    if (!TKBattleNetWriteTicket(ticket,name,region.uppercaseString,locale,Domain)) return NO;
    readyUntil=[NSDate dateWithTimeIntervalSinceNow:600];
    return YES;
}
+ (BOOL)isReady {
    if (readyUntil && readyUntil.timeIntervalSinceNow<=0) [self clear];
    return readyUntil!=nil;
}
+ (void)clear { readyUntil=nil; TKBattleNetClearTicket(Domain); }
+ (NSArray<NSString *> *)argumentsForProfile:(NSString *)profile {
    return [self isReady] && [profile isEqual:@"wow-forever"]?@[@"-launcherlogin",@"-uid",@"wowf"]:@[];
}
@end
