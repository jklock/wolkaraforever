#import "BattleNetSession.h"
#import <CommonCrypto/CommonCrypto.h>
#include <string.h>

// macOS handoff format adapted from Waypoint (0BSD):
// https://github.com/wowlocal/waypoint-launcher/blob/main/Sources/WaypointCore/LaunchOptions.swift
// This creates a new handoff from the user's browser login. It never reads the
// desktop Battle.net application's credentials or changes the game executable.
//
// Hardened lifecycle (differs from upstream PR #98): the ticket is NOT written to
// preferences when the browser returns it. It waits in memory, is written only at
// the moment the game starts, and the launch preferences are removed again as soon
// as the game has taken WEB_TOKEN, when the game returns, or after a hard deadline.
static NSString *const Domain=@"net.battle";
static NSString *const Prefix=@"Launch Options/WoW/";
const NSTimeInterval TKBattleNetTicketLifetime=600;
// After the game removes WEB_TOKEN, give it this long to finish reading the rest.
static const NSTimeInterval ConsumedGrace=30;

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
NSData *TKBattleNetEncodeLaunchTicket(NSString *ticket, NSString *userName) {
    // Wire format fixed by the game client (RegistryDarwin). Not a secret.
    if (!TicketValid(ticket)) return nil;
    uint8_t entropy[16]={200,118,244,174,76,149,46,254,242,250,15,84,25,192,156,67};
    for (NSUInteger i=0;i<MIN(userName.length,16);i++) entropy[i]^=(uint8_t)[userName characterAtIndex:i];
    const uint8_t salt[]="someSalt";
    uint8_t key[16]={0}, iv[16]={0};
    int status=CCKeyDerivationPBKDF(kCCPBKDF2,(const char *)entropy,sizeof entropy,
                                   salt,sizeof salt-1,kCCPRFHmacAlgSHA1,1000,key,sizeof key);
    memset_s(entropy,sizeof entropy,0,sizeof entropy);
    if (status!=kCCSuccess) { memset_s(key,sizeof key,0,sizeof key); return nil; }
    NSMutableData *plain=[[ticket dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    NSMutableData *cipher=[NSMutableData dataWithLength:plain.length+kCCBlockSizeAES128];
    size_t written=0;
    status=CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key,sizeof key,iv,
                   plain.bytes,plain.length,cipher.mutableBytes,cipher.length,&written);
    memset_s(key,sizeof key,0,sizeof key);
    memset_s(plain.mutableBytes,plain.length,0,plain.length);
    if (status!=kCCSuccess) return nil;
    cipher.length=written;
    return cipher;
}
void TKBattleNetClearTicket(NSString *domain) {
    for (NSString *name in @[@"WEB_TOKEN",@"REGION",@"LOCALE",@"GAME_ACCOUNT",@"ACCOUNT_TS"])
        CFPreferencesSetAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:name],NULL,(__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}
static BOOL TokenPresent(NSString *domain) {
    CFPropertyListRef value=CFPreferencesCopyAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:@"WEB_TOKEN"],
                                                      (__bridge CFStringRef)domain);
    if (value) CFRelease(value);
    return value!=NULL;
}
BOOL TKBattleNetWriteTicket(NSString *ticket, NSString *userName, NSString *region, NSString *locale, NSString *domain) {
    if (![@[@"US",@"EU",@"KR",@"TW"] containsObject:region] ||
        ![@[@"enUS",@"frFR",@"deDE",@"esES"] containsObject:locale]) return NO;
    NSData *encoded=TKBattleNetEncodeLaunchTicket(ticket,userName);
    if (!encoded) return NO;
    TKBattleNetClearTicket(domain);
    NSDictionary *values=@{@"WEB_TOKEN":encoded,@"REGION":region,@"LOCALE":locale};
    for (NSString *name in values)
        CFPreferencesSetAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:name],
                                 (__bridge CFPropertyListRef)values[name],(__bridge CFStringRef)domain);
    BOOL saved=CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    NSData *readback=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)[Prefix stringByAppendingString:@"WEB_TOKEN"],(__bridge CFStringRef)domain));
    if (!saved || ![readback isEqual:encoded]) { TKBattleNetClearTicket(domain); return NO; }
    return YES;
}

// All state below is guarded by Lock(). The ticket lives only in these variables.
static NSString *heldTicket, *heldRegion, *heldLocale;
static NSDate *readyUntil;
static NSString *handedOffDomain;   // domain holding launch prefs written by this process
static BOOL processBegan;           // the app (not a unit test) owns net.battle
static dispatch_source_t watcher;
static NSUInteger generation;
static NSObject *Lock(void) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock=[NSObject new]; });
    return lock;
}
static void DropTicketLocked(void) { heldTicket=nil; heldRegion=nil; heldLocale=nil; readyUntil=nil; }
static void StopWatcherLocked(void) {
    if (watcher) { dispatch_source_cancel(watcher); watcher=nil; }
    generation++;
}
static void ClearHandOffLocked(void) {
    StopWatcherLocked();
    if (handedOffDomain) { TKBattleNetClearTicket(handedOffDomain); handedOffDomain=nil; }
}

@implementation TKBattleNetSession
+ (void)beginProcess {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @synchronized (Lock()) { processBegan=YES; }
        // A crash or kill during a previous game leaves nothing behind for long.
        [self clear];
    });
}
+ (BOOL)acceptTicket:(NSString *)ticket region:(NSString *)region locale:(NSString *)locale {
    [self clear];
    NSString *upper=region.uppercaseString;
    if (!TicketValid(ticket) || ![@[@"US",@"EU",@"KR",@"TW"] containsObject:upper] ||
        ![@[@"enUS",@"frFR",@"deDE",@"esES"] containsObject:locale]) return NO;
    @synchronized (Lock()) {
        heldTicket=[ticket copy]; heldRegion=upper; heldLocale=[locale copy];
        readyUntil=[NSDate dateWithTimeIntervalSinceNow:TKBattleNetTicketLifetime];
    }
    return YES;
}
+ (BOOL)isReady {
    @synchronized (Lock()) {
        if (readyUntil && readyUntil.timeIntervalSinceNow<=0) DropTicketLocked();
        return heldTicket!=nil;
    }
}
+ (void)clear {
    @synchronized (Lock()) {
        DropTicketLocked();
        ClearHandOffLocked();
        if (processBegan) TKBattleNetClearTicket(Domain);
    }
}
+ (void)gameEnded {
    @synchronized (Lock()) {
        DropTicketLocked();
        ClearHandOffLocked();
        if (processBegan) TKBattleNetClearTicket(Domain);
    }
}
+ (NSArray<NSString *> *)argumentsForProfile:(NSString *)profile {
    return [self isReady] && [profile isEqual:@"wow-forever"]?@[@"-launcherlogin",@"-uid",@"wowf"]:@[];
}
+ (NSArray<NSString *> *)handOffForProfile:(NSString *)profile {
    return [self handOffForProfile:profile domain:Domain clearAfter:TKBattleNetTicketLifetime];
}
+ (NSArray<NSString *> *)handOffForProfile:(NSString *)profile domain:(NSString *)domain clearAfter:(NSTimeInterval)seconds {
    if (![profile isEqual:@"wow-forever"] || ![self isReady]) return @[];
    @synchronized (Lock()) {
        NSString *ticket=heldTicket, *region=heldRegion, *locale=heldLocale;
        // Single use: the in-memory copy is gone whether or not the write succeeds.
        DropTicketLocked();
        ClearHandOffLocked();
        if (!ticket) return @[];
        // Foundation returns an empty username in an iOS sandbox. The public handoff
        // algorithm accepts that: no username bytes are XORed into the entropy.
        if (!TKBattleNetWriteTicket(ticket,NSUserName()?:@"",region,locale,domain)) return @[];
        ticket=nil;
        handedOffDomain=[domain copy];
        NSUInteger mine=++generation;
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
        __block NSDate *consumedAt=nil;
        // A background queue: the game runs on the main thread until it returns.
        dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,
            dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        NSTimeInterval interval=MIN(1.0,MAX(seconds/4,0.05));
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(interval*NSEC_PER_SEC)),
                                  (uint64_t)(interval*NSEC_PER_SEC),(uint64_t)(0.1*NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            @synchronized (Lock()) {
                if (generation!=mine || !handedOffDomain) return;
                BOOL expired=deadline.timeIntervalSinceNow<=0;
                if (!consumedAt && !TokenPresent(handedOffDomain)) consumedAt=[NSDate date];
                BOOL settled=consumedAt && -consumedAt.timeIntervalSinceNow>=MIN(ConsumedGrace,seconds);
                if (expired || settled) ClearHandOffLocked();
            }
        });
        watcher=timer;
        dispatch_resume(timer);
    }
    return @[@"-launcherlogin",@"-uid",@"wowf"];
}
@end
