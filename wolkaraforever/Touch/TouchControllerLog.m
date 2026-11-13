#import "TouchControllerLog.h"

NSString *const AKTouchControllerLogTag = @"touch-controller";

void (*AKTouchControllerLogSink)(NSString *line) = NULL;

NSString *AKTouchControllerEventName(AKTouchControllerEvent event) {
    switch (event) {
        case AKTouchControllerEventLayout: return @"layout";
        case AKTouchControllerEventGesture: return @"gesture";
        case AKTouchControllerEventPress: return @"press";
        case AKTouchControllerEventRelease: return @"release";
        case AKTouchControllerEventThreshold: return @"threshold";
        case AKTouchControllerEventCancel: return @"cancel";
        case AKTouchControllerEventLifecycle: return @"lifecycle";
    }
    return @"event";
}

NSArray<NSString *> *AKTouchControllerLogKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"mode", @"control", @"element", @"zone", @"reason", @"from", @"to", @"count",
                 @"version", @"source", @"ms"];
    });
    return keys;
}

// A value is a word, not a sentence: 1-24 characters, starting with a letter or a digit, and
// only letters, digits, dot, dash or underscore after it. A coordinate ("412.5"), a path, a
// value with a space in it, or anything the player typed fails this and is replaced, so there
// is no shape a touch trail or a game interaction could be pushed through.
static BOOL AKTouchValueIsBounded(NSString *value) {
    NSUInteger length = value.length;
    if (length < 1 || length > 24) return NO;
    for (NSUInteger index = 0; index < length; index++) {
        unichar character = [value characterAtIndex:index];
        BOOL letter = (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z');
        BOOL digit = character >= '0' && character <= '9';
        if (index == 0 && !(letter || digit)) return NO;
        if (letter || digit || character == '.' || character == '-' || character == '_') continue;
        return NO;
    }
    return YES;
}

static NSString *AKTouchBoundedValue(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !AKTouchValueIsBounded(value)) return @"-";
    return value;
}

NSString *AKTouchControllerLogLine(AKTouchControllerEvent event, NSString *outcome,
                                   NSDictionary<NSString *, NSString *> *values) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"[%@] event=%@ outcome=%@",
        AKTouchControllerLogTag, AKTouchControllerEventName(event), AKTouchBoundedValue(outcome)];
    for (NSString *key in AKTouchControllerLogKeys()) {
        NSString *value = values[key];
        if (![value isKindOfClass:NSString.class] || !value.length) continue;
        [line appendFormat:@" %@=%@", key, AKTouchBoundedValue(value)];
    }
    return [line copy];
}

void AKTouchControllerLog(AKTouchControllerEvent event, NSString *outcome,
                          NSDictionary<NSString *, NSString *> *values) {
    NSString *line = AKTouchControllerLogLine(event, outcome, values);
    if (AKTouchControllerLogSink) { AKTouchControllerLogSink(line); return; }
    // A plain line in the app's own log, which is where a device run is read back from.
    NSLog(@"%@", line);
}
