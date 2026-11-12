#import <Foundation/Foundation.h>
#import "../launcher/WoW/Updater.h"
#import "../launcher/WoW/CASC.h"
#import "../launcher/WoW/Installation.h"
#include <assert.h>
#include <unistd.h>
@interface TKWoWClient (TestTransport)
- (NSURLSessionConfiguration *)sessionConfiguration;
@end
static NSData *Text(NSString *s){return [s dataUsingEncoding:NSUTF8StringEncoding];}
static void BE(NSMutableData *d,uint64_t n,NSUInteger bytes){while(bytes){uint8_t b=(uint8_t)(n>>(--bytes*8));[d appendBytes:&b length:1];}}
static NSData *Hash(NSData *d){uint8_t bytes[16];assert(TKWoWUnhex(TKWoWMD5(d),bytes));return [NSData dataWithBytes:bytes length:16];}
static NSData *Wrap(NSData *d){NSMutableData *r=[Text(@"BLTE") mutableCopy];BE(r,0,4);BE(r,'N',1);[r appendData:d];return r;}
@interface TKUpdateClient : TKWoWClient
@property(nonatomic) NSMutableDictionary *responses;
@property(nonatomic) NSMutableDictionary *counts;
@property(nonatomic) NSData *archive;
@property(nonatomic) BOOL changed;
@end
@implementation TKUpdateClient
- (instancetype)init { if((self=[super init])){_responses=[NSMutableDictionary new];_counts=[NSMutableDictionary new];}return self; }
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit error:(NSError **)error {
    NSString *key=url.lastPathComponent;_counts[key]=@([_counts[key] unsignedIntegerValue]+1);
    NSData *data=_responses[key];if(self.changed && [key isEqual:@"versions"])data=Text(@"Region|BuildConfig|CDNConfig|VersionsName\neu|11111111111111111111111111111111|22222222222222222222222222222222|changed\n");
    if(self.cancelled || !data || data.length>limit){if(error)*error=TKWoWError(@"Synthetic missing/cancelled response");return nil;}return data;
}
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size error:(NSError **)error {
    (void)url; if(offset>_archive.length || size>_archive.length-offset){if(error)*error=TKWoWError(@"Bad synthetic range");return nil;}
    _counts[@"range"]=@([_counts[@"range"] unsignedIntegerValue]+1);return [_archive subdataWithRange:NSMakeRange((NSUInteger)offset,size)];
}
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit window:(uint64_t)window error:(NSError **)error {
    (void)window;return [self fetch:url limit:limit error:error];
}
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size window:(uint64_t)window error:(NSError **)error {
    (void)window;return [self range:url offset:offset size:size error:error];
}
@end
static NSString *ReferenceResponses(NSString *name,NSData *d,NSMutableDictionary *responses){NSData *raw=Wrap(d);responses[TKWoWMD5(raw)]=raw;return [NSString stringWithFormat:@"%@ = %@ %@\n%@-size = %lu %lu\n",name,TKWoWMD5(d),TKWoWMD5(raw),name,(unsigned long)d.length,(unsigned long)raw.length];}
static NSString *Reference(NSString *name,NSData *d,TKUpdateClient *client){return ReferenceResponses(name,d,client.responses);}
static NSData *IndexObjects(NSArray<NSData *> *objects){
    NSMutableData *d=[NSMutableData new];uint32_t offset=37;
    for(NSData *raw in objects){[d appendData:Hash(raw)];BE(d,raw.length,4);BE(d,offset,4);offset+=(uint32_t)raw.length;}
    d.length=4096;[d appendData:Hash(objects.lastObject)];[d appendData:Hash(d)];
    uint8_t f[20]={1,0,0,4,4,4,16,8,0,0,0,0};f[8]=(uint8_t)objects.count;
    NSData *digest=Hash([NSData dataWithBytes:f length:20]);memcpy(f+12,digest.bytes,8);[d appendBytes:f length:20];return d;
}
static NSData *Index(NSData *raw){return IndexObjects(@[raw]);}

@interface TKCheckpointUpdater : TKWoWUpdater
@end
@implementation TKCheckpointUpdater
- (uint64_t)verificationCheckpointBytes { return 1; }
@end

@interface TKWoWUpdater (StorageTests)
- (NSNumber *)importantStorageAtPath:(NSString *)path error:(NSError **)error;
- (NSNumber *)freeStorageAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)checkStorageAtPath:(NSString *)path missingBytes:(uint64_t)missing looseBytes:(uint64_t)loose error:(NSError **)error;
@end
@interface TKStorageUpdater : TKWoWUpdater
@property(nonatomic) NSNumber *importantCapacity;
@property(nonatomic) NSNumber *freeCapacity;
@end
@implementation TKStorageUpdater
- (NSNumber *)importantStorageAtPath:(NSString *)path error:(NSError **)error {
    (void)path;if(!_importantCapacity && error)*error=TKWoWError(@"Synthetic unavailable important capacity");
    return _importantCapacity;
}
- (NSNumber *)freeStorageAtPath:(NSString *)path error:(NSError **)error {
    (void)path;
    if(!_freeCapacity && error)*error=TKWoWError(@"Synthetic unavailable filesystem capacity");
    return _freeCapacity;
}
@end
static void TestStorage(void) {
    TKStorageUpdater *updater=[[TKStorageUpdater alloc] initWithClient:[TKUpdateClient new]];
    NSError *error=nil;
    // iOS may report 115 GB for user-requested resources with only 30 GB of raw
    // free blocks. A 68 GB installation must use the former, including reclaimable caches.
    updater.importantCapacity=@115000000000ULL;updater.freeCapacity=@30000000000ULL;
    assert([updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:0 error:&error]);
    assert(!error);
    updater.importantCapacity=@66000000000ULL;
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:0 error:&error]);
    assert([error.localizedDescription containsString:@"66.0 GB available"]);
    updater.importantCapacity=@0;updater.freeCapacity=@0;
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:1 looseBytes:0 error:&error]);
    // A silent zero from the important-usage service must not hide real blocks.
    updater.freeCapacity=@115000000000ULL;error=nil;
    assert([updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:0 error:&error]);
    assert(!error);
    updater.importantCapacity=nil;error=nil;
    assert([updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:0 error:&error]);
    assert(!error);
    updater.freeCapacity=nil;error=nil;
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:1 looseBytes:0 error:&error]);
    assert([error.localizedDescription containsString:@"Could not check available storage"]);
    assert([error.localizedDescription containsString:@"Synthetic unavailable filesystem capacity"]);
    assert(![error.localizedDescription containsString:@"Not enough storage"]);
    updater.importantCapacity=@(-1);updater.freeCapacity=@115000000000ULL;error=nil;
    assert([updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:0 error:&error]);
    assert(!error);
    updater.importantCapacity=(NSNumber *)NSNull.null;updater.freeCapacity=@(-1);
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:1 looseBytes:0 error:&error]);
    assert([error.localizedDescription containsString:@"Could not check available storage"]);
    // Boundaries and overflow must not wrap into an apparently small requirement.
    updater.importantCapacity=@(67000000000ULL+1024ULL*1024*1024);
    assert([updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:0 error:&error]);
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:67000000000ULL looseBytes:1 error:&error]);
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:UINT64_MAX looseBytes:0 error:&error]);
    assert([error.localizedDescription containsString:@"requirement is too large"]);
    assert(![updater checkStorageAtPath:@"/synthetic" missingBytes:0 looseBytes:UINT64_MAX error:&error]);
    assert([error.localizedDescription containsString:@"requirement is too large"]);
}


// The update suites drive the downloader itself: this transport serves the same
// synthetic objects through NSURLSession, so an injected drop exercises the
// retry path the device uses. No socket or live CDN is involved.
static NSDictionary *RetryResponses;
static NSString *RetryDropRange;
static NSUInteger RetryLosses;
@interface TKRetryProtocol : NSURLProtocol @end
@implementation TKRetryProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *host=request.URL.host.lowercaseString;
    return [host isEqual:@"fixture.invalid"] || [host hasSuffix:@".blizzard.com"] || [host hasSuffix:@".battle.net"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    id reply=RetryResponses[self.request.URL.lastPathComponent];
    NSData *body=[reply isKindOfClass:NSDictionary.class]?reply[@"data"]:reply;
    NSString *range=[self.request valueForHTTPHeaderField:@"Range"];
    NSUInteger status=body?200:404;NSString *contentRange=nil;
    if(body && range) {
        unsigned long long first=0,last=0;
        if(sscanf(range.UTF8String,"bytes=%llu-%llu",&first,&last)!=2 || first>last || last>=body.length) {
            status=416;body=nil;
        } else {
            contentRange=[NSString stringWithFormat:@"bytes %llu-%llu/%lu",first,last,(unsigned long)body.length];
            body=[body subdataWithRange:NSMakeRange((NSUInteger)first,(NSUInteger)(last-first+1))];status=206;
        }
    }
    BOOL drop=NO;
    @synchronized(TKRetryProtocol.class) {
        if(RetryLosses && (!RetryDropRange || [range isEqual:RetryDropRange])) { RetryLosses--;drop=YES; }
    }
    NSMutableDictionary *headers=[@{@"Content-Length":[NSString stringWithFormat:@"%lu",(unsigned long)body.length]} mutableCopy];
    if(contentRange)headers[@"Content-Range"]=contentRange;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:(NSInteger)status
        HTTPVersion:@"HTTP/1.1" headerFields:headers];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        if(drop) {
            [self.client URLProtocol:self didFailWithError:
                [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]];
            return;
        }
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:body];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {
    [self.client URLProtocol:self didFailWithError:
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
}
@end
@interface TKRetryClient : TKWoWClient
@property(nonatomic) NSMutableDictionary *responses;
@end
@implementation TKRetryClient
- (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *configuration=[super sessionConfiguration];
    configuration.protocolClasses=@[TKRetryProtocol.class];return configuration;
}
@end
// Virtual retry clock: the schedule is asserted, no test sleeps a delay.
@interface TKVirtualClock : TKWoWRetryScheduler
@property(nonatomic) NSTimeInterval now;
@property(nonatomic) NSMutableArray<NSNumber *> *delays;
@end
@implementation TKVirtualClock
- (instancetype)init { if((self=[super init])){_now=5000;_delays=[NSMutableArray new];}return self; }
- (NSTimeInterval)monotonicNow { return _now; }
- (BOOL)waitUntil:(NSTimeInterval)deadline lock:(NSCondition *)lock {
    (void)lock;[self.delays addObject:@(deadline-self.now)];self.now=deadline;return YES;
}
@end
// Play eligibility is exactly what TKWoWInspectInstallation reports for the
// installed folder, so both sides read the same launcher state.
@interface TKContractApp : NSObject
@property(nonatomic) TKAppSource source;
@property(nonatomic, copy) NSString *workingDirectory;
@end
@implementation TKContractApp
@end
@interface TKContractLibrary : NSObject
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, copy) NSString *executable;
@property(nonatomic, strong) NSArray *apps;
- (NSString *)workingDirectoryForApp:(id)app error:(NSError **)error;
- (NSString *)executablePathForApp:(id)app error:(NSError **)error;
@end
@implementation TKContractLibrary
- (NSString *)workingDirectoryForApp:(id)app error:(NSError **)error { (void)app;(void)error;return _directory; }
- (NSString *)executablePathForApp:(id)app error:(NSError **)error { (void)app;(void)error;return _executable; }
@end
static TKWoWInstallation *PlayInspection(NSString *root,NSDictionary *plan) {
    TKContractApp *app=[TKContractApp new];app.source=TKAppSourceDocuments;
    app.workingDirectory=[root stringByAppendingPathComponent:@"_forever_"];
    TKContractLibrary *library=[TKContractLibrary new];library.apps=@[app];
    library.directory=app.workingDirectory;
    library.executable=[app.workingDirectory stringByAppendingPathComponent:@"Synthetic.app/Contents/MacOS/Synthetic"];
    NSDictionary *product=@{@"id":plan[@"product"],@"folder":@"_forever_"};
    return TKWoWInspectInstallation((id)library,product,plan);
}
static TKWoWInstallationState PlayEligibility(NSString *root,NSDictionary *plan) {
    TKWoWInstallation *inspection=PlayInspection(root,plan);
    return inspection.state;
}
static NSData *PlistBytes(NSDictionary *plan) {
    return [NSPropertyListSerialization dataWithPropertyList:plan format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}
// A retried download must not move the launcher's startup contract: metadata,
// verification, activation and Play eligibility stay exactly what they were
// until the single activation of a completely downloaded build.
static void TestStartupContract(void) {
    NSData *first=Text(@"first installed code"),*second=Text(@"second installed code");
    NSData *firstRaw=Wrap(first),*secondRaw=Wrap(second),*third=Wrap(Text(@"third downloaded object"));
    NSMutableDictionary *responses=[NSMutableDictionary new];
    for(NSData *raw in @[firstRaw,secondRaw,third])responses[TKWoWMD5(raw)]=@{@"data":raw};
    NSMutableData *install=[Text(@"IN") mutableCopy];BE(install,1,1);BE(install,16,1);BE(install,0,2);BE(install,1,4);
    [install appendData:Text(@"Synthetic.app/Contents/MacOS/Synthetic")];BE(install,0,1);[install appendData:Hash(first)];BE(install,first.length,4);
    NSMutableData *encoding=[Text(@"EN") mutableCopy];BE(encoding,1,1);BE(encoding,16,1);BE(encoding,16,1);
    BE(encoding,1,2);BE(encoding,1,2);BE(encoding,1,4);BE(encoding,0,4);BE(encoding,0,1);BE(encoding,0,4);encoding.length+=32;
    BE(encoding,1,1);BE(encoding,first.length,5);[encoding appendData:Hash(first)];[encoding appendData:Hash(firstRaw)];
    encoding.length=22+32+1024;
    NSString *(^manifest)(NSString *,NSArray *)=^(NSString *version,NSArray *entries) {
        NSMutableData *download=[Text(@"DL") mutableCopy];BE(download,3,1);BE(download,16,1);BE(download,0,1);
        BE(download,entries.count,4);BE(download,0,2);BE(download,0,1);BE(download,0,4);
        for(NSData *entry in entries){[download appendData:Hash(entry)];BE(download,entry.length,5);BE(download,0,1);}
        NSString *configuration=[NSString stringWithFormat:@"build-uid = wowf\nroot = %@\n%@%@%@",TKWoWMD5(first),
            ReferenceResponses(@"install",install,responses),ReferenceResponses(@"encoding",encoding,responses),
            ReferenceResponses(@"download",download,responses)];
        NSString *build=TKWoWMD5(Text(version.length?[configuration stringByAppendingFormat:@"\nversion = %@",version]:configuration));
        responses[build]=@{@"data":Text([configuration stringByAppendingFormat:@"\nversion = %@",version])};
        return build;
    };
    NSMutableData *archive=[NSMutableData dataWithLength:37];
    [archive appendData:firstRaw];[archive appendData:secondRaw];[archive appendData:third];
    NSString *archiveKey=TKWoWMD5(archive);
    responses[archiveKey]=@{@"data":archive};
    NSMutableArray *indexed=[NSMutableArray new];
    for(NSData *raw in @[firstRaw,secondRaw,third])[indexed addObject:raw];
    responses[[archiveKey stringByAppendingString:@".index"]]=@{@"data":IndexObjects(indexed)};
    NSData *cdnData=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);NSString *cdn=TKWoWMD5(cdnData);
    responses[cdn]=@{@"data":cdnData};
    responses[@"cdns"]=@{@"data":Text(@"Name|Path|Hosts|Servers\neu|tpr/wow|level3.ssl.blizzard.com|https://level3.ssl.blizzard.com/?maxhosts=4&fallback=1\n")};
    NSString *(^publish)(NSString *,NSArray *)=^(NSString *version,NSArray *entries) {
        NSString *build=manifest(version,entries);
        responses[@"versions"]=@{@"data":Text([NSString stringWithFormat:
            @"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|%@\n",build,cdn,version])};
        return build;
    };
    NSError *error=nil;
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *root=[base stringByAppendingPathComponent:@"World of Warcraft"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *exe=[root stringByAppendingPathComponent:@"_forever_/Synthetic.app/Contents/MacOS/Synthetic"];
    assert([fm createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);
    NSData *old=Text(@"previous installed code");assert([old writeToFile:exe atomically:YES]);
    NSString *infoPath=[root stringByAppendingPathComponent:@".build.info"];
    NSData *oldInfo=Text(@"Product|Active|Build Key|CDN Key|Version|Tags\nwowf|1|11111111111111111111111111111111|22222222222222222222222222222222|previous|OSX arm64 EU enUS speech?:OSX arm64 EU enUS text?\n");
    assert([oldInfo writeToFile:infoPath atomically:YES]);
    RetryResponses=responses;
    TKRetryClient *client=[TKRetryClient new];client.responses=responses;
    TKVirtualClock *clock=[TKVirtualClock new];client.retryScheduler=clock;

    // v1 installs the executable. Nothing is retried yet.
    publish(@"synthetic-1",@[firstRaw]);
    NSDictionary *plan=[client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];
    if(!plan)fprintf(stderr,"Contract plan: %s\n",error.localizedDescription.UTF8String);
    assert(plan && !error);
    assert(PlayEligibility(root,plan)==TKWoWInstallationOutdated);
    NSData *planBytes=PlistBytes(plan);
    RetryLosses=0;RetryDropRange=nil;
    __block NSUInteger activations=0;__block BOOL sawDownload=NO;
    TKWoWUpdater *updater=[[TKWoWUpdater alloc] initWithClient:client];
    BOOL result=[updater updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)done;(void)total;
        if([phase isEqual:@"activate"])activations++;
        if([phase isEqual:@"download"]) {
            sawDownload=YES;
            assert([[NSData dataWithContentsOfFile:infoPath] isEqual:oldInfo]);
            assert([[NSData dataWithContentsOfFile:exe] isEqual:old]);
            assert(PlayEligibility(root,plan)==TKWoWInstallationOutdated);
        }
    } error:&error];
    if(!result)fprintf(stderr,"Contract v1: %s\n",error.localizedDescription.UTF8String);
    assert(result && sawDownload && activations==1);
    assert([[NSData dataWithContentsOfFile:exe] isEqual:first]);
    assert(PlayEligibility(root,plan)==TKWoWInstallationReady);
    assert([PlistBytes(plan) isEqual:planBytes]);
    assert(clock.delays.count==0);

    // v2 adds an object. Its range transfer drops once: the retry must not
    // re-verify, re-activate or change eligibility before the single activation.
    publish(@"synthetic-2",@[firstRaw,secondRaw]);
    NSDictionary *plan2=[client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];
    assert(plan2 && !error);
    assert(PlayEligibility(root,plan2)==TKWoWInstallationOutdated);
    NSData *plan2Bytes=PlistBytes(plan2);
    NSData *v1Info=[NSData dataWithContentsOfFile:infoPath],*v1Exe=[NSData dataWithContentsOfFile:exe];
    RetryLosses=1;
    RetryDropRange=[NSString stringWithFormat:@"bytes=%lu-%lu",(unsigned long)(37+firstRaw.length),
        (unsigned long)(37+firstRaw.length+secondRaw.length-1)];
    activations=0;sawDownload=NO;
    TKWoWUpdater *updater2=[[TKWoWUpdater alloc] initWithClient:client];
    result=[updater2 updatePlan:plan2 root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)done;(void)total;
        if([phase isEqual:@"activate"])activations++;
        if([phase isEqual:@"download"]) {
            sawDownload=YES;
            assert([[NSData dataWithContentsOfFile:infoPath] isEqual:v1Info]);
            assert([[NSData dataWithContentsOfFile:exe] isEqual:v1Exe]);
            assert(PlayEligibility(root,plan2)==TKWoWInstallationOutdated);
        }
    } error:&error];
    if(!result)fprintf(stderr,"Contract v2: %s\n",error.localizedDescription.UTF8String);
    assert(result && sawDownload && activations==1);
    // The retry happened, exactly once, and it re-read no verified payload.
    assert(RetryLosses==0 && [clock.delays isEqual:@[@1]]);
    assert(updater2.verificationBytesRead==0 && updater2.verificationBytesReused>=firstRaw.length);
    assert([[NSData dataWithContentsOfFile:exe] isEqual:first]);
    assert(PlayEligibility(root,plan2)==TKWoWInstallationReady);
    assert([PlistBytes(plan2) isEqual:plan2Bytes]);

    // Exhausted retries change nothing either: the installed root, its metadata
    // and Play eligibility are exactly the previously activated build.
    publish(@"synthetic-3",@[firstRaw,secondRaw,third]);
    NSDictionary *plan3=[client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];
    assert(plan3 && !error);
    NSData *v2Info=[NSData dataWithContentsOfFile:infoPath],*v2Exe=[NSData dataWithContentsOfFile:exe];
    RetryLosses=100;RetryDropRange=nil;[clock.delays removeAllObjects];
    TKWoWUpdater *updater3=[[TKWoWUpdater alloc] initWithClient:client];
    result=[updater3 updatePlan:plan3 root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)phase;(void)done;(void)total;
    } error:&error];
    assert(!result && error);
    assert(([clock.delays isEqual:@[@1,@2,@4,@8]]));
    assert([[NSData dataWithContentsOfFile:infoPath] isEqual:v2Info]);
    assert([[NSData dataWithContentsOfFile:exe] isEqual:v2Exe]);
    assert(PlayEligibility(root,plan3)==TKWoWInstallationOutdated);
    RetryLosses=0;RetryDropRange=nil;RetryResponses=nil;
    assert([fm removeItemAtPath:base error:&error]);
    puts("WoW startup contract PASS: a retried and an exhausted download leave metadata, verification, activation and Play eligibility unchanged, and activation happens once for the completed build.");
}

int main(void){@autoreleasepool{
    TestStorage();
    TestStartupContract();
    TKUpdateClient *client=[TKUpdateClient new];NSData *old=Text(@"old code"),*original=Text(@"our own new code"),*raw=Wrap(original);
    NSData *asset=Wrap(Text(@"new asset")),*present=Wrap(Text(@"existing asset"));
    client.responses[TKWoWMD5(asset)]=asset;client.responses[TKWoWMD5(present)]=present;
    NSMutableData *install=[Text(@"IN") mutableCopy];BE(install,1,1);BE(install,16,1);BE(install,0,2);BE(install,1,4);
    [install appendData:Text(@"Synthetic.app/Contents/MacOS/Synthetic")];BE(install,0,1);[install appendData:Hash(original)];BE(install,original.length,4);
    NSMutableData *encoding=[Text(@"EN") mutableCopy];BE(encoding,1,1);BE(encoding,16,1);BE(encoding,16,1);BE(encoding,1,2);BE(encoding,1,2);BE(encoding,1,4);BE(encoding,0,4);BE(encoding,0,1);BE(encoding,0,4);encoding.length+=32;
    BE(encoding,1,1);BE(encoding,original.length,5);[encoding appendData:Hash(original)];[encoding appendData:Hash(raw)];encoding.length=22+32+1024;
    NSMutableData *download=[Text(@"DL") mutableCopy];BE(download,3,1);BE(download,16,1);BE(download,0,1);BE(download,2,4);BE(download,0,2);BE(download,0,1);BE(download,0,4);
    for(NSData *entry in @[asset,present]){[download appendData:Hash(entry)];BE(download,entry.length,5);BE(download,0,1);}
    NSString *configuration=[NSString stringWithFormat:@"build-uid = wowf\nroot = %@\n%@%@%@",TKWoWMD5(original),Reference(@"install",install,client),Reference(@"encoding",encoding,client),Reference(@"download",download,client)];
    NSString *build=TKWoWMD5(Text(configuration));client.responses[build]=Text(configuration);
    NSMutableData *archive=[NSMutableData dataWithLength:37];[archive appendData:raw];client.archive=archive;NSString *archiveKey=TKWoWMD5(archive);
    client.responses[[archiveKey stringByAppendingString:@".index"]]=Index(raw);
    NSData *cdnData=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);NSString *cdn=TKWoWMD5(cdnData);client.responses[cdn]=cdnData;
    client.responses[@"versions"]=Text([NSString stringWithFormat:@"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|synthetic-2\n",build,cdn]);
    client.responses[@"cdns"]=Text(@"Name|Path|Hosts|Servers\neu|tpr/wow|level3.blizzard.com level3.ssl.blizzard.com|http://level3.blizzard.com/?maxhosts=8 https://level3.ssl.blizzard.com/?maxhosts=4&fallback=1\n");
    NSError *error=nil;NSDictionary *plan=[client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];assert(plan);
    assert([plan[@"cdnHosts"] isEqual:@"level3.blizzard.com level3.ssl.blizzard.com"]);
    assert([plan[@"cdnServers"] containsString:@"http://level3.blizzard.com/?maxhosts=8"]);
    NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString],*root=[base stringByAppendingPathComponent:@"World of Warcraft"];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *exe=[root stringByAppendingPathComponent:@"_forever_/Synthetic.app/Contents/MacOS/Synthetic"];
    assert([fm createDirectoryAtPath:exe.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);assert([old writeToFile:exe atomically:YES]);
    NSString *settings=[root stringByAppendingPathComponent:@"_forever_/WTF/Config.wtf"],*addon=[root stringByAppendingPathComponent:@"_forever_/Interface/AddOns/OurFixture.txt"];
    for(NSString *path in @[settings,addon]){assert([fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);assert([Text(@"keep me") writeToFile:path atomically:YES]);}
    NSData *info=Text(@"Product|Active|Build Key|CDN Key|Version\nwowf|1|11111111111111111111111111111111|22222222222222222222222222222222|synthetic-1\n");
    assert([info writeToFile:[root stringByAppendingPathComponent:@".build.info"] atomically:YES]);
    // A current install from an older launcher is repaired in place: no clone,
    // download, or game-file write is required before it can safely launch.
    assert([[[TKWoWUpdater alloc] initWithClient:client] repairBuildInfoForPlan:plan root:root error:&error]);
    info=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".build.info"]];
    NSString *repaired=[[NSString alloc] initWithData:info encoding:NSUTF8StringEncoding];
    assert([repaired containsString:@"CDN Hosts!STRING:0|CDN Servers!STRING:0"]);
    assert([repaired containsString:plan[@"cdnServers"]]);
    TKWoWCASCStore *source=[[TKWoWCASCStore alloc] initWithDirectory:[root stringByAppendingPathComponent:@"Data/data"] error:&error];assert(source);
    assert([source addData:present key:TKWoWMD5(present) error:&error]);assert([source checkpoint:&error]);source=nil;
    __block BOOL paused=NO, savedDuringScan=NO;
    BOOL result=[[[TKCheckpointUpdater alloc] initWithClient:client] updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        if([phase isEqual:@"verify"] && done==total) {
            // Reopen before the updater's normal end/cancellation cleanup. A
            // killed process could resume from this already durable receipt.
            NSString *data=[base stringByAppendingPathComponent:[NSString stringWithFormat:
                @".tolkara-updates/wowf-%@-enUS/installation/Data/data",build]];
            TKWoWCASCStore *reopened=[[TKWoWCASCStore alloc] initWithDirectory:data error:NULL];
            assert(reopened && [reopened verifyKey:TKWoWMD5(present) size:present.length]);
            assert(reopened.verificationBytesRead==0);savedDuringScan=YES;
        }
        if([phase isEqual:@"download"]){paused=YES;[client cancel];}
    } error:&error];
    if(!paused)fprintf(stderr,"Cancel fixture failed before download: %s\n",error.localizedDescription.UTF8String);
    assert(!result && paused && savedDuringScan);assert([[NSData dataWithContentsOfFile:exe] isEqual:old]);assert([[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".build.info"]] isEqual:info]);
    assert([Text(@"settings edited while paused") writeToFile:settings atomically:YES]);
    TKUpdateClient *resume=[TKUpdateClient new];resume.responses=client.responses;resume.archive=archive;
    __block BOOL changedMetadata=NO;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)done;(void)total;
        if([phase isEqual:@"download"] && !changedMetadata) {
            // The resumed job has already reused the downloaded asset's receipt.
            // Changing metadata must recheck it, not restart or lose the patch.
            NSString *segment=[base stringByAppendingPathComponent:[NSString stringWithFormat:
                @".tolkara-updates/wowf-%@-enUS/installation/Data/data/data.001",build]];
            assert([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSinceNow:10]}
                ofItemAtPath:segment error:NULL]);changedMetadata=YES;
        }
    } error:&error];
    if(!result)fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);assert(result);
    assert(changedMetadata);
    assert([[NSData dataWithContentsOfFile:exe] isEqual:original]);assert([[NSData dataWithContentsOfFile:addon] isEqual:Text(@"keep me")]);assert([[NSData dataWithContentsOfFile:settings] isEqual:Text(@"settings edited while paused")]);
    assert(!resume.counts[TKWoWMD5(asset)] && !resume.counts[TKWoWMD5(present)]);assert([resume.counts[@"range"] unsignedIntegerValue]==1);
    NSArray *rows=TKWoWTable([NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@".build.info"]],&error);assert(TKWoWBuildCurrent(rows,@"wowf",plan[@"version"]));
    source=[[TKWoWCASCStore alloc] initWithDirectory:[root stringByAppendingPathComponent:@"Data/data"] error:&error];assert(source);assert([[source readKey:TKWoWMD5(asset) size:asset.length] isEqual:asset]);assert([[source readKey:TKWoWMD5(present) size:present.length] isEqual:present]);source=nil;
    // A new transaction clones the prior receipts and reads no unchanged CASC
    // payload, while still validating metadata and the original loose file.
    TKWoWUpdater *warm=[[TKWoWUpdater alloc] initWithClient:resume];
    __block BOOL reused=NO;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){
        (void)done;(void)total;if([phase isEqual:@"reuse"])reused=YES;
    } error:&error];
    if(!result)fprintf(stderr,"Warm update: %s\n",error.localizedDescription.UTF8String);assert(result && reused);
    assert(warm.verificationBytesRead==0 && warm.verificationBytesReused>=asset.length+present.length);
    warm.fullVerification=YES;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(result && warm.verificationBytesRead>0 && warm.verificationBytesReused==0);
    // A published patch adds one object: unchanged payload is not reread and
    // exactly that new object is fetched, across another atomic clone/swap.
    NSData *patchAsset=Wrap(Text(@"our next patch asset"));resume.responses[TKWoWMD5(patchAsset)]=patchAsset;
    NSMutableData *nextDownload=[download mutableCopy];((uint8_t *)nextDownload.mutableBytes)[8]=3;
    [nextDownload appendData:Hash(patchAsset)];BE(nextDownload,patchAsset.length,5);BE(nextDownload,0,1);
    NSString *nextConfiguration=[configuration stringByReplacingOccurrencesOfString:Reference(@"download",download,resume)
        withString:Reference(@"download",nextDownload,resume)];
    NSString *nextBuild=TKWoWMD5(Text(nextConfiguration));resume.responses[nextBuild]=Text(nextConfiguration);
    resume.responses[@"versions"]=Text([NSString stringWithFormat:@"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|synthetic-3\n",nextBuild,cdn]);
    plan=[resume planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];assert(plan);
    warm.fullVerification=NO;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"Incremental patch: %s\n",error.localizedDescription.UTF8String);assert(result);
    assert(warm.verificationBytesRead==0 && warm.verificationBytesReused>=asset.length+present.length);
    assert([resume.counts[TKWoWMD5(patchAsset)] unsignedIntegerValue]==1);
    // An external edit to an existing segment is caught on the next update;
    // only the broken object is downloaded again and user folders survive.
    NSString *dataDirectory=[root stringByAppendingPathComponent:@"Data/data"];
    NSDictionary *receipt=TKWoWCASCVerificationSnapshot(dataDirectory);assert(receipt);
    BOOL damaged=NO;uint8_t assetKey[16];assert(TKWoWUnhex(TKWoWMD5(asset),assetKey));
    for(NSData *bucket in receipt[@"buckets"]) {
        const uint8_t *p=bucket.bytes;
        for(NSUInteger i=0;i<bucket.length;i+=25)if(!memcmp(p+i,assetKey,16)) {
            uint64_t location=0;for(unsigned j=0;j<5;j++)location=(location<<8)|p[i+16+j];
            NSString *path=[dataDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"data.%03llu",location>>30]];
            NSFileHandle *file=[NSFileHandle fileHandleForUpdatingAtPath:path];assert(file);
            [file seekToFileOffset:(location&0x3fffffff)+30+asset.length-1];[file writeData:Text(@"!")];[file closeFile];damaged=YES;
        }
    }
    assert(damaged);NSUInteger oldDownloads=[resume.counts[TKWoWMD5(asset)] unsignedIntegerValue];
    warm.fullVerification=NO;
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"Changed segment: %s\n",error.localizedDescription.UTF8String);assert(result);
    assert([resume.counts[TKWoWMD5(asset)] unsignedIntegerValue]==oldDownloads+1);
    assert([[NSData dataWithContentsOfFile:addon] isEqual:Text(@"keep me")]);
    // The receipt is optional: loss/corruption must produce full verification.
    assert([Text(@"broken receipt") writeToFile:[dataDirectory stringByAppendingPathComponent:@".wolkaraforever-verified"] atomically:YES]);
    result=[warm updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(result && warm.verificationBytesRead>0 && warm.verificationBytesReused==0);
    // A newly published build before activation leaves the previous root intact.
    resume.changed=NO;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)done;(void)total;if([phase isEqual:@"files"])resume.changed=YES;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"newer build"]);assert([[NSData dataWithContentsOfFile:exe] isEqual:original]);
    // Adjacent archive objects use one request; corrupt bytes never reach storage.
    TKUpdateClient *batch=[TKUpdateClient new];batch.archive=[NSMutableData dataWithLength:37];
    [(NSMutableData *)batch.archive appendData:asset];[(NSMutableData *)batch.archive appendData:present];
    NSString *batchArchive=TKWoWMD5(batch.archive);
    NSData *batchConfig=Text([NSString stringWithFormat:@"archives = %@\n",batchArchive]);
    batch.responses[TKWoWMD5(batchConfig)]=batchConfig;batch.responses[[batchArchive stringByAppendingString:@".index"]]=IndexObjects(@[asset,present]);
    NSMutableDictionary *batchPlan=[plan mutableCopy],*batchVersion=[plan[@"version"] mutableCopy];
    batchVersion[@"CDNConfig"]=TKWoWMD5(batchConfig);batchPlan[@"version"]=batchVersion;
    NSData *requests=TKWoWDownloads(download,@"enUS",@"eu",&error);__block NSUInteger consumed=0;
    NSString *indices=[base stringByAppendingPathComponent:@"batch-indices"];
    assert([batch downloadEntries:requests plan:batchPlan indices:indices consume:^BOOL(NSData *bytes,NSString *key,NSError **problem){
        (void)problem;assert(([@[asset,present] containsObject:bytes]));assert([TKWoWMD5(bytes) isEqual:key]);consumed++;return YES;
    } error:&error]);
    assert(consumed==2 && [batch.counts[@"range"] unsignedIntegerValue]==1);
    NSMutableData *broken=[batch.archive mutableCopy];((uint8_t *)broken.mutableBytes)[37+asset.length-1]^=1;batch.archive=broken;
    consumed=0;error=nil;
    assert(![batch downloadEntries:requests plan:batchPlan indices:indices consume:^BOOL(NSData *bytes,NSString *key,NSError **problem){
        (void)bytes;(void)key;(void)problem;consumed++;return YES;
    } error:&error]);
    assert(consumed==0 && [error.localizedDescription containsString:@"checksum"]);
    // Errors originating inside an autorelease pool remain valid to the caller.
    resume.changed=NO;
    NSMutableDictionary *protectedPlan=[plan mutableCopy];
    protectedPlan[@"files"]=@[@{@"path":@"WTF/Config.wtf",@"size":@1,@"contentKey":TKWoWMD5(Text(@"x"))}];
    error=nil;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:protectedPlan root:root progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"protected user data"]);
    assert([[NSData dataWithContentsOfFile:settings] isEqual:Text(@"settings edited while paused")]);
    // An escaping symlink must fail during cloning without reading its target.
    NSString *unsafeRoot=[base stringByAppendingPathComponent:@"unsafe"];
    assert([fm createDirectoryAtPath:unsafeRoot withIntermediateDirectories:YES attributes:nil error:&error]);
    assert([fm createSymbolicLinkAtPath:[unsafeRoot stringByAppendingPathComponent:@"escape"] withDestinationPath:@"/Applications" error:&error]);
    error=nil;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:unsafeRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"outside its installation"]);
    assert([fm fileExistsAtPath:[unsafeRoot stringByAppendingPathComponent:@"escape"]]);
    // Optional packs and other platforms are excluded, common data remains.
    NSMutableData *tagged=[download mutableCopy];((uint8_t *)tagged.mutableBytes)[10]=2;
    [tagged appendData:Text(@"HighRes")];BE(tagged,0,1);BE(tagged,0x4000,2);BE(tagged,0x80,1);
    [tagged appendData:Text(@"OSX")];BE(tagged,0,1);BE(tagged,1,2);BE(tagged,0x40,1);
    NSData *selection=TKWoWDownloads(tagged,@"enUS",@"eu",&error);assert(selection.length==sizeof(TKWoWDownloadEntry));
    const TKWoWDownloadEntry *picked=selection.bytes;assert([TKWoWHex(picked->key,16) isEqual:TKWoWMD5(present)]);
    // A fresh synthetic install activates all files and only initial locale/portal settings.
    NSString *freshRoot=[base stringByAppendingPathComponent:@"fresh-parent/World of Warcraft"];
    resume.changed=NO;error=nil;
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:freshRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    if(!result)fprintf(stderr,"Fresh install: %s\n",error.localizedDescription.UTF8String);assert(result);
    NSString *freshInfo=[NSString stringWithContentsOfFile:[freshRoot stringByAppendingPathComponent:@".build.info"] encoding:NSUTF8StringEncoding error:&error];
    assert([freshInfo containsString:@"CDN Hosts!STRING:0|CDN Servers!STRING:0"]);
    assert([freshInfo containsString:plan[@"cdnServers"]]);
    NSString *freshConfig=[NSString stringWithContentsOfFile:[freshRoot stringByAppendingPathComponent:@"_forever_/WTF/Config.wtf"] encoding:NSUTF8StringEncoding error:&error];
    // The released product writes the selected region as the portal. The `_beta`
    // product suffix is the old beta hook and is not what this fixture installs.
    assert([freshConfig containsString:@"SET portal \"EU\""] && [freshConfig containsString:@"SET textLocale \"enUS\""]);
    // Reject oversized local metadata before cloning or allocating its contents.
    NSData *oversized=[NSMutableData dataWithLength:2*1024*1024+1];
    assert([oversized writeToFile:[freshRoot stringByAppendingPathComponent:@".build.info"] atomically:YES]);
    result=[[[TKWoWUpdater alloc] initWithClient:resume] updatePlan:plan root:freshRoot progress:^(NSString *phase,uint64_t done,uint64_t total){(void)phase;(void)done;(void)total;} error:&error];
    assert(!result && [error.localizedDescription containsString:@"oversized"]);
    // Malformed binary data is rejected, including every truncation of our DL fixture.
    for(NSUInteger n=0;n<download.length;n++)assert(!TKWoWDownloads([download subdataWithRange:NSMakeRange(0,n)],@"enUS",@"eu",NULL));
    NSMutableData *bad=[asset mutableCopy];((uint8_t *)bad.mutableBytes)[bad.length-1]^=1;assert(!TKWoWEncodedValid(bad,TKWoWMD5(asset),NULL));
    bad=[Index(raw) mutableCopy];((uint8_t *)bad.mutableBytes)[bad.length-1]^=1;assert(!TKWoWArchiveEntries(bad,0,NULL));
    assert(TKWoWJenkins("",0,NULL,0)==0xdeadbeef);
    assert([fm removeItemAtPath:base error:&error]);
    puts("WoW updater PASS: unchanged data reuse, archive ranges, cancel before activation, durable resume, atomic activation, settings/addon preservation, superseded build and malformed input.");
}return 0;}
