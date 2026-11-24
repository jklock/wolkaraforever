#import "AddonDiagnosticsViewController.h"
#import "AddonHubLog.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WolkaraForeverTheme.h"

// The page the home gear's Settings sheet opens: one switch per development aid, each with the
// sentence that says what it records, what it costs while it is off, how long the output is kept
// and where it can be read. Nothing here toggles from the sheet itself.

typedef NS_ENUM(NSInteger, TKAddonDiagnosticsSection) {
    TKAddonDiagnosticsSectionAddons = 0,
    TKAddonDiagnosticsSectionInput,
    TKAddonDiagnosticsSectionLogs,
    TKAddonDiagnosticsSectionCount,
};

@implementation TKAddonDiagnosticsViewController {
    BOOL _inputOn;
    UISwitch *_eventsSwitch;
    UISwitch *_inputSwitch;
}

- (instancetype)initWithInputDiagnosticsOn:(BOOL)on {
    if (!(self=[super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _inputOn=on;
    self.title=WKLocalized(@"addons.diagnostics.title");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=WKInk();
    self.tableView.backgroundColor=WKInk();
    self.tableView.accessibilityIdentifier=@"wow.addons.diagnostics";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem.tintColor=WKGold();
    self.navigationItem.leftBarButtonItem.accessibilityIdentifier=@"wow.addons.diagnostics.done";
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return TKAddonDiagnosticsSectionCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return 1; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch ((TKAddonDiagnosticsSection)section) {
        case TKAddonDiagnosticsSectionAddons: return WKLocalized(@"addons.diagnostics.section.addons");
        case TKAddonDiagnosticsSectionInput: return WKLocalized(@"addons.diagnostics.section.input");
        case TKAddonDiagnosticsSectionLogs: return WKLocalized(@"addons.diagnostics.section.logs");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    switch ((TKAddonDiagnosticsSection)section) {
        case TKAddonDiagnosticsSectionAddons: return WKLocalized(@"addons.diagnostics.events.footer");
        case TKAddonDiagnosticsSectionInput: return WKLocalized(@"addons.diagnostics.input.footer");
        case TKAddonDiagnosticsSectionLogs: return WKLocalized(@"addons.diagnostics.logs.footer");
        default: return nil;
    }
}

- (UISwitch *)switchWithIdentifier:(NSString *)identifier on:(BOOL)on action:(SEL)action {
    UISwitch *control=[UISwitch new];
    control.onTintColor=WKGold();
    control.on=on;
    control.accessibilityIdentifier=identifier;
    [control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return control;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"diagnostic"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"diagnostic"];
    cell.backgroundColor=WKPanel();
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor=[UIColor colorWithWhite:0.96 alpha:1];
    cell.detailTextLabel.textColor=[UIColor colorWithWhite:0.70 alpha:1];
    cell.detailTextLabel.numberOfLines=0;
    cell.accessoryView=nil;
    cell.accessoryType=UITableViewCellAccessoryNone;
    cell.detailTextLabel.text=nil;

    switch ((TKAddonDiagnosticsSection)indexPath.section) {
        case TKAddonDiagnosticsSectionAddons:
            cell.textLabel.text=WKLocalized(@"addons.diagnostics.events");
            if (!_eventsSwitch)
                _eventsSwitch=[self switchWithIdentifier:@"wow.addons.diagnostics.events"
                                                     on:TKAddonHubDiagnosticsEnabled()
                                                 action:@selector(eventsChanged:)];
            cell.accessoryView=_eventsSwitch;
            break;
        case TKAddonDiagnosticsSectionInput:
            cell.textLabel.text=WKLocalized(@"addons.diagnostics.input");
            if (!_inputSwitch)
                _inputSwitch=[self switchWithIdentifier:@"wow.addons.diagnostics.input"
                                                     on:_inputOn
                                                 action:@selector(inputChanged:)];
            cell.accessoryView=_inputSwitch;
            break;
        case TKAddonDiagnosticsSectionLogs:
            cell.textLabel.text=WKLocalized(@"addons.diagnostics.logs.title");
            // The file's own name is a name, not a sentence: it is what the Files app shows and
            // what an attached log is called, so it is not translated.
            cell.detailTextLabel.text=WKLogPath().lastPathComponent ?: @"wolkaraforever.log";
            cell.accessibilityIdentifier=@"wow.addons.diagnostics.log";
            cell.selectionStyle=UITableViewCellSelectionStyleDefault;
            break;
        default:
            break;
    }
    return cell;
}

#pragma mark - Switches

- (void)eventsChanged:(UISwitch *)sender {
    TKAddonHubSetDiagnosticsEnabled(sender.isOn);
    WKLog("ui", @"add-on manager diagnostics: %@", sender.isOn?@"on":@"off");
}

- (void)inputChanged:(UISwitch *)sender {
    _inputOn=sender.isOn;
    if (self.inputDiagnosticsChanged) self.inputDiagnosticsChanged(_inputOn);
}

@end
