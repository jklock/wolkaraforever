#import "BatterySaverOptionsViewController.h"

#import "BatterySaverPolicy.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WolkaraForeverTheme.h"

@implementation AKBatterySaverOptionsViewController {
    NSArray<UIButton *> *_limitButtons;
    NSArray<UIButton *> *_afkButtons;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = WKLocalized(@"home.batterySaver.title").uppercaseString;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = WKInk();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    done.tintColor = WKGold();
    done.accessibilityIdentifier = @"batterySaver.done";
    self.navigationItem.leftBarButtonItem = done;

    UIScrollView *scroll = [UIScrollView new];
    scroll.accessibilityIdentifier = @"batterySaver.scroll";
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *rows = [[UIStackView alloc] init];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 26;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:rows];

    [rows addArrangedSubview:WKNote(WKLocalized(@"home.batterySaver.options.note"))];

    // --- Frame limit --------------------------------------------------------
    [rows addArrangedSubview:WKHeading(WKLocalized(@"home.batterySaver.frameLimit.title"))];
    _limitButtons = @[
        [self row:@"batterySaver.limit.off" tag:AKBatterySaverFrameLimitOff action:@selector(limitChosen:)],
        [self row:@"batterySaver.limit.auto" tag:AKBatterySaverFrameLimitAutomatic action:@selector(limitChosen:)],
        [self row:@"batterySaver.limit.30" tag:AKBatterySaverFrameLimit30 action:@selector(limitChosen:)],
        [self row:@"batterySaver.limit.60" tag:AKBatterySaverFrameLimit60 action:@selector(limitChosen:)],
    ];
    [rows addArrangedSubview:[self card:_limitButtons]];
    [rows addArrangedSubview:WKNote(WKLocalized(@"home.batterySaver.frameLimit.message"))];

    // --- AFK saver ----------------------------------------------------------
    [rows addArrangedSubview:WKHeading(WKLocalized(@"home.batterySaver.afk.title"))];
    _afkButtons = @[
        [self row:@"batterySaver.afk.off" tag:0 action:@selector(afkChosen:)],
        [self row:@"batterySaver.afk.2" tag:2 action:@selector(afkChosen:)],
        [self row:@"batterySaver.afk.5" tag:5 action:@selector(afkChosen:)],
        [self row:@"batterySaver.afk.10" tag:10 action:@selector(afkChosen:)],
    ];
    [rows addArrangedSubview:[self card:_afkButtons]];
    [rows addArrangedSubview:WKNote(WKLocalized(@"home.batterySaver.afk.message"))];

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

    [self render];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self render];
}

- (void)done {
    WKDismissPage(self);
}

- (UIButton *)row:(NSString *)identifier tag:(NSInteger)tag action:(SEL)action {
    UIButton *button = WKRowButton(identifier);
    button.tag = tag;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)card:(NSArray<UIView *> *)rows {
    UIView *panel = WKCard();
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
    ]];
    return panel;
}

// The words a choice reads as. Kept here rather than in the home page: this page is the only
// place that shows them now.
- (NSString *)limitText:(AKBatterySaverFrameLimit)limit {
    switch (limit) {
        case AKBatterySaverFrameLimitAutomatic: return WKLocalized(@"home.batterySaver.frame.automatic");
        case AKBatterySaverFrameLimit30: return WKLocalized(@"home.batterySaver.frame.30");
        case AKBatterySaverFrameLimit60: return WKLocalized(@"home.batterySaver.frame.60");
        case AKBatterySaverFrameLimitOff: break;
    }
    return WKLocalized(@"home.batterySaver.off");
}

- (NSString *)afkText:(NSInteger)minutes {
    switch (minutes) {
        case 2: return WKLocalized(@"home.batterySaver.afk.2");
        case 5: return WKLocalized(@"home.batterySaver.afk.5");
        case 10: return WKLocalized(@"home.batterySaver.afk.10");
        default: break;
    }
    return WKLocalized(@"home.batterySaver.off");
}

- (void)setTitle:(NSString *)title selected:(BOOL)selected on:(UIButton *)button {
    UIButtonConfiguration *configuration = [button.configuration copy] ?: UIButtonConfiguration.plainButtonConfiguration;
    configuration.title = selected ? [@"✓ " stringByAppendingString:title] : title;
    configuration.baseForegroundColor = selected ? WKGold() : WKMuted();
    button.configuration = configuration;
    button.accessibilityValue = selected ? WKLocalized(@"batterySaver.selected") : nil;
}

// The current choice in each group is the one marked; nothing here is enabled or disabled by
// the master switch, because these are the values it turns on.
- (void)render {
    AKBatterySaverFrameLimit limit = AKBatterySaverStoredFrameLimit();
    for (UIButton *button in _limitButtons) {
        AKBatterySaverFrameLimit each = (AKBatterySaverFrameLimit)button.tag;
        [self setTitle:[self limitText:each] selected:(each == limit) on:button];
    }
    NSInteger minutes = AKBatterySaverStoredAFKMinutes();
    for (UIButton *button in _afkButtons) {
        NSInteger each = button.tag;
        [self setTitle:[self afkText:each] selected:(each == minutes) on:button];
    }
}

- (void)limitChosen:(UIButton *)sender {
    AKBatterySaverFrameLimit limit = (AKBatterySaverFrameLimit)sender.tag;
    AKBatterySaverSetFrameLimit(limit);
    WKLog("ui", @"battery saver: frame limit %@", AKBatterySaverFrameLimitStoredName(limit));
    [self render];
}

- (void)afkChosen:(UIButton *)sender {
    NSInteger minutes = sender.tag;
    AKBatterySaverSetAFKMinutes(minutes);
    WKLog("ui", @"battery saver: afk saver %ld min", (long)minutes);
    [self render];
}

@end
