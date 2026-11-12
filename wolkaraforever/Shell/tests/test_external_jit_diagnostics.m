#import <Foundation/Foundation.h>
#import "ExternalJITDiagnostics.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSString *path = WKExternalJITDiagnosticsPath();
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        WKExternalJITDiagnosticsBegin(@"saved");
        WKExternalJITDiagnosticsCheckpoint(@"native-startup-entered");
        WKExternalJITDiagnosticsFinish(YES);
        NSString *record = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        assert([record containsString:@"launch-begin source=saved"]);
        assert([record containsString:@"native-startup-entered"]);
        assert([record containsString:@"native-return success"]);
        puts("PASS: External-JIT diagnostics persist host checkpoints");
    }
    return 0;
}
