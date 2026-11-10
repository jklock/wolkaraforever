#import <Foundation/Foundation.h>
#import "Manifest.h"

NS_ASSUME_NONNULL_BEGIN
// An interrupted transient request is retried once after each of these delays,
// with a fresh buffer and the same byte range. Partially received bytes are
// discarded; verified data already on the device is never touched.
extern const NSTimeInterval TKWoWRetryDelays[];
extern const NSUInteger TKWoWRetryDelayCount;

// Schedules those retry delays on a monotonic clock. Replace it in tests so a
// delay is virtual and no test sleeps.
@interface TKWoWRetryScheduler : NSObject
// Monotonic seconds from an arbitrary fixed origin: never moves backwards and
// is unaffected by wall-clock changes.
- (NSTimeInterval)monotonicNow;
// Called with `lock` held and returns with `lock` held. YES means `deadline`
// elapsed; NO means the condition was signalled first, so the caller decides
// whether to stop or wait again.
- (BOOL)waitUntil:(NSTimeInterval)deadline lock:(NSCondition *)lock;
@end

// Synchronous, bounded requests: call on a worker queue, never UIKit's main thread.
// A client performs one operation at a time. cancel is safe from another thread.
@interface TKWoWClient : NSObject
- (void)cancel;
@property(nonatomic, readonly) BOOL cancelled;
// The clock that schedules retry delays. Tests substitute a virtual clock.
@property(nonatomic, strong) TKWoWRetryScheduler *retryScheduler;
@property(nonatomic, copy, nullable) void (^progress)(NSString *phase, uint64_t done, uint64_t total);
- (nullable NSData *)configuration:(NSString *)key cdn:(NSString *)cdn error:(NSError **)error;
- (nullable NSData *)manifest:(NSString *)name config:(NSDictionary *)config cdn:(NSString *)cdn error:(NSError **)error;
- (nullable NSData *)encodingForPlan:(NSDictionary *)plan directory:(NSString *)directory error:(NSError **)error;
- (nullable NSData *)encodedKey:(NSString *)key size:(uint64_t)size plan:(NSDictionary *)plan
    indices:(NSString *)indices error:(NSError **)error;
// Downloads up to four bounded archive ranges concurrently (64 MiB window;
// larger individual objects run alone), refilling each slot after consumption.
// Ranges can complete out of order. The consumer receives
// only checksum-verified original encoded bytes, serially on the calling queue.
- (BOOL)downloadEntries:(NSData *)entries plan:(NSDictionary *)plan indices:(NSString *)indices
    consume:(BOOL (^)(NSData *data, NSString *key, NSError **error))consume error:(NSError **)error;
- (nullable NSDictionary *)versionForProduct:(NSString *)product region:(NSString *)region error:(NSError **)error;
// Fetches and verifies the build configuration and install manifest. Does not install a game.
- (nullable NSDictionary *)planForProduct:(NSString *)product region:(NSString *)region
    locale:(NSString *)locale error:(NSError **)error;
// Experimental extraction of one original install file to an isolated staging directory.
// Fetches the encoding manifest (can be large), with verified archive-range fallback.
- (nullable NSString *)stageFile:(NSDictionary *)file plan:(NSDictionary *)plan
    directory:(NSString *)directory error:(NSError **)error;
@end

// The transfer hooks the downloader itself uses. Each call already owns `window`
// bytes of the bounded range window, so a retry delay can hand the reservation
// back and let an unrelated range start. The plain fetch/range entry points
// reserve nothing. Subclasses replace these to inject a transport.
@interface TKWoWClient (TKTransfer)
- (nullable NSData *)fetch:(NSURL *)url limit:(NSUInteger)limit window:(uint64_t)window
    error:(NSError **)error;
- (nullable NSData *)range:(NSURL *)url offset:(uint64_t)offset size:(NSUInteger)size
    window:(uint64_t)window error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
