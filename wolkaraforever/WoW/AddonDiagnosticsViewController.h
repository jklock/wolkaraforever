#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The developer switches that make the Add-On Manager explain itself, on their own page.
//
// It is reached from the home gear's Settings sheet rather than from the Add-On Manager, because
// a diagnostic switch belongs with the other diagnostics and because the Settings sheet's root
// is not the place for a one-tap switch that changes what an app records about a session.
//
// The page owns neither the controller inspector nor the input router: the home page passes what
// should happen when the input switch changes, so this file is UIKit and the hub log only, and a
// fixture can drive it without an input adapter.
@interface TKAddonDiagnosticsViewController : UITableViewController
// `on` is the state the input switch starts in; the add-on switch reads the stored value.
- (instancetype)initWithInputDiagnosticsOn:(BOOL)on;
// Called with the new value whenever the person changes the input switch. The page does not
// remember it beyond this session; the caller's inspector does.
@property(nonatomic, copy, nullable) void (^inputDiagnosticsChanged)(BOOL enabled);
@end

NS_ASSUME_NONNULL_END
