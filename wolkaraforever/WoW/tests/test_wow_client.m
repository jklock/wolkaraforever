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
- (NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit window:(uint64_t)window error:(NSError **)error {
    (void)window;return [self fetch:url limit:limit error:error];
}
@end
// Delays are virtual: the downloader asks this clock for a deadline instead of
// sleeping, so every retry assertion below is exact rather than timing based.
@interface TKFakeRetryScheduler : TKWoWRetryScheduler
@property(nonatomic) NSTimeInterval now;
@property(nonatomic) NSMutableArray<NSNumber *> *delays;
@property(nonatomic) NSTimeInterval lastDeadline;
@property(nonatomic, copy) void (^duringWait)(void);
// Hold the wait until the client itself signals it, proving cancellation and a
// terminal sibling failure wake a request that is already waiting.
@property(nonatomic) BOOL hold;
@property(nonatomic) BOOL signalled;
@property(nonatomic) dispatch_semaphore_t entered;
@end
@implementation TKFakeRetryScheduler
- (instancetype)init {
    if((self=[super init])){_now=1000;_delays=[NSMutableArray new];_lastDeadline=NAN;}
    return self;
}
- (NSTimeInterval)monotonicNow { return _now; }
- (BOOL)waitUntil:(NSTimeInterval)deadline lock:(NSCondition *)lock {
    // An unrelated broadcast re-enters the wait with the same deadline; the
    // schedule records each delay once, not once per wake-up.
    if (!(deadline==self.lastDeadline)) { [self.delays addObject:@(deadline-self.now)];self.lastDeadline=deadline; }
    if (self.duringWait) self.duringWait();
    self.now=deadline;
    if (!self.hold) return YES;
    if (self.entered) dispatch_semaphore_signal(self.entered);
    // A test barrier, not a simulated delay: the only early exit is the client's
    // own condition being signalled. The cap only stops a hung test.
    self.signalled=[lock waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:10]];
    return NO;
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
static NSString *ReferenceResponses(NSString *name,NSData *data,NSMutableDictionary *responses) {
    NSData *raw=Wrap(data);
    responses[TKWoWMD5(raw)]=raw;
    return [NSString stringWithFormat:@"%@ = %@ %@\n%@-size = %lu %lu\n",name,TKWoWMD5(data),TKWoWMD5(raw),name,(unsigned long)data.length,(unsigned long)raw.length];
}
static NSString *Reference(NSString *name, NSData *data, TKFixtureClient *client) {
    return ReferenceResponses(name,data,client.responses);
}
// Exercise the real NSURLSession delegate routing with synthetic HTTPS objects.
// No socket, credentials, application code or live CDN request is used.
static NSDictionary<NSString *,NSDictionary *> *ProtocolResponses;
static NSUInteger ActiveRequests,PeakRequests,StartedRequests,StoppedRequests;
static NSUInteger InjectedConnectionLosses;
static uint64_t ActiveBytes,PeakBytes;
static dispatch_semaphore_t FourStarted;
static dispatch_semaphore_t FiveStarted;
static dispatch_semaphore_t StartedReached;
static NSUInteger StartedTarget;
static dispatch_group_t ProtocolDeliveries;
@interface TKDownloadProtocol : NSURLProtocol
@property(nonatomic) BOOL finished;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) dispatch_semaphore_t deliveryGate;
@end
@implementation TKDownloadProtocol
// Claim the version service and every advertised CDN host too, so no suite in
// this binary can reach the network even with a synthetic server list.
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *host=request.URL.host.lowercaseString;
    return [host isEqual:@"fixture.invalid"] || [host hasSuffix:@".battle.net"] || [host hasSuffix:@".blizzard.com"];
}
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
    BOOL dropConnection=NO;
    @synchronized(TKDownloadProtocol.class) {
        if (InjectedConnectionLosses<[reply[@"connectionLosses"] unsignedIntegerValue] &&
            (!reply[@"dropRange"] || [range isEqual:reply[@"dropRange"]])) {
            InjectedConnectionLosses++;
            dropConnection=YES;
        }
        ActiveRequests++;StartedRequests++;ActiveBytes+=_bytes;
        PeakRequests=MAX(PeakRequests,ActiveRequests);PeakBytes=MAX(PeakBytes,ActiveBytes);
        if(ActiveRequests==4 && FourStarted)dispatch_semaphore_signal(FourStarted);
        if(StartedRequests==5 && FiveStarted)dispatch_semaphore_signal(FiveStarted);
        if(StartedTarget && StartedRequests==StartedTarget && StartedReached)dispatch_semaphore_signal(StartedReached);
    }
    if(reply[@"holdAll"] && !dropConnection)_deliveryGate=dispatch_semaphore_create(0);
    if(reply[@"failWith"]) {
        NSDictionary *failure=reply[@"failWith"];
        dispatch_group_enter(ProtocolDeliveries);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)([reply[@"delay"] doubleValue]*NSEC_PER_SEC)),
            dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{\
            @synchronized(self) { @try {
                [self finishCount:NO];
                [self.client URLProtocol:self didFailWithError:
                    [NSError errorWithDomain:failure[@"domain"] code:[failure[@"code"] integerValue] userInfo:nil]];
            } @finally { dispatch_group_leave(ProtocolDeliveries); } }
        });
        return;
    }
    NSMutableDictionary *headers=[@{@"Content-Length":[NSString stringWithFormat:@"%lu",(unsigned long)body.length]} mutableCopy];
    if(contentRange)headers[@"Content-Range"]=contentRange;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:(NSInteger)status HTTPVersion:@"HTTP/1.1" headerFields:headers];
    double delay=[reply[@"delay"] doubleValue];
    if(reply[@"delays"] && range)delay=[reply[@"delays"][range] doubleValue];
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
            if (dropConnection) {
                NSError *loss=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil];
                [self.client URLProtocol:self didFailWithError:loss];
                dispatch_semaphore_t dropped=reply[@"dropped"];
                if (dropped) dispatch_semaphore_signal(dropped);
                return;
            }
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
        ActiveBytes=PeakBytes=0;FourStarted=nil;FiveStarted=nil;InjectedConnectionLosses=0;
        StartedReached=nil;StartedTarget=0;
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
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size window:(uint64_t)window error:(NSError **)error {
    (void)window;
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
- (NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size window:(uint64_t)window error:(NSError **)error {
    (void)url;(void)window;assert(offset==37);
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
    TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
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
    // Lose the first archive range halfway through. Retry only that exact range
    // after the first delay, discard its partial bytes, and deliver every
    // verified object exactly once.
    NSMutableDictionary *faulty=[responses mutableCopy];
    NSUInteger firstOffset=[offsets[0] unsignedIntegerValue];
    NSString *firstRange=[NSString stringWithFormat:@"bytes=%lu-%lu",(unsigned long)firstOffset,
        (unsigned long)(firstOffset+[objects[0] length]-1)];
    faulty[archiveKey]=@{@"data":archive,@"dropRange":firstRange,@"connectionLosses":@1};
    ResetProtocol(faulty);[seen removeAllObjects];error=nil;
    clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
    BOOL retried=[client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)problem;assert([TKWoWMD5(data) isEqual:key] && ![seen containsObject:key]);[seen addObject:key];return YES;
    } error:&error];
    if(!retried)fprintf(stderr,"Retried fixture: %s seen=%lu started=%lu losses=%lu\n",error.localizedDescription.UTF8String,(unsigned long)seen.count,(unsigned long)StartedRequests,(unsigned long)InjectedConnectionLosses);
    assert(retried);
    assert(!error && seen.count==objects.count && InjectedConnectionLosses==1 && StartedRequests==objects.count+1);
    assert(([clock.delays isEqual:@[@1]] && clock.delays.count==1));

    // Cancelling a request that is already waiting out a delay ends it at once
    // and starts no further attempt.
    TKSessionClient *paused=[TKSessionClient new];
    TKFakeRetryScheduler *waiting=[TKFakeRetryScheduler new];waiting.hold=YES;waiting.entered=dispatch_semaphore_create(0);
    paused.retryScheduler=waiting;
    NSURL *offline=[NSURL URLWithString:@"https://fixture.invalid/object"];
    ResetProtocol(@{@"object":@{@"data":objects[0],@"connectionLosses":@100}});
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        dispatch_semaphore_wait(waiting.entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
        [paused cancel];
    });
    error=nil;
    assert(![paused fetch:offline limit:[objects[0] length] error:&error]);
    assert(paused.cancelled && error && StartedRequests==1 && waiting.signalled);
    assert(([waiting.delays isEqual:@[@1]]));

    // Invalid range responses still cancel siblings without scheduling another window.
    faulty[archiveKey]=@{@"data":archive,@"delay":@0.01,@"contentRange":@"bytes 0-0/1"};
    ResetProtocol(faulty);[seen removeAllObjects];error=nil;
    assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)data;(void)key;(void)problem;[seen addObject:key];return YES;
    } error:&error]);
    // NSURLSession may return the terminal transport error before its cancelled
    // NSURLProtocol siblings run their stop-loading cleanup. Drain those scheduled
    // fixture deliveries before asserting the protocol accounting boundary.
    assert(!dispatch_group_wait(ProtocolDeliveries,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
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
// The synthetic metadata every plan is derived from, so an unretried run and a
// retried run can be compared field for field.
static NSMutableDictionary *MetadataFixture(void) {
    NSMutableDictionary *responses=[NSMutableDictionary new];
    NSData *original=Text(@"test"),*raw=Wrap(original);
    responses[TKWoWMD5(raw)]=raw;
    NSMutableData *install=[Text(@"IN") mutableCopy];BE(install,1,1);BE(install,16,1);BE(install,0,2);BE(install,1,4);
    [install appendData:Text(@"Test.app/Contents/MacOS/Test")];BE(install,0,1);[install appendData:Hash(original)];BE(install,original.length,4);
    NSMutableData *encoding=[Text(@"EN") mutableCopy];BE(encoding,1,1);BE(encoding,16,1);BE(encoding,16,1);
    BE(encoding,1,2);BE(encoding,1,2);BE(encoding,1,4);BE(encoding,0,4);BE(encoding,0,1);BE(encoding,0,4);
    [encoding appendData:[NSMutableData dataWithLength:32]];
    BE(encoding,1,1);BE(encoding,original.length,5);[encoding appendData:Hash(original)];[encoding appendData:Hash(raw)];
    encoding.length=22+32+1024;
    NSString *config=[NSString stringWithFormat:@"build-uid = wowf\n%@%@",
        ReferenceResponses(@"install",install,responses),ReferenceResponses(@"encoding",encoding,responses)];
    NSString *build=TKWoWMD5(Text(config)),*cdn=TKWoWMD5(Text(@"cdn"));
    responses[build]=Text(config);
    responses[@"versions"]=Text([NSString stringWithFormat:@"Region|BuildConfig|CDNConfig|VersionsName\neu|%@|%@|synthetic-1\n",build,cdn]);
    responses[@"cdns"]=Text(@"Name|Path|Hosts|Servers\neu|tpr/wow|level3.ssl.blizzard.com|https://level3.ssl.blizzard.com/?maxhosts=4&fallback=1\n");
    return responses;
}
// The retry schedule is exact and the clock is virtual: five attempts at most,
// each after twice the previous delay, then the final transport error.
static void TestRetrySchedule(void) {
    TKSessionClient *client=[TKSessionClient new];
    TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
    NSData *body=Wrap(Text(@"synthetic retried object"));
    NSURL *offline=[NSURL URLWithString:@"https://fixture.invalid/object"];
    NSError *error=nil;
    ResetProtocol(@{@"object":@{@"data":body,@"connectionLosses":@100}});
    assert(![client fetch:offline limit:body.length error:&error]);
    assert([error.domain isEqual:NSURLErrorDomain] && error.code==NSURLErrorNetworkConnectionLost);
    assert(([clock.delays isEqual:@[@1,@2,@4,@8]] && StartedRequests==5 && InjectedConnectionLosses==5));
    assert(!ActiveRequests);
    // One drop costs exactly one delay, and the whole body arrives: the half
    // received before the drop is discarded, never appended to.
    clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
    ResetProtocol(@{@"object":@{@"data":body,@"connectionLosses":@1}});
    error=nil;
    NSData *data=[client fetch:offline limit:body.length error:&error];
    assert(([data isEqual:body] && !error && [clock.delays isEqual:@[@1]] && StartedRequests==2));
    assert(!ActiveRequests);
}
// Every other failure class fails on its first attempt: no delay is scheduled
// and the original error reaches the caller.
static void TestTerminalFailures(void) {
    TKSessionClient *client=[TKSessionClient new];
    NSData *body=Wrap(Text(@"synthetic terminal object"));
    NSURL *offline=[NSURL URLWithString:@"https://fixture.invalid/object"];
    NSError *error=nil;
    NSArray *terminal=@[@(NSURLErrorSecureConnectionFailed),@(NSURLErrorServerCertificateHasBadDate),
        @(NSURLErrorServerCertificateUntrusted),@(NSURLErrorServerCertificateNotYetValid),
        @(NSURLErrorClientCertificateRejected),@(NSURLErrorClientCertificateRequired),
        @(NSURLErrorHTTPTooManyRedirects),@(NSURLErrorBadServerResponse),@(NSURLErrorResourceUnavailable),
        @(NSURLErrorCancelled),@(NSURLErrorUserCancelledAuthentication),@(NSURLErrorZeroByteResource),
        @(NSURLErrorDataLengthExceedsMaximum),@(NSURLErrorFileDoesNotExist),
        @(NSURLErrorNoPermissionsToReadFile),@(NSURLErrorUnsupportedURL),
        @(NSURLErrorAppTransportSecurityRequiresSecureConnection)];
    for(NSNumber *code in terminal) {
        TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
        ResetProtocol(@{@"object":@{@"data":body,@"failWith":@{@"domain":NSURLErrorDomain,@"code":code}}});
        error=nil;
        assert(![client fetch:offline limit:body.length error:&error]);
        assert(error && [error.domain isEqual:NSURLErrorDomain] && error.code==code.integerValue);
        assert(clock.delays.count==0 && StartedRequests==1 && !ActiveRequests);
    }
    // HTTP status, a wrong Content-Range and a short body are our own terminal
    // errors, not transport failures.
    TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
    ResetProtocol(@{@"object":@{@"data":body,@"status":@500}});
    error=nil;
    assert(![client fetch:offline limit:body.length error:&error]);
    assert([error.localizedDescription containsString:@"HTTP 500"] && clock.delays.count==0 && StartedRequests==1);
    clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
    ResetProtocol(@{@"object":@{@"data":body,@"contentRange":@"bytes 0-0/1"}});
    error=nil;
    assert(![client range:offline offset:0 size:16 error:&error]);
    assert(error && clock.delays.count==0 && StartedRequests==1);
    clock=[TKFakeRetryScheduler new];client.retryScheduler=clock;
    ResetProtocol(@{@"object":@{@"data":body,@"truncate":@YES}});
    error=nil;
    assert(![client range:offline offset:0 size:body.length error:&error]);
    assert([error.localizedDescription containsString:@"Incomplete range"] && clock.delays.count==0 && StartedRequests==1);
    assert(!ActiveRequests);
}
// A sibling's terminal failure ends a request that is already waiting, instead
// of letting it wait out the remaining delay.
static void TestSiblingFailureWakesWait(void) {
    NSMutableArray *objects=[NSMutableArray new],*offsets=[NSMutableArray new];
    NSMutableData *archive=[NSMutableData dataWithLength:37];
    NSData *present=Wrap(Text(@"synthetic archive member"));
    [objects addObject:present];[offsets addObject:@(archive.length)];[archive appendData:present];
    NSString *archiveKey=TKWoWMD5(archive);
    NSData *waiting=Wrap(Text(@"synthetic waiting object")),*failing=Wrap(Text(@"synthetic failing object"));
    NSMutableData *records=[NSMutableData new];
    for(NSData *raw in @[waiting,failing]) {
        TKWoWDownloadEntry entry={0};assert(TKWoWUnhex(TKWoWMD5(raw),entry.key));entry.size=raw.length;
        [records appendBytes:&entry length:sizeof(entry)];
    }
    NSData *config=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);
    NSDictionary *responses=@{archiveKey:@{@"data":archive},
        [archiveKey stringByAppendingString:@".index"]:@{@"data":ArchiveIndex(objects,offsets)},
        TKWoWMD5(config):@{@"data":config},
        TKWoWMD5(waiting):@{@"data":waiting,@"connectionLosses":@100},
        TKWoWMD5(failing):@{@"data":failing,@"status":@500,@"delay":@0.3}};
    NSDictionary *plan=@{@"cdn":@"https://fixture.invalid/tpr/wow",@"version":@{@"CDNConfig":TKWoWMD5(config)}};
    NSString *indices=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    TKSessionClient *client=[TKSessionClient new];
    TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];clock.hold=YES;clock.entered=dispatch_semaphore_create(0);
    client.retryScheduler=clock;
    ResetProtocol(responses);
    NSError *error=nil;
    assert(![client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **problem){
        (void)data;(void)key;(void)problem;assert(!"No object is consumed from a failed operation");return NO;
    } error:&error]);
    assert((clock.signalled && [clock.delays isEqual:@[@1]]));
    assert([error.localizedDescription containsString:@"HTTP 500"]);
    // Configuration, archive index, the waiting object and the failed one.
    assert(StartedRequests==4 && InjectedConnectionLosses==1 && !ActiveRequests);
    assert([NSFileManager.defaultManager removeItemAtPath:indices error:NULL]);
}
// A retry delay is not an occupied transfer slot: while one range waits, four
// unrelated ranges still transfer, and cancellation then wakes the waiting one.
static void TestDelayFreesTransferSlot(void) {
    NSMutableArray *objects=[NSMutableArray new],*offsets=[NSMutableArray new];
    NSMutableData *archive=[NSMutableData dataWithLength:37],*records=[NSMutableData new];
    for(NSUInteger i=0;i<6;i++) {
        NSData *raw=Wrap(Text([NSString stringWithFormat:@"Synthetic slot range %lu",(unsigned long)i]));
        [objects addObject:raw];[offsets addObject:@(archive.length)];[archive appendData:raw];archive.length+=65537;
        TKWoWDownloadEntry entry={0};assert(TKWoWUnhex(TKWoWMD5(raw),entry.key));entry.size=raw.length;
        [records appendBytes:&entry length:sizeof(entry)];
    }
    NSString *archiveKey=TKWoWMD5(archive);
    NSUInteger offset=[offsets[0] unsignedIntegerValue];
    NSString *dropRange=[NSString stringWithFormat:@"bytes=%lu-%lu",(unsigned long)offset,
        (unsigned long)(offset+[objects[0] length]-1)];
    NSData *config=Text([NSString stringWithFormat:@"archives = %@\n",archiveKey]);
    NSDictionary *responses=@{archiveKey:@{@"data":archive,@"dropRange":dropRange,@"connectionLosses":@1,
            @"holdAll":@YES},
        [archiveKey stringByAppendingString:@".index"]:@{@"data":ArchiveIndex(objects,offsets)},
        TKWoWMD5(config):@{@"data":config}};
    NSDictionary *plan=@{@"cdn":@"https://fixture.invalid/tpr/wow",@"version":@{@"CDNConfig":TKWoWMD5(config)}};
    NSString *indices=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    TKSessionClient *client=[TKSessionClient new];
    TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];clock.hold=YES;clock.entered=dispatch_semaphore_create(0);
    client.retryScheduler=clock;
    ResetProtocol(responses);StartedReached=dispatch_semaphore_create(0);StartedTarget=7;
    dispatch_semaphore_t finished=dispatch_semaphore_create(0);__block BOOL result=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *problem=nil;
        result=[client downloadEntries:records plan:plan indices:indices consume:^BOOL(NSData *data,NSString *key,NSError **error){
            (void)data;(void)key;(void)error;assert(!"No payload is consumed");return NO;
        } error:&problem];
        dispatch_semaphore_signal(finished);
    });
    // The dropped range is waiting out its delay ...
    assert(!dispatch_semaphore_wait(clock.entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
    // ... and the fifth object still starts: the only slot it could take is the
    // one the waiting range handed back, because the other three are held open.
    assert(!dispatch_semaphore_wait(StartedReached,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
    assert(StartedRequests==StartedTarget && ActiveRequests==4);
    [client cancel];
    assert(!dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)));
    assert((!result && client.cancelled && clock.signalled && [clock.delays isEqual:@[@1]]));
    StartedReached=nil;StartedTarget=0;
    assert(!dispatch_group_wait(ProtocolDeliveries,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)));
    assert(!ActiveRequests);
    assert([NSFileManager.defaultManager removeItemAtPath:indices error:NULL]);
}
// A retried metadata request re-requests exactly that object. The plan the
// launcher derives from it is field-for-field identical, so a retry cannot move
// metadata, verification inputs, activation or Play eligibility.
static void TestMetadataContract(void) {
    NSMutableDictionary *plain=MetadataFixture(),*replies=[NSMutableDictionary new];
    for(NSString *key in plain)replies[key]=@{@"data":plain[key]};
    TKSessionClient *clean=[TKSessionClient new];clean.retryScheduler=[TKFakeRetryScheduler new];
    NSError *error=nil;
    ResetProtocol(replies);
    NSDictionary *expected=[clean planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];
    if(!expected)fprintf(stderr,"Metadata fixture: %s\n",error.localizedDescription.UTF8String);
    assert(expected && !error);
    NSUInteger baseline=StartedRequests,losses=InjectedConnectionLosses;
    NSMutableDictionary *faulty=[replies mutableCopy];
    faulty[@"versions"]=@{@"data":plain[@"versions"],@"connectionLosses":@1};
    TKSessionClient *retried=[TKSessionClient new];
    TKFakeRetryScheduler *clock=[TKFakeRetryScheduler new];retried.retryScheduler=clock;
    ResetProtocol(faulty);error=nil;
    NSDictionary *actual=[retried planForProduct:@"wowf" region:@"eu" locale:@"enUS" error:&error];
    assert(actual && !error && [actual isEqual:expected]);
    assert(StartedRequests==baseline+1 && InjectedConnectionLosses==losses+1);
    assert(([clock.delays isEqual:@[@1]] && !ActiveRequests));
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
    TestRetrySchedule();
    TestTerminalFailures();
    TestSiblingFailureWakesWait();
    TestDelayFreesTransferSlot();
    TestMetadataContract();
    puts("WoW client tests PASS: bounded concurrent transfers, serial consumption, range validation, cancellation, verified staging, cache repair, patch invalidation, malformed metadata and failed transport; retries are 1/2/4/8 s on a virtual clock, discard partial bytes, free their transfer slot, wake on cancellation or a terminal sibling, fail every other class at once, and leave metadata unchanged.");
    return 0;
}
