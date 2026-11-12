#import "ExternalJITDiagnostics.h"

#include <fcntl.h>
#include <string.h>
#include <unistd.h>

static NSString *WKExternalJITPath;

NSString *WKExternalJITDiagnosticsPath(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:NULL];
        WKExternalJITPath = [documents stringByAppendingPathComponent:@"external-jit-diagnostics.log"];
    });
    return WKExternalJITPath;
}

static NSString *WKExternalJITSafe(NSString *value) {
    return [[value ?: @"unknown" stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
}

static void WKExternalJITWrite(NSString *event) {
    NSString *line = [NSString stringWithFormat:@"%lld %@\n", (long long)(NSDate.date.timeIntervalSince1970 * 1000), WKExternalJITSafe(event)];
    int descriptor = open(WKExternalJITDiagnosticsPath().fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (descriptor < 0) return;
    const char *bytes = line.UTF8String;
    if (bytes) {
        (void)write(descriptor, bytes, strlen(bytes));
        (void)fsync(descriptor);
    }
    close(descriptor);
}

void WKExternalJITDiagnosticsBegin(NSString *source) {
    WKExternalJITWrite([NSString stringWithFormat:@"launch-begin source=%@", WKExternalJITSafe(source)]);
}

void WKExternalJITDiagnosticsCheckpoint(NSString *event) {
    if (event.length) WKExternalJITWrite(event);
}

void WKExternalJITDiagnosticsFinish(BOOL success) {
    WKExternalJITWrite(success ? @"native-return success" : @"native-return stopped");
}
