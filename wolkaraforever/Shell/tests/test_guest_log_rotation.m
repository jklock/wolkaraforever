#import <Foundation/Foundation.h>
#import "GuestLogRotation.h"

static int failures;
#define CHECK(value, name) do { if (!(value)) { fprintf(stderr, "FAIL %s\n", name); failures++; } } while (0)

static void rotation_case(NSString *name, NSData *current, NSData *old, BOOL blocked,
                          WKGuestLogKeep expected) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"guest-log-rotation-%d-%@", getpid(), name]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:dir error:NULL];
    CHECK([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL], "create fixture directory");
    NSString *log = [dir stringByAppendingPathComponent:@"native-guest.log"];
    NSString *previous = [dir stringByAppendingPathComponent:@"native-guest.previous.log"];
    if (current) CHECK([current writeToFile:log atomically:YES], "write current");
    if (old) CHECK([old writeToFile:previous atomically:YES], "write previous");
    if (blocked) {
        CHECK([fm createDirectoryAtPath:previous withIntermediateDirectories:NO attributes:nil error:NULL], "create obstructing directory");
        CHECK([@"occupied" writeToFile:[previous stringByAppendingPathComponent:@"child"] atomically:YES encoding:NSUTF8StringEncoding error:NULL], "make directory nonempty");
    }
    NSString *problem = nil;
    WKGuestLogKeep result = WKGuestLogKeepPrevious(log, previous, &problem);
    CHECK(result == expected, "rotation result");
    CHECK((expected == WKGuestLogKeepFailed) == (problem.length > 0), "problem only on failure");
    if (expected == WKGuestLogKeepMoved) {
        CHECK(![fm fileExistsAtPath:log], "moved log path absent");
        CHECK([[NSData dataWithContentsOfFile:previous] isEqualToData:current], "previous has exact current bytes");
    } else if (expected == WKGuestLogKeepNothing) {
        CHECK([[NSData dataWithContentsOfFile:previous] isEqualToData:old], "absent log preserves previous bytes");
    } else {
        CHECK([[NSData dataWithContentsOfFile:log] isEqualToData:current], "failed move preserves current bytes");
    }
    [fm removeItemAtPath:dir error:NULL];
}

int main(void) {
    @autoreleasepool {
        NSData *first = [@"first\0session\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *old = [@"older\n" dataUsingEncoding:NSUTF8StringEncoding];
        rotation_case(@"R1", first, nil, NO, WKGuestLogKeepMoved);
        rotation_case(@"R2", first, old, NO, WKGuestLogKeepMoved);
        rotation_case(@"R3", nil, old, NO, WKGuestLogKeepNothing);
        rotation_case(@"R4", NSData.data, nil, NO, WKGuestLogKeepMoved);
        rotation_case(@"R5", first, nil, YES, WKGuestLogKeepFailed);
        printf("GUEST_LOG_ROTATION_%s\n", failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
