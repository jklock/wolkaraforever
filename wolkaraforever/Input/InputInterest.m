#import "InputInterest.h"
#import "InputElement.h"

@implementation AKInputInterest

+ (instancetype)none {
    AKInputInterest *interest = [AKInputInterest new];
    interest->_mode = AKInputInterestModeNone;
    interest->_elements = [NSSet set];
    return interest;
}
+ (instancetype)mappedWithElements:(NSSet<NSString *> *)elements {
    AKInputInterest *interest = [AKInputInterest new];
    interest->_mode = AKInputInterestModeMapped;
    interest->_elements = [elements copy] ?: [NSSet set];
    return interest;
}
+ (instancetype)learning {
    AKInputInterest *interest = [AKInputInterest new];
    interest->_mode = AKInputInterestModeLearning;
    interest->_elements = [NSSet set];
    return interest;
}
+ (instancetype)diagnostic {
    AKInputInterest *interest = [AKInputInterest new];
    interest->_mode = AKInputInterestModeDiagnostic;
    interest->_elements = [NSSet set];
    return interest;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<interest mode=%ld elements=%lu>",
            (long)_mode, (unsigned long)_elements.count];
}

- (BOOL)admitsElement:(NSString *)element {
    if (!element.length) return NO;
    switch (_mode) {
        case AKInputInterestModeNone:
            return NO;
        case AKInputInterestModeDiagnostic:
            return YES;
        case AKInputInterestModeLearning:
            return AKInputElementIsPressable(element);
        case AKInputInterestModeMapped:
            // A stick's position is never something the user mapped - the vocabulary has no
            // element for a half-pushed stick - so the membership test below is exact.
            return [_elements containsObject:element];
    }
    return NO;
}

@end

BOOL AKInputElementIsPressable(NSString *element) {
    if (!element.length) return NO;
    if ([element hasPrefix:@"controller.button."]) return YES;
    if ([element hasPrefix:AKInputElementKeyboardPrefix]) return YES;
    if ([element hasPrefix:@"mouse.button."]) return YES;
    if ([element hasPrefix:@"system."]) return YES;
    return NO;
}

// A ring of 512 samples. At 120 Hz that is a little over four seconds, which is longer than any
// hitch worth acting on and short enough that a stale burst cannot hide behind fresh numbers
// once the user starts a new sweep.
enum { AKTimingCapacity = 512 };

@implementation AKTimingSamples {
    double _samples[AKTimingCapacity];
    NSUInteger _count;
    NSUInteger _next;
}

- (void)record:(double)milliseconds {
    if (!(milliseconds >= 0)) return;
    @synchronized (self) {
        _samples[_next] = milliseconds;
        _next = (_next + 1) % AKTimingCapacity;
        if (_count < AKTimingCapacity) _count += 1;
    }
}
- (NSUInteger)count {
    @synchronized (self) { return _count; }
}
- (double)maximum {
    @synchronized (self) {
        double value = 0;
        for (NSUInteger index = 0; index < _count; index++) value = MAX(value, _samples[index]);
        return value;
    }
}
- (double)percentile:(double)fraction {
    double values[AKTimingCapacity];
    NSUInteger count;
    @synchronized (self) {
        count = _count;
        for (NSUInteger index = 0; index < count; index++) values[index] = _samples[index];
    }
    if (!count) return 0;
    // Insertion sort over at most 512 doubles, on a diagnostic path only.
    for (NSUInteger a = 1; a < count; a++) {
        double value = values[a];
        NSUInteger b = a;
        while (b > 0 && values[b - 1] > value) { values[b] = values[b - 1]; b -= 1; }
        values[b] = value;
    }
    double clamped = MIN(MAX(fraction, 0.0), 1.0);
    NSUInteger index = (NSUInteger)floor(clamped * (double)(count - 1));
    return values[index];
}
- (void)reset {
    @synchronized (self) { _count = 0; _next = 0; }
}

@end
