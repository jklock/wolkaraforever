#import "ExternalJITDiagnostics.h"

#include <fcntl.h>
#include <mach/mach.h>
#include <os/proc.h>
#include <string.h>
#include <TargetConditionals.h>
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

void WKExternalJITDiagnosticsMemory(NSString *checkpoint) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    size_t available = 0;
#if TARGET_OS_IPHONE
    if (@available(iOS 13.0, *)) available = os_proc_available_memory();
#endif
    if (result != KERN_SUCCESS) {
        WKExternalJITWrite([NSString stringWithFormat:@"memory checkpoint=%@ unavailable=%d available=%zu",
            WKExternalJITSafe(checkpoint), result, available]);
        return;
    }
    WKExternalJITWrite([NSString stringWithFormat:@"memory checkpoint=%@ footprint=%llu resident=%llu virtual=%llu internal=%llu compressed=%llu available=%zu",
        WKExternalJITSafe(checkpoint),
        info.phys_footprint, info.resident_size, info.virtual_size, info.internal, info.compressed, available]);
}

void WKExternalJITDiagnosticsFinish(BOOL success) {
    WKExternalJITWrite(success ? @"native-return success" : @"native-return stopped");
}
