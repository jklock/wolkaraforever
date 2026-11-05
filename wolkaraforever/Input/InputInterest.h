// WolkaraForever: the one question every GameController callback asks first.
//
// The 2026-11-04 device log recorded 12,658 controller-inspector event lines in one five-minute
// run, and exactly 12,658 more in the other log sink - every inspected input was written twice.
// Each one also entered the main queue, and each one scheduled a second main-queue block for a
// diagnostic panel that was not on screen. None of it was input the user had asked for: the
// run had voice off, no mapping armed, and a controller whose sticks and buttons were being
// inspected purely because a controller was connected.
//
// So the inspector no longer decides for itself what to report. It asks this object, and the
// answer is an immutable snapshot that the router replaces wholesale whenever the user's
// choices change. Reading it allocates nothing, logs nothing and dispatches nothing, which is
// what lets the callback return before it has done any work at all.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AKInputInterestMode) {
    // Nothing is interesting. The normal state of the app during play.
    AKInputInterestModeNone = 0,
    // Exactly the elements the user has mapped for dictation, and nothing else.
    AKInputInterestModeMapped,
    // Every element a person could press, because the user is choosing one.
    AKInputInterestModeLearning,
    // Everything, including the continuous sources, because the user asked for diagnostics.
    // Off unless the configuration screen switched it on, and bounded when it is on.
    AKInputInterestModeDiagnostic,
};

@interface AKInputInterest : NSObject

+ (instancetype)none;
+ (instancetype)mappedWithElements:(NSSet<NSString *> *)elements;
+ (instancetype)learning;
+ (instancetype)diagnostic;

@property (nonatomic, readonly) AKInputInterestMode mode;
// Non-empty only in AKInputInterestModeMapped.
@property (nonatomic, readonly, copy) NSSet<NSString *> *elements;

// The whole decision, in one call. Pressable elements are pad buttons, keys, mouse buttons and
// the system's own signals; a stick axis, a d-pad position and touch-pad movement are not
// pressable and are admitted only in diagnostic mode.
- (BOOL)admitsElement:(NSString *)element;

@end

// Whether an element id names something a person can press.
FOUNDATION_EXPORT BOOL AKInputElementIsPressable(NSString *element);

// Aggregation only: a count, a maximum, and percentiles over a fixed ring of samples.
//
// This is deliberately not a log. The gate the plan sets is a p95 and a p99 over a five-minute
// sweep, which a log cannot answer without keeping every sample; a fixed ring answers it in
// constant memory and constant time, and losing the oldest sample is exactly the right thing to
// lose.
@interface AKTimingSamples : NSObject
- (void)record:(double)milliseconds;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) double maximum;
// 0.50, 0.95, 0.99. Returns 0 when nothing has been recorded.
- (double)percentile:(double)fraction;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
