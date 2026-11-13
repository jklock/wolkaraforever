// Durable, host-only breadcrumbs for External-JIT runs. These are intentionally separate from
// native-guest.log because an abrupt process termination may leave that file incomplete.
#import <Foundation/Foundation.h>

void WKExternalJITDiagnosticsBegin(NSString *source);
void WKExternalJITDiagnosticsCheckpoint(NSString *event);
// Host-process memory values in bytes. This is intentionally host-only: it does not inspect
// guest memory and is safe to persist after an unexpected termination.
void WKExternalJITDiagnosticsMemory(NSString *checkpoint);
void WKExternalJITDiagnosticsFinish(BOOL success);
NSString *WKExternalJITDiagnosticsPath(void);
