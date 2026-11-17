#import "ControllerTouchpadViewController.h"

#import "../Input/ControllerTouchpad.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"

@interface AKControllerTouchpadViewController ()
@property(nonatomic) UISwitch *enabledSwitch;
@property(nonatomic) UISegmentedControl *speedControl;
@property(nonatomic) UILabel *reportLabel;
@property(nonatomic) UILabel *statusLabel;
@end

@implementation AKControllerTouchpadViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=WKLocalized(@"touchpad.title").uppercaseString;
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=WKInk();
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.navigationItem.leftBarButtonItem.tintColor=WKGold();

    UIScrollView *scroll=[UIScrollView new];
    scroll.accessibilityIdentifier=@"touchpad.configuration.scroll";
    scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll];
    UIStackView *rows=[UIStackView new]; rows.axis=UILayoutConstraintAxisVertical; rows.spacing=22;
    rows.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:rows];
    [rows addArrangedSubview:WKNote(WKLocalized(@"touchpad.intro"))];

    [rows addArrangedSubview:WKHeading(WKLocalized(@"touchpad.heading.pointer"))];
    AKControllerTouchpadRelay *relay=AKControllerTouchpadRelay.shared;
    _enabledSwitch=[UISwitch new]; _enabledSwitch.on=relay.enabled;
    _enabledSwitch.accessibilityIdentifier=@"touchpad.enabled";
    _enabledSwitch.accessibilityLabel=WKLocalized(@"touchpad.enabled");
    [_enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [rows addArrangedSubview:[self card:@[[self switchRow:WKLocalized(@"touchpad.enabled") control:_enabledSwitch],
        WKNote(WKLocalized(@"touchpad.enabled.note"))]]];

    [rows addArrangedSubview:WKHeading(WKLocalized(@"touchpad.heading.speed"))];
    _speedControl=[[UISegmentedControl alloc] initWithItems:@[WKLocalized(@"touchpad.speed.slow"),
        WKLocalized(@"touchpad.speed.normal"),WKLocalized(@"touchpad.speed.fast")]];
    _speedControl.selectedSegmentIndex=relay.speed;
    _speedControl.accessibilityIdentifier=@"touchpad.speed";
    _speedControl.accessibilityLabel=WKLocalized(@"touchpad.heading.speed");
    _speedControl.selectedSegmentTintColor=WKGold();
    [_speedControl setTitleTextAttributes:@{NSForegroundColorAttributeName:WKOnGold()} forState:UIControlStateSelected];
    [_speedControl setTitleTextAttributes:@{NSForegroundColorAttributeName:WKMuted()} forState:UIControlStateNormal];
    [_speedControl addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [rows addArrangedSubview:[self card:@[_speedControl,WKNote(WKLocalized(@"touchpad.speed.note"))]]];

    [rows addArrangedSubview:WKHeading(WKLocalized(@"touchpad.heading.test"))];
    _statusLabel=WKNote(@""); _statusLabel.accessibilityIdentifier=@"touchpad.test.status";
    _reportLabel=WKLabel(18,UIFontWeightSemibold,UIColor.whiteColor);
    _reportLabel.accessibilityIdentifier=@"touchpad.test.coordinates";
    UIButton *clear=WKRowButton(@"touchpad.test.clear");
    [clear setTitle:WKLocalized(@"common.clear") forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clearReport) forControlEvents:UIControlEventTouchUpInside];
    [rows addArrangedSubview:[self card:@[WKNote(WKLocalized(@"touchpad.test.note")),_statusLabel,_reportLabel,clear]]];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [rows.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],
        [rows.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],
        [rows.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [rows.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [rows.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(touchpadReported:)
        name:AKControllerTouchpadPointerNotification object:relay];
    [self clearReport];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)done { WKDismissPage(self); }
- (void)enabledChanged:(UISwitch *)sender {
    AKControllerTouchpadRelay.shared.enabled=sender.on;
    [self clearReport];
}
- (void)speedChanged:(UISegmentedControl *)sender {
    AKControllerTouchpadRelay.shared.speed=(AKControllerTouchpadSpeed)sender.selectedSegmentIndex;
}
- (void)clearReport {
    BOOL enabled=AKControllerTouchpadRelay.shared.enabled;
    _statusLabel.text=enabled?WKLocalized(@"touchpad.test.waiting"):WKLocalized(@"touchpad.test.off");
    _reportLabel.text=WKLocalized(@"touchpad.test.none");
}
- (void)touchpadReported:(NSNotification *)note {
    NSDictionary *info=note.userInfo;
    if (info[AKControllerTouchpadResetKey]) {
        _statusLabel.text=WKLocalized(@"touchpad.test.reset");
        _reportLabel.text=WKLocalized(@"touchpad.test.none");
        return;
    }
    if (info[AKControllerTouchpadClickKey]) {
        _statusLabel.text=[info[AKControllerTouchpadClickKey] boolValue] ? WKLocalized(@"touchpad.test.clickDown") : WKLocalized(@"touchpad.test.clickUp");
        return;
    }
    _statusLabel.text=WKLocalized(@"touchpad.test.receiving");
    _reportLabel.text=WKLocalizedFormat(@"touchpad.test.coordinates",
        [info[AKControllerTouchpadFingersKey] unsignedIntegerValue],
        [info[AKControllerTouchpadXKey] doubleValue], [info[AKControllerTouchpadYKey] doubleValue]);
}
- (UIView *)card:(NSArray<UIView *> *)items {
    UIView *card=WKCard(); UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:items];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]]];
    return card;
}
- (UIView *)switchRow:(NSString *)title control:(UISwitch *)control {
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[WKLabel(16,UIFontWeightRegular,UIColor.whiteColor),control]];
    ((UILabel *)row.arrangedSubviews.firstObject).text=title;
    row.axis=UILayoutConstraintAxisHorizontal; row.alignment=UIStackViewAlignmentCenter;
    return row;
}
@end
