// Protocol pipeline tests: replace the transport, never contact a real server.
#import <Foundation/Foundation.h>
#include <assert.h>
#import "../launcher/WoW/Client.h"
#import "../launcher/WoW/CASC.h"

@interface TKWoWClient (TestTransport)
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit error:(NSError **)error;
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size error:(NSError **)error;
- (NSURLSessionConfiguration *)sessionConfiguration;
@end
@interface TKFixtureClient : TKWoWClient
@property(nonatomic) NSMutableDictionary<NSString *,NSData *> *responses;
@property(nonatomic) NSUInteger calls;
@end
@implementation TKFixtureClient
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit error:(NSError **)error {
    self.calls++;
    assert([url.scheme isEqual:@"https"]);
    NSData *data=self.responses[url.lastPathComponent];
    if (!data || data.length>limit) { if (error) *error=TKWoWError(@"Synthetic transport failure."); return nil; }
    return data;
}
@end
static NSData *Text(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static void BE(NSMutableData *d, uint64_t n, NSUInteger size) {
    for (NSUInteger i=size;i>0;i--) { uint8_t byte=(uint8_t)(n>>((i-1)*8)); [d appendBytes:&byte length:1]; }
}
static NSData *Hash(NSData *data) {
    NSString *hex=TKWoWMD5(data); NSMutableData *bytes=[NSMutableData new];
    for (NSUInteger i=0;i<16;i++) BE(bytes,strtoul([[hex substringWithRange:NSMakeRange(i*2,2)] UTF8String],NULL,16),1);
    return bytes;
}
static NSData *Wrap(NSData *data) {
    NSMutableData *raw=[Text(@"BLTE") mutableCopy]; BE(raw,0,4); BE(raw,'N',1); [raw appendData:data]; return raw;
}
static NSString *Reference(NSString *name, NSData *data, TKFixtureClient *client) {
    NSData *raw=Wrap(data); client.responses[TKWoWMD5(raw)]=raw;
    return [NSString stringWithFormat:@"%@ = %@ %@\n%@-size = %lu %lu\n",name,TKWoWMD5(data),TKWoWMD5(raw),name,(unsigned long)data.length,(unsigned long)raw.length];
}
// Exercise the real NSURLSession delegate routing with synthetic HTTPS objects.
// No socket, credentials, application code or live CDN request is used.
static NSDictionary<NSString *,NSDictionary *> *ProtocolResponses;
static NSUInteger ActiveRequests,PeakRequests,StartedRequests,StoppedRequests;
static uint64_t ActiveBytes,PeakBytes;
static dispatch_semaphore_t FourStarted;
static dispatch_group_t ProtocolDeliveries;
@interface TKDownloadProtocol : NSURLProtocol
@property(nonatomic) BOOL finished;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) dispatch_semaphore_t deliveryGate;
@end
@implementation TKDownloadProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"fixture.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)finishCount:(BOOL)stopped {
    if(_finished)return;_finished=YES;
    @synchronized(TKDownloadProtocol.class) {
        ActiveRequests--;ActiveBytes-=_bytes;if(stopped)StoppedRequests++;
    }
}
- (void)startLoading {
    NSDictionary *reply=ProtocolResponses[self.request.URL.lastPathComponent]?:@{@"data":NSData.data,@"status":@404};
    NSData *body=reply[@"data"];NSString *range=[self.request valueForHTTPHeaderField:@"Range"];
    NSUInteger status=[reply[@"status"] unsignedIntegerValue]?:200;NSString *contentRange=nil;
    if(range) {
        unsigned long long first=0,last=0;
        assert(sscanf(range.UTF8String,"bytes=%llu-%llu",&first,&last)==2 && first<=last && last<body.length);
        if(reply[@"holdRange"] && [reply[@"holdRange"] unsignedLongLongValue]==first)_deliveryGate=dispatch_semaphore_create(0);
        contentRange=[NSString stringWithFormat:@"bytes %llu-%llu/%lu",first,last,(unsigned long)body.length];
        body=[body subdataWithRange:NSMakeRange((NSUInteger)first,(NSUInteger)(last-first+1))];status=206;
    }
    if(reply[@"contentRange"])contentRange=reply[@"contentRange"];
    if(reply[@"status"])status=[reply[@"status"] unsignedIntegerValue];
    if(reply[@"truncate"])body=[body subdataWithRange:NSMakeRange(0,body.length-1)];
    if(reply[@"corrupt"]) { NSMutableData *bad=[body mutableCopy];((uint8_t *)bad.mutableBytes)[bad.length-1]^=1;body=bad; }
    _bytes=body.length;
    @synchronized(TKDownloadProtocol.class) {
        ActiveRequests++;StartedRequests++;ActiveBytes+=_bytes;
        PeakRequests=MAX(PeakRequests,ActiveRequests);PeakBytes=MAX(PeakBytes,ActiveBytes);
        if(ActiveRequests==4 && FourStarted)dispatch_semaphore_signal(FourStarted);
    }
    NSMutableDictionary *headers=[@{@"Content-Length":[NSString stringWithFormat:@"%lu",(unsigned long)body.length]} mutableCopy];
    if(contentRange)headers[@"Content-Range"]=contentRange;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:(NSInteger)status HTTPVersion:@"HTTP/1.1" headerFields:headers];
    double delay=[reply[@"delay"] doubleValue];
    dispatch_group_enter(ProtocolDeliveries);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        if(self.deliveryGate)assert(!dispatch_semaphore_wait(self.deliveryGate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
        @try { @synchronized(self) {
            if(self.finished)return;
            [self finishCount:NO];
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            // Distinct response lengths/chunks arrive interleaved across tasks.
            NSUInteger half=body.length/2;
            [self.client URLProtocol:self didLoadData:[body subdataWithRange:NSMakeRange(0,half)]];
            [self.client URLProtocol:self didLoadData:[body subdataWithRange:NSMakeRange(half,body.length-half)]];
            [self.client URLProtocolDidFinishLoading:self];
        }} @finally { dispatch_group_leave(ProtocolDeliveries); }
    });
}
- (void)stopLoading { @synchronized(self) {
    [self finishCount:YES];if(_deliveryGate)dispatch_semaphore_signal(_deliveryGate);
} }
@end
@interface TKSessionClient : TKWoWClient
@end
@implementation TKSessionClient
- (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *configuration=[super sessionConfiguration];
    configuration.protocolClasses=@[TKDownloadProtocol.class];return configuration;
}
@end
static void ResetProtocol(NSDictionary *responses) {
    @synchronized(TKDownloadProtocol.class) {
        if(!ProtocolDeliveries)ProtocolDeliveries=dispatch_group_create();
        assert(!ActiveRequests);ProtocolResponses=responses;PeakRequests=StartedRequests=StoppedRequests=0;
        ActiveBytes=PeakBytes=0;FourStarted=nil;
    }
}
static NSData *ArchiveIndex(NSArray<NSData *> *objects,NSArray<NSNumber *> *offsets) {
    NSMutableData *data=[NSMutableData new];
    for(NSUInteger i=0;i<objects.count;i++) {
        [data appendData:Hash(objects[i])];BE(data,objects[i].length,4);BE(data,offsets[i].unsignedIntegerValue,4);
    }
    data.length=4096;[data appendData:Hash(objects.lastObject)];[data appendData:Hash(data)];
    uint8_t footer[20]={1,0,0,4,4,4,16,8};footer[8]=(uint8_t)objects.count;
    NSData *hash=Hash([NSData dataWithBytes:footer length:20]);memcpy(footer+12,hash.bytes,8);
    [data appendBytes:footer length:20];return data;
}
// Hold the first range until every other object has reached the serial
// consumer. This detects batch barriers without relying on benchmark timing.
@interface TKDelayedRangeClient : TKFixtureClient
@property(nonatomic) dispatch_semaphore_t releaseFirst;
@end
@implementation TKDelayedRangeClient
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size error:(NSError **)error {
    if(offset==37 && dispatch_semaphore_wait(_releaseFirst,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) {
        if(error)*error=TKWoWError(@"Other ranges stalled behind the first range");return nil;
    }
    NSData *archive=self.responses[url.lastPathComponent];
    assert(offset<=archive.length && size<=archive.length-offset);
    return [archive subdataWithRange:NSMakeRange((NSUInteger)offset,size)];
}
@end
static void TestReadyRanges(void) {
    TKDelayedRangeClient *client=[TKDelayedRangeClient new];client.responses=[NSMutableDictionary new];
    client.releaseFirst=dispatch_semaphore_create(0);
    NSMutableArray *objects=[NSMutableArray new],*offsets=[NSMutableArray new];
    NSMutableData *archive=[NSMutableData dataWithLength:37],*records=[NSMutableData new];
    for(NSUInteger i=0;i<8;i++) {
        NSData *raw=Wrap(Text([NSString stringWithFormat:@"Synthetic rolling range %lu",(unsigned long)i]));
        [objects addObject:raw];[offsets addObject:@(archive.length)];[archive appendData:raw];archive.length+=65537;
        TKWoWDownloadEntry entry={0};assert(TKWoWUnhex(TKWoWMD5(raw),entry.key));entry.size=raw.length;
        [records appendBytes:&entry length:sizeof(entry)];
    }
    NSString *archiveKey=TKWoWMD5(archive);client.responses[archiveKey]=archive;
    client.responses[[archiveKey stringByAppendingString:@".index"]]=ArchiveIndex(objects,offsets);
    NSData *config=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);client.responses[TKWoWMD5(config)]=config;
    NSDictionary *plan=@{@"cdn":@"https://fixture.invalid/tpr/wow",@"version":@{@"CDNConfig":TKWoWMD5(config)}};
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
    NSMutableSet *seen=[NSMutableSet new];NSThread *caller=NSThread.currentThread;
    assert([client downloadEntries:records plan:plan indices:directory consume:^BOOL(NSData *data,NSString *key,NSError **problem) {
        (void)problem;assert(NSThread.currentThread==caller && [objects containsObject:data] && ![seen containsObject:key]);
        if([data isEqual:objects[0]])assert(seen.count==objects.count-1);
        [seen addObject:key];
        if(seen.count==objects.count-1)dispatch_semaphore_signal(client.releaseFirst);
        return YES;
    } error:&error]);
    assert(!error && seen.count==objects.count);
    assert([NSFileManager.defaultManager removeItemAtPath:directory error:NULL]);
    puts("Rolling downloader: seven verified ranges consumed while the first remained blocked.");
}
// Advertise large objects without allocating them: the transport stops once the
// admitted window is visible. This checks the memory budget before any payload.
@interface TKBudgetClient : TKFixtureClient
@property(nonatomic) NSUInteger expected;
@property(nonatomic) NSUInteger active;
@property(nonatomic) NSUInteger peak;
@property(nonatomic) NSUInteger rangeCalls;
@property(nonatomic) uint64_t bytes;
@property(nonatomic) uint64_t peakBytes;
@property(nonatomic) dispatch_semaphore_t gate;
@end
@implementation TKBudgetClient
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size error:(NSError **)error {
    (void)url;assert(offset==37);
    @synchronized(self) {
        _active++;_rangeCalls++;_bytes+=size;_peak=MAX(_peak,_active);_peakBytes=MAX(_peakBytes,_bytes);
        if(_active==_expected)for(NSUInteger i=0;i<_expected;i++)dispatch_semaphore_signal(_gate);
    }
    assert(!dispatch_semaphore_wait(_gate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
    @synchronized(self) { _active--;_bytes-=size; }
    if(error)*error=TKWoWError(@"Synthetic bounded-window stop");return nil;
}
@end
static void TestTransferBudget(void) {
    for(NSNumber *size in @[@(17*1024*1024),@(65*1024*1024)]) {
        @autoreleasepool {
            TKBudgetClient *client=[TKBudgetClient new];client.responses=[NSMutableDictionary new];
            client.expected=size.unsignedIntegerValue>64*1024*1024?1:3;client.gate=dispatch_semaphore_create(0);
            NSData *key=Hash(Text(@"synthetic large object"));NSMutableData *index=[NSMutableData new];
            [index appendData:key];BE(index,size.unsignedIntegerValue,4);BE(index,37,4);index.length=4096;
            [index appendData:key];[index appendData:Hash(index)];uint8_t footer[20]={1,0,0,4,4,4,16,8,1};
            memcpy(footer+12,Hash([NSData dataWithBytes:footer length:20]).bytes,8);[index appendBytes:footer length:20];
            NSString *archive=TKWoWMD5(Text(@"synthetic archive"));
            client.responses[[archive stringByAppendingString:@".index"]]=index;
            NSData *config=Text([NSString stringWithFormat:@"archives = %@\n",archive]);client.responses[TKWoWMD5(config)]=config;
            NSDictionary *plan=@{@"cdn":@"https://fixture.invalid/tpr/wow",@"version":@{@"CDNConfig":TKWoWMD5(config)}};
            NSMutableData *records=[NSMutableData new];TKWoWDownloadEntry entry={0};memcpy(entry.key,key.bytes,16);entry.size=size.unsignedLongLongValue;
            // Separate jobs are required above the 16 MiB grouped-range limit.
            for(NSUInteger i=0;i<4;i++)[records appendBytes:&entry length:sizeof(entry)];
            NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
            assert(![client downloadEntries:records plan:plan indices:directory consume:^BOOL(NSData *data,NSString *hash,NSError **problem){
                (void)data;(void)hash;(void)problem;assert(!"No synthetic payload should be consumed");return NO;
            } error:&error]);
            assert([error.localizedDescription containsString:@"bounded-window"] && client.peak==client.expected);
            assert(client.rangeCalls==client.expected && client.peakBytes==size.unsignedLongLongValue*client.expected);
            assert([NSFileManager.defaultManager removeItemAtPath:directory error:NULL]);
        }
    }
}
static void TestConcurrentDownloads(void) {
    NSMutableArray *objects=[NSMutableArray new],*offsets=[NSMutableArray new];
    NSMutableData *archive=[NSMutableData dataWithLength:37],*records=[NSMutableData new];
    for(NSUInteger i=0;i<12;i++) {
        NSMutableData *body=[NSMutableData dataWithLength:1024+i*127];memset(body.mutableBytes,(int)i+1,body.length);
        NSData *raw=Wrap(body);[objects addObject:raw];[offsets addObject:@(archive.length)];[archive appendData:raw];
        archive.length+=65537; // Deliberately exceed the archive grouping gap.
    }
    NSMutableDictionary *responses=[NSMutableDictionary new];
    NSString *archiveKey=TKWoWMD5(archive);
    responses[archiveKey]=@{@"data":archive,@"delay":@0.08};
    responses[[archiveKey stringByAppendingString:@".index"]]=@{@"data":ArchiveIndex(objects,offsets)};
    NSData *config=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);
    responses[TKWoWMD5(config)]=@{@"data":config};
    for(NSUInteger i=0;i<2;i++) {
        NSData *raw=Wrap(Text([NSString stringWithFormat:@"Synthetic standalone %lu",(unsigned long)i]));
        [objects addObject:raw];responses[TKWoWMD5(raw)]=@{@"data":raw,@"delay":@0.08};
    }
    for(NSData *raw in objects) {
        TKWoWDownloadEntry entry={0};assert(TKWoWUnhex(TKWoWMD5(raw),entry.key));entry.size=raw.length;
        [records appendBytes:&entry length:sizeof(entry)];
    }
    NSDictionary *plan=@{@"cdn":@"https://fixture.invalid/tpr/wow",@"version":@{@"CDNConfig":TKWoWMD5(config)}};
    NSString *indices=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *error=nil;
    ResetProtocol(responses);TKSessionClient *client=[TKSessionClient new];
    // Prime the archive catalogue, outside both benchmark intervals.
    assert([client encodedKey:TKWoWMD5(objects[0]) size:[objects[0] length] plan:plan indices:indices error:&error]);
    ResetProtocol(responses);double start=NSDate.timeIntervalSinceReferenceDate;
    for(NSData *raw in objects)assert([[client encodedKey:TKWoWMD5(raw) size:raw.length plan:plan indices:indices error:&error] isEqual:raw]);
    double serial=NSDate.timeIntervalSinceReferenceDate-start;assert(PeakRequests==1);
    ResetProtocol(responses);start=NSDate.timeIntervalSinceReferenceDate;
    NSMutableSet *seen=[NSMutableSet new];NSThread *caller=NSThread.currentThread;
    BOOL result=[client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem) {
        (void)problem;assert(NSThread.currentThread==caller && [objects containsObject:data]);
        assert([TKWoWMD5(data) isEqual:key] && ![seen containsObject:key]);[seen addObject:key];return YES;
    } error:&error];
    double parallel=NSDate.timeIntervalSinceReferenceDate-start;
    if(!result)fprintf(stderr,"Concurrent fixture: %s\n",error.localizedDescription.UTF8String);
    assert(result && seen.count==objects.count && PeakRequests==4 && PeakBytes<=64*1024*1024 && !ActiveRequests);
    // Timing is diagnostic, never a load-dependent test pass condition.
    printf("Synthetic downloader: 14 latency-bound requests, serial %.3fs, four-way %.3fs (%.2fx); no live CDN.\n",serial,parallel,serial/parallel);
    // A transport error cancels siblings and the next window is not scheduled.
    NSMutableDictionary *faulty=[responses mutableCopy];
    faulty[archiveKey]=@{@"data":archive,@"delay":@0.01,@"contentRange":@"bytes 0-0/1"};
    ResetProtocol(faulty);[seen removeAllObjects];error=nil;
    assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)data;(void)key;(void)problem;[seen addObject:key];return YES;
    } error:&error]);
    assert(error && !seen.count && StartedRequests<=4 && !ActiveRequests);
    // Error state is scoped to this operation. A verified retry still works.
    ResetProtocol(responses);error=nil;
    assert([client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)problem;assert([TKWoWMD5(data) isEqual:key]);return YES;
    } error:&error]);assert(!error);
    // Checksum corruption, a short range and a failing serial consumer stop safely.
    for(NSString *kind in @[@"corrupt",@"truncate"]) {
        faulty=[responses mutableCopy];faulty[archiveKey]=@{@"data":archive,@"delay":@0.01,kind:@YES};
        ResetProtocol(faulty);__block NSUInteger consumed=0;error=nil;
        assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
            (void)data;(void)key;(void)problem;consumed++;return YES;
        } error:&error]);assert(error && !consumed && !ActiveRequests);
    }
    ResetProtocol(responses);__block NSUInteger consumed=0;error=nil;
    assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)data;(void)key;consumed++;*problem=TKWoWError(@"Synthetic full disk");return NO;
    } error:&error]);assert(consumed==1 && [error.localizedDescription containsString:@"full disk"] && StartedRequests<=4);
    assert(!dispatch_group_wait(ProtocolDeliveries,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
    assert(!ActiveRequests);
    // A consumer can now fail before a slow sibling finishes. Cancel and drain
    // that live task, including when the consumer supplies no NSError.
    for(NSNumber *provideError in @[@YES,@NO]) {
        faulty=[responses mutableCopy];
        faulty[archiveKey]=@{@"data":archive,@"delay":@0.02,@"holdRange":offsets[0]};
        ResetProtocol(faulty);consumed=0;error=nil;
        assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
            (void)data;(void)key;consumed++;
            if(provideError.boolValue)*problem=TKWoWError(@"Synthetic consumer error with live sibling");
            return NO;
        } error:&error]);
        assert(consumed==1 && error && StartedRequests<=4);
        assert([error.localizedDescription containsString:provideError.boolValue?@"live sibling":@"Cannot store"]);
        assert(!dispatch_group_wait(ProtocolDeliveries,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
        assert(!ActiveRequests && StoppedRequests>=1);
    }
    // User cancellation while all four requests are active must unblock them.
    faulty=[responses mutableCopy];faulty[archiveKey]=@{@"data":archive,@"delay":@5};
    ResetProtocol(faulty);FourStarted=dispatch_semaphore_create(0);dispatch_semaphore_t cancelled=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        assert(!dispatch_semaphore_wait(FourStarted,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
        [client cancel];dispatch_semaphore_signal(cancelled);
    });
    error=nil;consumed=0;
    assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)data;(void)key;(void)problem;consumed++;return YES;
    } error:&error]);
    assert(!dispatch_semaphore_wait(cancelled,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
    assert(client.cancelled && error && !consumed && StartedRequests==4);
    // NSURLProtocol cleanup may lag NSURLSession's cancellation completion. Let
    // delayed synthetic deliveries drain; none may reach the cancelled consumer.
    assert(!dispatch_group_wait(ProtocolDeliveries,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)));
    assert(!ActiveRequests);
    FourStarted=nil;
    assert([NSFileManager.defaultManager removeItemAtPath:indices error:NULL]);
}
int main(void) {
    @autoreleasepool {
        TKFixtureClient *client=[TKFixtureClient new]; client.responses=[NSMutableDictionary new];
        NSData *original=Text(@"test"), *raw=Wrap(original); client.responses[TKWoWMD5(raw)]=raw;
        NSMutableData *install=[Text(@"IN") mutableCopy]; BE(install,1,1); BE(install,16,1); BE(install,0,2); BE(install,1,4);
        [install appendData:Text(@"Test.app/Contents/MacOS/Test")]; BE(install,0,1); [install appendData:Hash(original)]; BE(install,original.length,4);
        NSMutableData *encoding=[Text(@"EN") mutableCopy]; BE(encoding,1,1); BE(encoding,16,1); BE(encoding,16,1);
        BE(encoding,1,2); BE(encoding,1,2); BE(encoding,1,4); BE(encoding,0,4); BE(encoding,0,1); BE(encoding,0,4);
        [encoding appendData:[NSMutableData dataWithLength:32]];
        BE(encoding,1,1); BE(encoding,original.length,5); [encoding appendData:Hash(original)]; [encoding appendData:Hash(raw)]; encoding.length=22+32+1024;
        NSString *config=[NSString stringWithFormat:@"build-uid = wowf\n%@%@",Reference(@"install",install,client),Reference(@"encoding",encoding,client)];
        NSString *build=TKWoWMD5(Text(config)), *cdn=TKWoWMD5(Text(@"cdn")); client.responses[build]=Text(config);
        NSString *versions=[NSString stringWithFormat:@"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|synthetic-1\n",build,cdn];
        client.responses[@"versions"]=Text(versions);
        client.responses[@"cdns"]=Text(@"Name|Path|Servers\neu|tpr/wow|https://level3.ssl.blizzard.com/?fallback=1\n");
        NSError *error=nil;
        NSDictionary *plan=[client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];
        assert(plan && !error && [plan[@"files"] count]==1 && ![plan[@"complete"] boolValue]);
        assert([plan[@"cdnServers"] isEqual:@"https://level3.ssl.blizzard.com/?fallback=1"]);
        assert([plan[@"cdnHosts"] isEqual:@"level3.ssl.blizzard.com"]);
        NSDictionary *file=plan[@"files"][0];
        NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *path=[client stageFile:file plan:plan directory:directory error:&error];
        assert(path && !error && [[NSData dataWithContentsOfFile:path] isEqual:original]);
        // Reuse only a checksum-verified encoding cache. A damaged one is refetched.
        NSString *cache=[directory stringByAppendingPathComponent:[TKWoWMD5(encoding) stringByAppendingString:@".encoding"]];
        [Text(@"bad") writeToFile:cache atomically:YES];
        assert([client stageFile:file plan:plan directory:directory error:&error]);
        assert([[NSData dataWithContentsOfFile:cache] isEqual:encoding]);
        // A published patch invalidates the staged plan before any payload request.
        client.responses[@"versions"]=Text([versions stringByReplacingOccurrencesOfString:build withString:TKWoWMD5(Text(@"new build"))]);
        NSUInteger calls=client.calls;
        assert(![client stageFile:file plan:plan directory:directory error:&error]);
        assert(client.calls==calls+1 && [error.localizedDescription containsString:@"newer build"]);
        assert([[NSData dataWithContentsOfFile:path] isEqual:original]);
        // Corrupt configuration, duplicate region and transport failures stop the plan.
        client.responses[@"versions"]=Text(versions); client.responses[build]=Text(@"corrupt");
        assert(![client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error]);
        assert([error.localizedDescription containsString:@"checksum"]);
        client.responses[build]=Text(config);
        client.responses[@"versions"]=Text([versions stringByAppendingString:[[versions componentsSeparatedByString:@"\n"][1] stringByAppendingString:@"\n"]]);
        assert(![client versionForProduct:@"wowf" region:@"eu" error:&error]);
        assert([error.localizedDescription containsString:@"Ambiguous"]);
        [client.responses removeObjectForKey:@"versions"];
        assert(![client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error]);
        assert([error.localizedDescription containsString:@"transport"]);
        client.responses[@"versions"]=Text(versions);
        client.responses[@"cdns"]=Text(@"Name|Path|Servers\neu|tpr/wow|http://level3.blizzard.com/\n");
        assert(![client planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error]);
        assert([error.localizedDescription containsString:@"HTTPS"]);
        assert([NSFileManager.defaultManager removeItemAtPath:directory error:&error]);
    }
    TestTransferBudget();
    TestReadyRanges();
    TestConcurrentDownloads();
    puts("WoW client tests PASS: bounded concurrent transfers, serial consumption, range validation, cancellation, verified staging, cache repair, patch invalidation, malformed metadata and failed transport.");
    return 0;
}
