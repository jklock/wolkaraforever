// Durable, host-only breadcrumbs for External-JIT runs. These are intentionally separate from
// native-guest.log because an abrupt process termination may leave that file incomplete.
#import <Foundation/Foundation.h>

void WKExternalJITDiagnosticsBegin(NSString *source);
void WKExternalJITDiagnosticsCheckpoint(NSString *event);
void WKExternalJITDiagnosticsFinish(BOOL success);
NSString *WKExternalJITDiagnosticsPath(void);
