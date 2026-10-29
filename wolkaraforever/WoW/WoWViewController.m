#import "WoWViewController.h"
#import "Client.h"
#import "AddonManager.h"
#import "../Voice/VoiceViewController.h"
#import "../Voice/VoiceTestViewController.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WolkaraForeverTheme.h"
#import "../App/WKLocalization.h"
#import "Installation.h"
#import "ForeverUI.h"
#import "Updater.h"
#import "../App/LaunchProgressView.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static UIColor *Gold(void) { return [UIColor colorWithRed:0.88 green:0.73 blue:0.43 alpha:1]; }
// One grey for every row that cannot be used, so a page in a transient state
// reads as one thing instead of a mix of dimmed and full-strength text.
static UIColor *RowGrey(void) { return [UIColor colorWithWhite:0.55 alpha:1]; }
static UIColor *Muted(void) { return [UIColor colorWithRed:0.66 green:0.72 blue:0.78 alpha:1]; }
// The game's download languages, named in the app's own language: a German-speaking user
// choosing what World of Warcraft downloads needs to read the choice, and the row above it
// is the same row in the same language.
static NSString *TKWoWLocaleName(NSString *locale) {
    static NSArray<NSString *> *known; static dispatch_once_t once;
    dispatch_once(&once, ^{ known = @[@"enUS", @"esES", @"deDE"]; });
    return WKLocalized([@"locale." stringByAppendingString:[known containsObject:locale] ? locale : @"enUS"]);
}
static NSString *TKWoWRegionName(NSString *region) {
    static NSArray<NSString *> *known; static dispatch_once_t once;
    dispatch_once(&once, ^{ known = @[@"eu", @"us", @"kr", @"tw"]; });
    return WKLocalized([@"region." stringByAppendingString:[known containsObject:region] ? region : @"eu"]);
}
static UILabel *Label(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label=[UILabel new]; label.numberOfLines=0; label.textColor=color;
    label.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
    label.adjustsFontForContentSizeCategory=YES;
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return label;
}
static UIStackView *Stack(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=spacing; return stack;
}
// The Forever UI file operations are disk work: a backup reads the whole WTF and
// Interface trees, and a restore extracts and checks them. None of it belongs on
// the main thread, so every one runs here and reports back on the main thread.
static dispatch_queue_t TKForeverUIQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("org.tolkara.forever-ui", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
// The touch layout store's key and change notification, by value. The Touch
// module owns both, but WoW must not import it: the layer gate keeps these
// modules apart. Writing the dictionary read-modify-write is what preserves the
// layout's own values, which the store then reads back unchanged.
static NSString *const TKForeverLayoutKey = @"WolkaraForeverTouchLayoutV1";
static NSNotificationName const TKForeverLayoutDidChange = @"AKGamepadLayoutDidChange";


// A settings row that reads as a switch, not as a command: the words stay the
// same and the control says whether it is on. iOS draws the switch; the row only
// supplies the label and the state.
@interface TKWoWSwitchRow : UIView
@property(nonatomic, readonly) UILabel *titleLabel;
@property(nonatomic, readonly) UISwitch *toggle;
@property(nonatomic, getter=isEnabled) BOOL enabled;
- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier
                       target:(id)target action:(SEL)action;
// The words are fixed and the control says the state, so a language change rewrites both
// the label and the switch's own accessibility label with it.
- (void)applyTitle:(NSString *)title;
@end
@implementation TKWoWSwitchRow
- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier
                       target:(id)target action:(SEL)action {
    if ((self=[super initWithFrame:CGRectZero])) {
        self.accessibilityIdentifier=identifier;
        _titleLabel=Label(17,UIFontWeightRegular,UIColor.whiteColor);
        _titleLabel.text=title;
        _titleLabel.accessibilityIdentifier=[identifier stringByAppendingString:@".label"];
        _titleLabel.isAccessibilityElement=NO;
        [_titleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _toggle=[UISwitch new];
        _toggle.onTintColor=Gold();
        _toggle.accessibilityLabel=title;
        _toggle.accessibilityIdentifier=[identifier stringByAppendingString:@".switch"];
        [_toggle addTarget:target action:action forControlEvents:UIControlEventValueChanged];
        [_toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel,_toggle]];
        row.axis=UILayoutConstraintAxisHorizontal;
        row.alignment=UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints=NO;
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            // The same 12-point inset the button rows use, so the switch lines up
            // with their text.
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [row.topAnchor constraintEqualToAnchor:self.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:38],
        ]];
    }
    return self;
}
- (void)setEnabled:(BOOL)enabled {
    _enabled=enabled;
    _toggle.enabled=enabled;
    // The label follows the row, and the control only shows its own off/on
    // colour: no alpha on the row, which used to make an enabled switch look
    // the same as a disabled one. Gold is what every other usable row uses, so
    // an on/off row reads like the buttons above and below it.
    _titleLabel.textColor=enabled?Gold():RowGrey();
}
- (void)applyTitle:(NSString *)title {
    _titleLabel.text=title;
    _toggle.accessibilityLabel=title;
}
@end

@interface TKWoWViewController () <UIDocumentPickerDelegate>
@end

@implementation TKWoWViewController {
    TKAppLibrary *_library;
    TKWoWClient *_client;
    NSDictionary *_product, *_plan;
    TKWoWInstallation *_installation;
    NSString *_region, *_locale;
    NSError *_error;
    NSDate *_checkedAt;
    NSUInteger _generation;
    BOOL _busy, _updating, _updateError, _starting, _running;
    // A Forever UI file operation is running (backup, reset, restore, gamepad).
    // The rows are disabled while it runs and every handler rechecks it.
    BOOL _uiOperation;
    BOOL _gamepadEnabled, _overlayEnabled;
    // The game files are read once, when the launcher first appears. Not on every
    // appearance: leaving a popup used to send us straight back to the network.
    BOOL _checkedThisLaunch;
    NSString *_startupFailure;
    UILabel *_updatesLabel;
    NSString *_updatePhase;
    uint64_t _updateDone, _updateTotal;
    UIProgressView *_progressBar;
    CAGradientLayer *_background;
    UIStackView *_columns;
    NSLayoutConstraint *_markWidth;
    UIStackView *_gridRow1, *_gridRow2;
    UILabel *_stateLabel, *_detailLabel, *_versionLabel, *_startupLabel, *_compatibilityLabel;
    UIButton *_editionButton, *_preferencesButton, *_languageButton, *_addonsButton, *_addonsDirectoryButton,
        *_voiceButton, *_voiceTestButton, *_permissionsButton, *_primaryButton,
        *_macEverButton, *_backupButton, *_resetButton, *_restoreButton, *_settingsFolderButton,
        *_renderProfileButton;
    // The section headings, by their box's identifier, so a language change can rewrite
    // them where they were made instead of rebuilding the page.
    NSMutableDictionary<NSString *, UILabel *> *_headings;
    TKWoWSwitchRow *_gamepadRow, *_overlayRow;
    NSString *_backupsDirectory;
    UIView *_markView;
    NSLayoutConstraint *_markCap;
    UIBarButtonItem *_refreshItem;
    UIActivityIndicatorView *_activity;
}
- (instancetype)initWithLibrary:(TKAppLibrary *)library {
    if (!(self=[super initWithNibName:nil bundle:nil])) return nil;
    _library=library; self.title=@"";
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    _product=TKWoWProducts()[0];
    for (NSDictionary *p in TKWoWProducts()) if ([p[@"id"] isEqual:[defaults stringForKey:@"WoWProduct"]]) _product=p;
    _region=[defaults stringForKey:@"WoWRegion"]?:@"eu";
    if (![@[@"eu",@"us",@"kr",@"tw"] containsObject:_region]) _region=@"eu";
    _locale=[defaults stringForKey:@"WoWLocale"]?:@"enUS";
    if (![@[@"enUS",@"esES",@"deDE"] containsObject:_locale]) _locale=@"enUS";
    return self;
}
- (UIButton *)button:(NSString *)identifier action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityIdentifier=identifier;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
// The page's own section heading: the small uppercase label the edition line
// always used, now naming each group of rows.
- (UILabel *)heading:(NSString *)text {
    UILabel *label=Label(17,UIFontWeightSemibold,Muted());
    label.text=text.uppercaseString;
    return label;
}
// One section, in its own box: the heading and its rows share a panel with the
// page's own border and fill, so the eye can find a group without a long column
// of loose rows. The heading's words come from -localize, which is also what a
// language change runs, so the heading follows the app language like every other
// label on the page.
- (UIView *)sectionBoxWithIdentifier:(NSString *)identifier rows:(NSArray<UIView *> *)rows {
    UIView *box=[UIView new];
    box.accessibilityIdentifier=identifier;
    box.translatesAutoresizingMaskIntoConstraints=NO;
    box.backgroundColor=[UIColor colorWithRed:0.055 green:0.085 blue:0.125 alpha:1];
    box.layer.cornerRadius=14;
    box.layer.borderWidth=1;
    box.layer.borderColor=[Gold() colorWithAlphaComponent:0.18].CGColor;
    UILabel *heading=[self heading:@""];
    heading.accessibilityIdentifier=[identifier stringByReplacingOccurrencesOfString:@"wow.box."
                                                                          withString:@"wow.heading."];
    if (!_headings) _headings=[NSMutableDictionary new];
    _headings[identifier]=heading;
    UIStackView *stack=Stack([@[heading] arrayByAddingObjectsFromArray:rows],8);
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    // A box in the taller row is stretched to match its neighbour; without a
    // spacer the extra height would be shared out among the rows and drift them
    // apart. The spacer takes all of it, so the rows stay together at the top.
    UIView *spacer=[UIView new];
    spacer.accessibilityIdentifier=@"wow.box.spacer";
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [spacer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [stack addArrangedSubview:spacer];
    [box addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-14],
    ]];
    return box;
}
// Two boxes side by side on a wide screen, stacked when there is no room.
- (UIStackView *)boxRow:(NSArray<UIView *> *)boxes {
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:boxes];
    row.axis=UILayoutConstraintAxisHorizontal;
    row.distribution=UIStackViewDistributionFillEqually;
    row.alignment=UIStackViewAlignmentFill;
    row.spacing=16;
    return row;
}
// The layer's mark, where the wordmark used to sit. It is drawn at the top
// row's width, so it grows and shrinks with the window, with one cap: it may
// never take more than a fifth of the height, so the boxes below it always have
// room. The aspect constraint is optional for that reason — when the cap
// applies, the picture letterboxes rather than fighting the column's width.
//
// The cap spans this view and the controller's, so it can only be activated once
// the two share an ancestor. Here the picture is still unattached, and UIKit
// raises "no common ancestor" for exactly that — which aborts the app at launch,
// measured on 2026-10-16. The cap is therefore kept and switched on from
// -viewDidLayoutSubviews, by which time the column has been added to the scroll
// view.
- (UIView *)markView {
    UIImage *image=[UIImage imageNamed:@"WolkaraForeverLogo"];
    if (image) {
        UIImageView *view=[[UIImageView alloc] initWithImage:image];
        view.contentMode=UIViewContentModeScaleAspectFit;
        view.accessibilityIdentifier=@"wow.logo";
        view.accessibilityLabel=@"WolkaraForever";
        // The picture's own pixel size is far larger than the column, so its
        // intrinsic size must not be allowed to argue with the constraints below.
        [view setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
        [view setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
        NSLayoutConstraint *aspect=[view.widthAnchor constraintEqualToAnchor:view.heightAnchor
            multiplier:image.size.width/image.size.height];
        aspect.priority=999;
        aspect.active=YES;
        _markCap=[view.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor
            multiplier:0.20];
        return view;
    }
    // No artwork in this build: say the name rather than show an empty gap.
    UILabel *label=Label(37,UIFontWeightBold,Gold()); label.text=@"WOLKAREFOREVER";
    label.numberOfLines=1;
    label.adjustsFontSizeToFitWidth=YES;
    label.minimumScaleFactor=0.45;
    UIFontDescriptor *serif=[[UIFont systemFontOfSize:37 weight:UIFontWeightBold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
    if (serif) label.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:[UIFont fontWithDescriptor:serif size:37]];
    label.accessibilityIdentifier=@"wow.title";
    return label;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=[UIColor colorWithRed:0.025 green:0.045 blue:0.075 alpha:1];
    _background=[CAGradientLayer layer];
    _background.colors=@[(id)[UIColor colorWithRed:0.035 green:0.085 blue:0.13 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.03 blue:0.055 alpha:1].CGColor];
    _background.startPoint=CGPointMake(0,0); _background.endPoint=CGPointMake(1,1);
    [self.view.layer insertSublayer:_background atIndex:0];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
        style:UIBarButtonItemStylePlain target:self action:@selector(settings)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"wow.settings";
    _refreshItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
        style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    _refreshItem.accessibilityIdentifier=@"wow.refresh";
    self.navigationItem.leftBarButtonItem=_refreshItem;

    // Identity and the play surface share the top of the page; the four
    // sections sit in boxes underneath both, so the whole page fits without
    // scrolling on an iPad instead of a column that has to be scrolled.
    _markView=[self markView];
    _editionButton=[self button:@"wow.edition" action:@selector(chooseEdition)];
    _preferencesButton=[self button:@"wow.preferences" action:@selector(preferences)];
    // The app's own language, beside the game's. Separate rows on purpose: one changes
    // WolkaraForever's labels, the other changes what World of Warcraft downloads, and a
    // single row for both would be the exact confusion this page has to avoid.
    _languageButton=[self button:@"wow.language" action:@selector(chooseAppLanguage)];
    _addonsButton=[self button:@"wow.addons.manage" action:@selector(manageAddons)];
    // Mac-Ever is a Forever-compatible add-on that is downloaded from CurseForge
    // by the person using Safari, then installed with the row above. No scrape,
    // no embedded download URL, and opening the page is not an installation.
    _macEverButton=[self button:@"wow.addons.macEver" action:@selector(downloadMacEver)];
    _addonsDirectoryButton=[self button:@"wow.addons.directory" action:@selector(openAddonDirectory)];
    // Straight to this app's own page in Settings, which is where the Microphone and Speech Recognition
    // switches live. Available before the game is installed, because it is a setting and not a game
    // action - and it is the only place those switches can be changed.
    _permissionsButton=[self button:@"wow.permissions" action:@selector(openPermissions)];
    _voiceButton=[self button:@"wow.voice" action:@selector(manageVoice)];
    _voiceTestButton=[self button:@"wow.voice.test" action:@selector(testVoice)];
    _compatibilityLabel=Label(17,UIFontWeightRegular,Muted());
    _backupButton=[self button:@"wow.performance.backup" action:@selector(backupUI)];
    _resetButton=[self button:@"wow.performance.reset" action:@selector(resetGraphics)];
    _restoreButton=[self button:@"wow.performance.restore" action:@selector(restoreUI)];
    _gamepadRow=[[TKWoWSwitchRow alloc] initWithTitle:@"" identifier:@"wow.performance.gamepad"
        target:self action:@selector(gamepadChanged:)];
    _overlayRow=[[TKWoWSwitchRow alloc] initWithTitle:@"" identifier:@"wow.performance.overlay"
        target:self action:@selector(overlayChanged:)];
    _renderProfileButton=[self button:@"wow.performance.renderProfile" action:@selector(chooseRenderProfile)];
    _settingsFolderButton=[self button:@"wow.performance.settingsFolder" action:@selector(openSettingsFolder)];

    // The four sections, as boxes. Their order is the order they are read in.
    // The compatibility note belongs to the edition it is about, so it lives in
    // that box rather than loose on the page. Every word in them comes from
    // -localize, below, which is also what a language change runs.
    UIView *editionBox=[self sectionBoxWithIdentifier:@"wow.box.edition"
        rows:@[_editionButton,_preferencesButton,_languageButton,_compatibilityLabel]];
    UIView *addonsBox=[self sectionBoxWithIdentifier:@"wow.box.addons"
        rows:@[_addonsButton,_macEverButton,_addonsDirectoryButton]];
    UIView *voiceBox=[self sectionBoxWithIdentifier:@"wow.box.voice"
        rows:@[_permissionsButton,_voiceButton,_voiceTestButton]];
    UIView *performanceBox=[self sectionBoxWithIdentifier:@"wow.box.performance"
        rows:@[_renderProfileButton,_backupButton,_resetButton,_restoreButton,_settingsFolderButton,_gamepadRow,_overlayRow]];

    _activity=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _activity.color=Gold(); _activity.hidesWhenStopped=YES;
    _stateLabel=Label(17,UIFontWeightSemibold,UIColor.whiteColor); _stateLabel.accessibilityIdentifier=@"wow.status";
    UIStackView *stateRow=[[UIStackView alloc] initWithArrangedSubviews:@[_activity,_stateLabel]];
    stateRow.axis=UILayoutConstraintAxisHorizontal; stateRow.spacing=10;
    // A hidden activity indicator retains its 20pt intrinsic height. Center
    // it rather than stretching/compressing both views to that same height.
    stateRow.alignment=UIStackViewAlignmentCenter;
    [_activity setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    _detailLabel=Label(17,UIFontWeightRegular,Muted()); _detailLabel.accessibilityIdentifier=@"wow.detail";
    _versionLabel=Label(17,UIFontWeightRegular,Muted()); _versionLabel.accessibilityIdentifier=@"wow.version";
    _progressBar=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressBar.progressTintColor=Gold(); _progressBar.accessibilityIdentifier=@"wow.progress";
    _launchProgress=[TKLaunchProgressView new];
    _launchProgress.accessibilityIdentifier=@"wow.elapsed";
    _diagnosticsButton=[self button:@"wow.diagnostics" action:@selector(diagnostics)];
    _diagnosticsButton.tintColor=Gold(); _diagnosticsButton.hidden=YES;
    UIStackView *status=Stack(@[stateRow,_detailLabel,_progressBar,_launchProgress,_versionLabel,_diagnosticsButton],10);
    status.layoutMargins=UIEdgeInsetsMake(20,20,20,20); status.layoutMarginsRelativeArrangement=YES;
    status.backgroundColor=[UIColor colorWithRed:0.07 green:0.105 blue:0.15 alpha:1];
    status.layer.cornerRadius=16; status.layer.borderWidth=1;
    status.layer.borderColor=[Gold() colorWithAlphaComponent:0.24].CGColor;
    _primaryButton=[self button:@"wow.primary" action:@selector(primaryAction)];
    [_primaryButton.heightAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;
    _updatesLabel=Label(17,UIFontWeightRegular,Muted()); _updatesLabel.accessibilityIdentifier=@"wow.updates";
    _startupLabel=Label(17,UIFontWeightRegular,Muted()); _startupLabel.accessibilityIdentifier=@"wow.startup";
    UIStackView *right=Stack(@[status,_primaryButton,_updatesLabel,_startupLabel],12);
    // The top of the page: the mark on the left, what the launcher is doing and
    // the Play button on the right. The boxes go underneath both.
    UIStackView *top=[[UIStackView alloc] initWithArrangedSubviews:@[_markView,right]];
    top.axis=UILayoutConstraintAxisHorizontal; top.spacing=28; top.alignment=UIStackViewAlignmentTop;
    top.accessibilityIdentifier=@"wow.top";
    _markWidth=[_markView.widthAnchor constraintEqualToAnchor:top.widthAnchor multiplier:0.30];
    _markWidth.active=YES;
    _gridRow1=[self boxRow:@[editionBox,addonsBox]];
    _gridRow2=[self boxRow:@[voiceBox,performanceBox]];
    UIStackView *grid=Stack(@[_gridRow1,_gridRow2],16);
    grid.accessibilityIdentifier=@"wow.grid";
    _columns=Stack(@[top,grid],20); _columns.accessibilityIdentifier=@"wow.columns";
    _columns.alignment=UIStackViewAlignmentFill;

    UIScrollView *scroll=[UIScrollView new]; scroll.accessibilityIdentifier=@"wow.scroll";
    scroll.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:scroll];
    _columns.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:_columns];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_columns.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [_columns.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [_columns.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
        [_columns.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
        [_columns.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48]
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:)
        name:UIApplicationWillResignActiveNotification object:nil];
    // The app language can change from this page's own row, so the page rewrites its words
    // where they are instead of being rebuilt: the game-file check it has already done and
    // the installation it is showing stay exactly as they were.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appLanguageChanged:)
        name:WKLocalizationDidChangeNotification object:nil];
    [self localize];
    [self render];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new]; [appearance configureWithOpaqueBackground];
    appearance.backgroundColor=[UIColor colorWithRed:0.025 green:0.045 blue:0.075 alpha:1];
    appearance.titleTextAttributes=@{NSForegroundColorAttributeName:Gold()};
    self.navigationItem.standardAppearance=appearance; self.navigationItem.scrollEdgeAppearance=appearance;
    self.navigationItem.compactAppearance=appearance;
    self.navigationController.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.navigationController.navigationBar.prefersLargeTitles=NO;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.navigationController.navigationBar.tintColor=Gold();
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _background.frame=self.view.bounds;
    // The mark's height cap was made in -markView, before the picture had a
    // superview. Now it does, so the two ends have an ancestor and it can be
    // switched on; once only, because switching it on lays out again.
    if (_markCap && !_markCap.active) _markCap.active=YES;
    BOOL horizontal=self.view.bounds.size.width>=700 && !UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    // Two boxes side by side when there is room, one column otherwise. The page
    // itself is always a single vertical column, and the boxes keep their order.
    _gridRow1.axis=horizontal?UILayoutConstraintAxisHorizontal:UILayoutConstraintAxisVertical;
    _gridRow2.axis=_gridRow1.axis;
    _gridRow1.distribution=horizontal?UIStackViewDistributionFillEqually:UIStackViewDistributionFill;
    _gridRow2.distribution=_gridRow1.distribution;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Once per launch, and not again. This used to run on every appearance, so
    // closing the add-on or the voice popup sent the launcher back for a full
    // manifest check and the home page sat busy again - every single time, for a
    // page the user had only looked at. The refresh button and Try again still ask
    // for a check on purpose, and that is now the only way to get a second one.
    if (_checkedThisLaunch || _busy || _sessionUsed || _starting) return;
    _checkedThisLaunch=YES;
    WKLog("ui", @"home: first appearance, checking the game files");
    [self refresh];
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self cancel]; }
- (void)foreground:(NSNotification *)note {
    (void)note;
    // Deliberately no check here. Coming back to the app is not a reason to re-read
    // every manifest, and the check above has already happened for this launch.
    WKLog("ui", @"home: back in front");
}
- (void)background:(NSNotification *)note { (void)note; [self cancel]; }
- (void)cancel { [_client cancel]; _client=nil; _generation++; _busy=NO; }
- (void)setExecutionMode:(TKExecutionMode)mode { _executionMode=mode; if (self.isViewLoaded) [self render]; }
- (void)setSessionUsed:(BOOL)used { _sessionUsed=used; if (used) { _running=NO; [self cancel]; } if (self.isViewLoaded) [self render]; }
- (void)selectProduct:(NSDictionary *)product {
    if (_starting || _sessionUsed) return;
    if (![TKWoWProducts() containsObject:product]) return;
    _product=product;
    [NSUserDefaults.standardUserDefaults setObject:product[@"id"] forKey:@"WoWProduct"];
    [self refresh];
}
- (void)refresh {
    // Asked for on purpose: the refresh button, Try again, or a changed edition.
    // The check that happens by itself runs once per launch; see -viewDidAppear:.
    WKLog("wow", @"a check was asked for");
    [self checkForUpdatesAndLaunch:NO];
}
- (void)checkForUpdatesAndLaunch:(BOOL)launch { [self checkForUpdatesAndLaunch:launch install:NO]; }
- (void)checkForUpdatesAndLaunch:(BOOL)launch install:(BOOL)install {
    if (_starting || _sessionUsed) return;
    NSString *installKey=[@"WoWInstallRequested." stringByAppendingString:_product[@"id"]];
    NSString *repairKey=[@"WoWRepairRequested." stringByAppendingString:_product[@"id"]];
    if(install && _installation.state==TKWoWInstallationNeedsRepair)
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:repairKey];
    if(install)[NSUserDefaults.standardUserDefaults setBool:YES forKey:installKey];
    install=install || [NSUserDefaults.standardUserDefaults boolForKey:installKey];
    BOOL repair=[NSUserDefaults.standardUserDefaults boolForKey:repairKey];
    [self cancel]; _plan=nil; _installation=nil; _error=nil; _checkedAt=nil; _startupFailure=nil;
    _updating=NO; _updateError=NO; _updatePhase=nil; _updateDone=0; _updateTotal=0;
    _client=[TKWoWClient new]; _busy=YES; [self render];
    WKLog("wow", @"checking %@ %@/%@ install=%d launch=%d", _product[@"id"], _region, _locale, install, launch);
    TKWoWClient *client=_client; NSUInteger generation=_generation;
    NSDictionary *product=_product; NSString *region=_region, *locale=_locale;
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once,^{ queue=dispatch_queue_create("org.tolkara.wow-updates",DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue,^{
        [self->_library discover];
        NSError *error=nil;
        NSDictionary *plan=[client planForProduct:product[@"id"] region:region locale:locale error:&error];
        TKWoWInstallation *installation=plan?TKWoWInspectInstallation(self->_library,product,plan):nil;
        BOOL updateAttempted=plan && (install || installation.state==TKWoWInstallationOutdated) && !client.cancelled;
        if(updateAttempted) {
            __block NSString *lastPhase=nil;
            void (^progress)(NSString *,uint64_t,uint64_t)=^(NSString *phase,uint64_t done,uint64_t total) {
                if(![lastPhase isEqual:phase]) {
                    lastPhase=phase;NSLog(@"[wow-update] Phase: %@",phase);
                }
                dispatch_async(dispatch_get_main_queue(),^{
                    if(generation!=self->_generation)return;
                    self->_plan=plan;self->_installation=installation;self->_updating=YES;
                    self->_updatePhase=phase;self->_updateDone=done;self->_updateTotal=total;[self render];
                });
            };
            progress(@"snapshot",0,0);
            NSString *directory=installation.app?[self->_library workingDirectoryForApp:installation.app error:&error]:nil;
            NSString *root=directory?directory.stringByDeletingLastPathComponent:
                [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"World of Warcraft"];
            TKWoWUpdater *updater=[[TKWoWUpdater alloc] initWithClient:client];
            updater.fullVerification=repair;
            if([updater updatePlan:plan root:root progress:progress error:&error]) {
                [self->_library discover];installation=TKWoWInspectInstallation(self->_library,product,plan);error=nil;
                // Editions without a bundled compatibility profile still need a
                // library entry after their first download. Register only the
                // original executable already verified by the install manifest.
                if(installation.state==TKWoWInstallationMissing) {
                    NSMutableArray *executables=[NSMutableArray new];
                    for(NSDictionary *file in plan[@"files"])if([file[@"path"] hasSuffix:@".app/Contents/MacOS/World of Warcraft"])
                        [executables addObject:[[root stringByAppendingPathComponent:product[@"folder"]] stringByAppendingPathComponent:file[@"path"]]];
                    if(executables.count==1 && [self->_library importExecutable:executables[0] copy:NO error:&error])
                        installation=TKWoWInspectInstallation(self->_library,product,plan);
                }
                if(installation.state==TKWoWInstallationReady) {
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:installKey];
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:repairKey];
                }
                else error=error?:installation.error?:TKWoWError(@"The downloaded installation could not be registered in the library.");
            }
            if(error)NSLog(@"[wow-update] Interrupted during %@: %@ (%@:%ld)",lastPhase?:@"preparation",
                error.localizedDescription,error.domain,(long)error.code);
            NSLog(@"[wow-update] Verification bytes read=%llu reused=%llu",updater.verificationBytesRead,updater.verificationBytesReused);
        }

        // Before the home page is exposed again: finish or roll back a restore
        // that a previous launch interrupted. This is the one place that runs
        // early enough to be ahead of the page, and it runs only for Forever.
        if(installation.state==TKWoWInstallationReady && installation.app &&
           [self->_product[@"id"] isEqual:TKForeverUIEdition]) {
            NSString *directory=[self->_library workingDirectoryForApp:installation.app error:NULL];
            if(directory && ![TKForeverUI recoverInterruptedRestoreInWorkingDirectory:directory error:NULL])
                NSLog(@"[wow-ui] an interrupted restore could not be resolved; the game files were left as they were");
        }
        dispatch_async(dispatch_get_main_queue(),^{
            if (generation!=self->_generation) return;
            self->_plan=plan; self->_installation=installation; self->_error=error;
            self->_checkedAt=plan?NSDate.date:nil; self->_busy=NO; self->_updating=NO; self->_updateError=updateAttempted && error; [self render];
            WKLog("wow", @"checked: state=%ld error=%@", (long)installation.state, error.localizedDescription ?: @"none");
            // Returning from the background or changing edition invalidates this request.
            if (launch && !error && !client.cancelled && installation.state==TKWoWInstallationReady && installation.app && !self->_sessionUsed &&
                self.view.window && self.navigationController.topViewController==self && self.startApp) self.startApp(installation.app);
        });
    });
}
- (void)primaryAction {
    // Starting and running own the button; nothing else may close or start.
    if (_starting || _running) return;
    // After a session the only useful action is to leave: this process cannot
    // start a second guest, and the user must be able to close it from here.
    if (_sessionUsed) { [self closeApp]; return; }
    if (_busy) return;
    if (_startupFailure) { _startupFailure=nil; [self render]; }
    if (_error || !_plan) { [self refresh]; return; }
    if (_installation.state==TKWoWInstallationMissing || _installation.state==TKWoWInstallationNeedsRepair) {
        [self checkForUpdatesAndLaunch:NO install:YES];return;
    }
    if (_installation.state!=TKWoWInstallationReady) return;
    if (_executionMode==TKExecutionModeNone) return;
    [self checkForUpdatesAndLaunch:YES];
}
- (void)repairInstallation {
    if(_busy || _starting || _sessionUsed || !_installation.app)return;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"WoWRepairRequested." stringByAppendingString:_product[@"id"]]];
    [self checkForUpdatesAndLaunch:NO install:YES];
}
- (void)configureButton:(UIButton *)button title:(NSString *)title filled:(BOOL)filled {
    UIButtonConfiguration *configuration=filled?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.plainButtonConfiguration;
    configuration.title=title; configuration.cornerStyle=UIButtonConfigurationCornerStyleMedium;
    configuration.baseBackgroundColor=Gold(); configuration.baseForegroundColor=filled?[UIColor colorWithRed:0.08 green:0.065 blue:0.035 alpha:1]:Gold();
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(filled?14:8,12,filled?14:8,12);
    button.configuration=configuration;
    [button setTitle:title forState:UIControlStateNormal];
}
// Disabled rows use one explicit grey rather than the system's dimming, so a
// starting page, a session page and an ended session all read the same.
- (void)stylePlainButton:(UIButton *)button {
    UIButtonConfiguration *configuration=button.configuration;
    configuration.baseForegroundColor=button.enabled?Gold():RowGrey();
    button.configuration=configuration;
}
- (void)stylePrimaryButton {
    UIButtonConfiguration *configuration=_primaryButton.configuration;
    BOOL enabled=_primaryButton.enabled;
    configuration.baseBackgroundColor=enabled?Gold():[UIColor colorWithWhite:0.28 alpha:1];
    configuration.baseForegroundColor=enabled?[UIColor colorWithRed:0.08 green:0.065 blue:0.035 alpha:1]:[UIColor colorWithWhite:0.62 alpha:1];
    _primaryButton.configuration=configuration;
}
// Every fixed word on the page, in the app's language, in one place. Called once when the
// page is built and again whenever the language changes: labels set in -viewDidLoad alone
// were the shape of bug that leaves half a page in the old language, and a language the
// user chose has to apply without a relaunch.
//
// The rows whose words change with the installation itself (the Game language row, the
// Play button, the status line) are not here: -render owns those, and every path that
// changes the language runs it.
- (void)localize {
    WKLocalization *localization=WKLocalization.shared;
    WKLog("language", @"home: drawing the page in %@ (%@)", localization.languageCode, localization.settingDisplayName);
    self.navigationItem.rightBarButtonItem.accessibilityLabel=WKLocalized(@"home.settings");
    self.navigationItem.backButtonTitle=WKLocalized(@"common.back");
    _refreshItem.accessibilityLabel=WKLocalized(@"home.refresh");
    _headings[@"wow.box.edition"].text=WKLocalized(@"home.box.edition").uppercaseString;
    _headings[@"wow.box.addons"].text=WKLocalized(@"home.box.addons").uppercaseString;
    _headings[@"wow.box.voice"].text=WKLocalized(@"home.box.voice").uppercaseString;
    _headings[@"wow.box.performance"].text=WKLocalized(@"home.box.performance").uppercaseString;
    [_gamepadRow applyTitle:WKLocalized(@"home.performance.gamepad")];
    [_overlayRow applyTitle:WKLocalized(@"home.performance.overlay")];
    [_diagnosticsButton setTitle:WKLocalized(@"home.diagnostics") forState:UIControlStateNormal];
    _updatesLabel.text=WKLocalized(@"home.updates.note");
    // A VoiceOver reader is told the language of the words it is about to read, so a German
    // page is read with German pronunciation instead of an English voice over German text.
    self.view.accessibilityLanguage=localization.languageCode;
}
- (void)appLanguageChanged:(NSNotification *)note {
    (void)note;
    [self localize];
    [self render];
}
// The app's own language. The choice is English, German, or follow the iPad; the row above
// it is the *game's* language and is a different setting entirely, which the sheet says.
- (void)chooseAppLanguage {
    WKLocalization *localization=WKLocalization.shared;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"lang.title")
        message:WKLocalized(@"lang.message") preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *each in WKLocalization.choices) {
        WKAppLanguage language=each.integerValue;
        // The two languages are named in themselves - a language is the one word a person
        // is most likely to recognise - and only the "follow the iPad" choice is translated.
        NSString *title=language==WKAppLanguageSystem
            ? [NSString stringWithFormat:@"%@ (%@)", WKLocalized(@"lang.system"), localization.resolvedLanguageName]
            : (language==WKAppLanguageGerman?@"Deutsch":@"English");
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            [self applyAppLanguage:language];
        }]];
    }
    [self presentSheet:sheet anchor:_languageButton];
}
- (void)applyAppLanguage:(WKAppLanguage)language {
    WKLocalization *localization=WKLocalization.shared;
    if (localization.language==language) return;
    WKLog("language", @"the user chose %@", [WKLocalization storedValueForLanguage:language]);
    localization.language=language;      // persists, and posts; -appLanguageChanged: redraws
    // This runs inside the sheet's own action handler, so the sheet is dismissing as it does.
    // -presentSheet: waits for that; the log line says so when the wait is what happened.
    [self offerGermanGameLanguage];
}
// The first time the app is put into German, offer to put the *game* into German too -
// rather than doing it silently, because the two settings cost different things: this one
// is a redraw, that one is a multi-gigabyte download. Once offered, never offered again;
// the Game language row is always there for a later change of mind.
- (void)offerGermanGameLanguage {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if (WKLocalization.shared.resolvedLanguage!=WKAppLanguageGerman) return;
    if ([_locale isEqual:@"deDE"]) return;
    if ([defaults boolForKey:@"WolkaraForeverGameLanguageOfferShown"]) return;
    [defaults setBool:YES forKey:@"WolkaraForeverGameLanguageOfferShown"];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"lang.confirm.title")
        message:WKLocalized(@"lang.confirm.message") preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"lang.confirm.yes") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self setGameLocale:@"deDE"];
        [self presentMessage:WKLocalized(@"lang.gameChanged.title") message:WKLocalized(@"lang.confirm.changed")];
    }]];
    // Declining is an answer, not a cancellation: the app language stays German, and only
    // the download is left alone.
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"lang.confirm.no") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet anchor:_languageButton];
}
- (void)render {
    if (!self.isViewLoaded) return;
    [self configureButton:_editionButton title:[_product[@"name"] stringByAppendingString:@"  ▾"] filled:NO];
    _editionButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _editionButton.backgroundColor=[UIColor colorWithWhite:1 alpha:0.055]; _editionButton.layer.cornerRadius=10;
    [self configureButton:_preferencesButton title:[NSString stringWithFormat:@"%@  ·  %@  ▾",_region.uppercaseString,TKWoWLocaleName(_locale)] filled:NO];
    _preferencesButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    // The app's own language. It reads in the same shape as the row above so the two are
    // seen as the two settings they are, and it says which language is in use rather than
    // which of the three choices was made - the sheet says that.
    [self configureButton:_languageButton title:WKLocalizedFormat(@"lang.row",WKLocalization.shared.settingDisplayName) filled:NO];
    _languageButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    [self configureButton:_addonsButton title:_installation.app?WKLocalized(@"home.addons.install"):WKLocalized(@"home.addons.install.needsgame") filled:NO];
    _addonsButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _addonsButton.enabled=_installation.app && !_busy && !_starting && !_running && !_sessionUsed;
    [self configureButton:_macEverButton title:WKLocalized(@"home.addons.macever") filled:NO];
    _macEverButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    // Navigation only: the page is opened for the user to download the ZIP.
    // Starting and an ended session grey it with everything else.
    _macEverButton.enabled=!_starting && !_running && !_sessionUsed;
    [self configureButton:_addonsDirectoryButton title:_installation.app?WKLocalized(@"home.addons.directory"):WKLocalized(@"home.addons.directory.needsgame") filled:NO];
    _addonsDirectoryButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _addonsDirectoryButton.enabled=_addonsButton.enabled;
    [self configureButton:_voiceButton title:WKLocalized(@"home.voice.keys") filled:NO];
    _voiceButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    // Available before the game is installed: it is a setting, not a game action.
    _voiceButton.enabled=!_busy && !_starting && !_running && !_sessionUsed;
    [self configureButton:_voiceTestButton title:WKLocalized(@"home.voice.test") filled:NO];
    _voiceTestButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _voiceTestButton.enabled=_voiceButton.enabled;
    [self configureButton:_permissionsButton title:WKLocalized(@"home.permissions") filled:NO];
    _permissionsButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    // Navigation to Settings is available whenever the page is usable; a
    // starting or ended session greys it with the rest so no gold text is left.
    _permissionsButton.enabled=!_starting && !_running && !_sessionUsed;
    // Performance & UI Manager. The Forever file rows need a ready Forever
    // installation - and the selected edition must be Forever, because they must
    // never read or write another edition's files - no download, start or
    // session, and no other UI operation in flight. The overlay is a
    // WolkaraForever runtime feature and follows the launcher's non-busy rule.
    NSString *foreverDirectory=[self foreverWorkingDirectory];
    BOOL foreverReady=foreverDirectory && !_busy && !_starting && !_running && !_sessionUsed && !_uiOperation;
    _gamepadEnabled=foreverDirectory?[TKForeverUI gamepadEnabledInWorkingDirectory:foreverDirectory]:NO;
    NSDictionary *layout=[NSUserDefaults.standardUserDefaults objectForKey:TKForeverLayoutKey];
    _overlayEnabled=[layout isKindOfClass:NSDictionary.class] && [layout[@"performanceOverlayEnabled"] boolValue];
    for (UIButton *button in @[_backupButton,_resetButton,_restoreButton,_settingsFolderButton]) {
        button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
        button.enabled=foreverReady;
    }
    [self configureButton:_backupButton title:WKLocalized(@"home.performance.backup") filled:NO];
    [self configureButton:_resetButton title:WKLocalized(@"home.performance.reset") filled:NO];
    [self configureButton:_restoreButton title:WKLocalized(@"home.performance.restore") filled:NO];
    [self configureButton:_settingsFolderButton title:WKLocalized(@"home.performance.settingsFolder") filled:NO];
    // Switches, not changing commands: the label is fixed and the control shows
    // the state.
    _gamepadRow.enabled=foreverReady;
    _gamepadRow.toggle.on=_gamepadEnabled;
    _overlayRow.enabled=!_busy && !_starting && !_running && !_sessionUsed;
    _overlayRow.toggle.on=_overlayEnabled;
    NSNumber *scale=[NSUserDefaults.standardUserDefaults objectForKey:@"WolkaraForeverBackingScale"];
    CGFloat renderScale=scale ? scale.doubleValue : 1.0;
    NSString *profile=renderScale<=0.75 ? WKLocalized(@"home.render.performance")
        : renderScale>=2.0 ? WKLocalized(@"home.render.quality") : WKLocalized(@"home.render.balanced");
    [self configureButton:_renderProfileButton title:WKLocalizedFormat(@"home.performance.renderProfile",profile) filled:NO];
    _renderProfileButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    _renderProfileButton.enabled=!_busy && !_starting && !_running && !_sessionUsed;
    _compatibilityLabel.text=([_product[@"id"] isEqual:@"wow"] || [_product[@"id"] isEqual:@"wow_beta"] || [_product[@"id"] isEqual:@"wow_classic"])?
        WKLocalized(@"home.compatibility.unverified"):
        @"";
    _compatibilityLabel.hidden=!_compatibilityLabel.text.length;
    _editionButton.enabled=!_busy && !_starting && !_running && !_sessionUsed;
    _preferencesButton.enabled=_editionButton.enabled;
    _languageButton.enabled=_editionButton.enabled;
    self.navigationItem.rightBarButtonItem.enabled=!_updating && !_starting && !_running;
    _primaryButton.hidden=_starting || _running;
    _updatesLabel.hidden=_starting || _running;
    _startupLabel.hidden=_starting || _running;
    _progressBar.hidden=!_updating || !_updateTotal;
    _progressBar.progress=_updateTotal?(float)((double)_updateDone/_updateTotal):0;
    NSString *title=nil, *detail=nil, *action=nil;
    BOOL enabled=NO;
    if (_running) {
        title=WKLocalized(@"home.status.running");
        detail=WKLocalized(@"home.status.running.detail");
        action=WKLocalized(@"home.status.running");
    } else if (_starting) {
        title=WKLocalized(@"home.status.starting");
        detail=_detailLabel.text.length?_detailLabel.text:WKLocalized(@"home.status.starting.detail");
        action=WKLocalized(@"home.status.starting");
    } else if (_startupFailure) {
        title=WKLocalized(@"home.status.failed");
        if (_sessionUsed) {
            detail=WKLocalized(@"home.status.failed.session");
            action=WKLocalized(@"home.action.close"); enabled=YES;
        } else {
            detail=WKLocalized(@"home.status.failed.retry");
            action=WKLocalized(@"home.action.retry"); enabled=YES;
        }
    } else if (_sessionUsed) {
        title=WKLocalized(@"home.status.closed");
        detail=WKLocalized(@"home.status.closed.detail");
        action=WKLocalized(@"home.action.close"); enabled=YES;
    } else if (_busy && _updating) {
        title=WKLocalized(@"home.status.updating");
        // The updater reports these phase names and they stay English: they are log keys,
        // matched in the device matrix, and only the words beside them are translated.
        NSDictionary *phases=@{@"snapshot":WKLocalized(@"home.phase.snapshot"),
            @"manifests":WKLocalized(@"home.phase.manifests"),
            @"verify":WKLocalized(@"home.phase.verify"),
            @"reuse":WKLocalized(@"home.phase.reuse"),
            @"indices":WKLocalized(@"home.phase.indices"),
            @"download":WKLocalized(@"home.phase.download"),
            @"files":WKLocalized(@"home.phase.files"),
            @"activate":WKLocalized(@"home.phase.activate"),
            @"complete":WKLocalized(@"home.phase.complete")};
        detail=phases[_updatePhase]?:WKLocalized(@"home.phase.preparing");
        if(_updateTotal) {
            // Counts and the clock are written with the app language's own separators, so a German
            // page writes 1.234 where the English one writes 1,234. Byte counts come from
            // NSByteCountFormatter, whose units ("MB", "GB") are the same word in both of the
            // languages this app ships; it takes no locale, so only they follow the system.
            NSByteCountFormatter *bytes=[NSByteCountFormatter new];
            bytes.countStyle=NSByteCountFormatterCountStyleFile;
            BOOL counted=[_updatePhase isEqual:@"verify"] || [_updatePhase isEqual:@"download"];
            NSNumberFormatter *number=[NSNumberFormatter new];
            number.locale=WKLocalization.shared.locale; number.numberStyle=NSNumberFormatterDecimalStyle;
            NSString *done=counted?[bytes stringFromByteCount:(int64_t)_updateDone]
                :[number stringFromNumber:@(_updateDone)];
            NSString *total=counted?[bytes stringFromByteCount:(int64_t)_updateTotal]
                :[number stringFromNumber:@(_updateTotal)];
            detail=[detail stringByAppendingFormat:@" · %@ / %@",done,total];
        }
        action=WKLocalized(@"home.action.updating");
    } else if (_busy) {
        title=WKLocalized(@"home.status.checking");
        detail=WKLocalized(@"home.status.checking.detail");
        action=WKLocalized(@"home.action.checking");
    } else if (_error || !_plan) {
        title=_updateError?WKLocalized(@"home.status.updateInterrupted"):WKLocalized(@"home.status.checkFailed");
        detail=_updateError?WKLocalized(@"home.status.updateInterrupted.detail"):WKLocalized(@"home.status.checkFailed.detail");
        action=WKLocalized(@"home.action.retry"); enabled=YES;
    } else {
        switch (_installation.state) {
        case TKWoWInstallationMissing:
            title=WKLocalized(@"home.status.missing");
            detail=WKLocalized(@"home.status.missing.detail");
            action=WKLocalized(@"home.action.install"); enabled=YES; break;
        case TKWoWInstallationOutdated:
            title=_installation.localeNeedsUpdate?WKLocalized(@"home.status.localeUpdate"):WKLocalized(@"home.status.outdated");
            detail=_installation.localeNeedsUpdate?WKLocalized(@"home.status.localeUpdate.detail"):WKLocalized(@"home.status.outdated.detail");
            action=WKLocalized(@"home.action.update"); break;
        case TKWoWInstallationNeedsRepair:
            title=WKLocalized(@"home.status.repair");
            detail=WKLocalized(@"home.status.repair.detail");
            action=WKLocalized(@"home.action.repair"); enabled=YES; break;
        case TKWoWInstallationReady:
            title=WKLocalized(@"home.status.ready");
            detail=WKLocalized(@"home.status.ready.detail");
            action=_executionMode==TKExecutionModeNone?WKLocalized(@"home.action.startupUnavailable"):WKLocalized(@"home.action.play");
            enabled=_executionMode!=TKExecutionModeNone; break;
        }
    }
    _stateLabel.text=title; _detailLabel.text=detail;
    [self configureButton:_primaryButton title:action filled:YES]; _primaryButton.enabled=enabled;
    _refreshItem.enabled=!_busy && !_sessionUsed && !_starting && !_running;
    for (UIButton *button in @[_editionButton,_preferencesButton,_addonsButton,_macEverButton,_addonsDirectoryButton,
                                _permissionsButton,_voiceButton,_voiceTestButton,_backupButton,_resetButton,
                                _restoreButton,_settingsFolderButton])
        [self stylePlainButton:button];
    [self stylePrimaryButton];
    _diagnosticsButton.tintColor=_diagnosticsButton.enabled?Gold():RowGrey();
    if (_busy) [_activity startAnimating]; else [_activity stopAnimating];
    if (_checkedAt) {
        // The time is written the way the chosen language writes it, not the way the iPad is
        // set to: a German page with an English clock reads as two apps.
        NSDateFormatter *clock=[NSDateFormatter new];
        clock.locale=WKLocalization.shared.locale;
        clock.dateStyle=NSDateFormatterNoStyle; clock.timeStyle=NSDateFormatterShortStyle;
        NSString *time=[clock stringFromDate:_checkedAt];
        NSString *available=_plan[@"version"][@"VersionsName"];
        _versionLabel.text=[_installation.installedVersion isEqual:available]?
            WKLocalizedFormat(@"home.version.upToDate",available,time):
            WKLocalizedFormat(@"home.version.compare",_installation.installedVersion?:@"—",available);
    } else _versionLabel.text=nil;
    _versionLabel.hidden=!_versionLabel.text.length;
    switch (_executionMode) {
    case TKExecutionModeDeveloperService:
        _startupLabel.text=WKLocalized(@"home.startup.developerService"); break;
    case TKExecutionModeLocalSigning:
        _startupLabel.text=WKLocalized(@"home.startup.localSigning"); break;
    case TKExecutionModeExternalJIT:
        _startupLabel.text=WKLocalized(@"home.startup.externalJIT"); break;
    case TKExecutionModeNone:
        _startupLabel.text=WKLocalized(@"home.startup.unavailable"); break;
    }
}
// The launcher's own pages open over it rather than being pushed away to. The
// columns behind stay where they are, closing one puts the user back on the page
// they left instead of animating them through a stack, and nothing about the home
// page has to be rebuilt for having visited a setting - which is also why the
// game files are not re-read when one closes. See -viewDidAppear:.
- (void)presentPage:(UIViewController *)page {
    UINavigationController *frame=[[UINavigationController alloc] initWithRootViewController:page];
    frame.modalPresentationStyle=UIModalPresentationPageSheet;
    frame.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    frame.navigationBar.tintColor=WKGold();
    WKLog("ui", @"opening %@ over the home page", NSStringFromClass(page.class));
    WKPresentWhenFree(self, ^{ [self presentViewController:frame animated:YES completion:nil]; });
}
- (void)presentSheet:(UIAlertController *)sheet anchor:(UIView *)anchor {
    // A sheet that brings its own way out keeps it: two cancel actions is a UIKit warning
    // and one that reads differently in two languages is a bug.
    BOOL cancellable=YES;
    for (UIAlertAction *action in sheet.actions) if (action.style==UIAlertActionStyleCancel) cancellable=NO;
    if (cancellable)
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    WKPresentWhenFree(self, ^{
        if (anchor) { sheet.popoverPresentationController.sourceView=anchor; sheet.popoverPresentationController.sourceRect=anchor.bounds; }
        else sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
        [self presentViewController:sheet animated:YES completion:nil];
    });
}
- (void)chooseEdition {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"home.edition.title") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *product in TKWoWProducts()) [sheet addAction:[UIAlertAction actionWithTitle:product[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action; [self selectProduct:product];
    }]];
    [self presentSheet:sheet anchor:_editionButton];
}
// The game's download language, through the one writer. The app's language is a different
// setting and lives on its own row; both routes that change the game's language - this
// picker and the offer that follows the first German selection - come through here, so the
// validated locale writer and the update gate are the same in both.
- (void)setGameLocale:(NSString *)value {
    _locale=value;
    NSString *directory=[self foreverWorkingDirectory];
    if (directory) {
        NSError *error=nil;
        if (![TKForeverUI setLocale:value inWorkingDirectory:directory error:&error])
            WKLog("ui", @"language: unable to update Forever locale: %@", error.localizedDescription?:@"unknown reason");
    }
    [NSUserDefaults.standardUserDefaults setObject:value forKey:@"WoWLocale"];
    [self refresh];
}
- (void)choosePreference:(BOOL)region {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:region?WKLocalized(@"home.preferences.region"):WKLocalized(@"home.preferences.downloadLanguage") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *values=region?@[@"eu",@"us",@"kr",@"tw"]:@[@"enUS",@"esES",@"deDE"];
    for (NSString *value in values) [sheet addAction:[UIAlertAction actionWithTitle:region?TKWoWRegionName(value):TKWoWLocaleName(value) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        if (region) { self->_region=value; [NSUserDefaults.standardUserDefaults setObject:value forKey:@"WoWRegion"]; [self refresh]; }
        else [self setGameLocale:value];
    }]];
    [self presentSheet:sheet anchor:_preferencesButton];
}
- (void)preferences {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"home.preferences.title")
        message:WKLocalized(@"home.preferences.message") preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.preferences.region") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self choosePreference:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.preferences.language") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { (void)a; [self choosePreference:NO]; }]];
    [self presentSheet:sheet anchor:_preferencesButton];
}
- (void)settings {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"home.settings.title")
        message:WKLocalized(@"home.settings.message") preferredStyle:UIAlertControllerStyleActionSheet];
    if(!_busy && !_starting && !_sessionUsed && _installation.app) {
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.settings.manageAddons") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a; [self manageAddons];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.settings.repair") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a; [self repairInstallation];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.settings.diagnostics") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self diagnostics];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.settings.about") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a; [self about];
    }]];
    if (_startupFailure || _error || _installation.error) [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.settings.technical") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        // The raw reason, in whatever language the layer produced it: it is detail, and it matches
        // the log line beside it. The title is ours and is translated.
        [self presentMessage:WKLocalized(@"home.settings.details.title")
                     message:self->_startupFailure?:(self->_error?:self->_installation.error).localizedDescription];
    }]];
    [self presentSheet:sheet anchor:nil];
}
// Everything about dictation lives on its own screen: the button, the mode, and
// what happens to the words afterwards.
- (void)manageVoice {
    [self presentPage:[AKVoiceViewController new]];
}

// The same settings, exercised: a box the transcript lands in, driven by the
// button the user mapped, so it can be tried without starting the game.
- (void)testVoice {
    [self presentPage:[AKVoiceTestViewController new]];
}

// This app's own page in Settings: the Microphone and Speech Recognition switches for WolkaraForever.
//
// iOS gives an app no way to grant, reset or re-prompt for its own privacy permission - the decision
// belongs to the person using the device. This project has been bitten by exactly that: tccd answers
// "allowed" and then fails to issue the microphone sandbox extension to the installed binary, so audio
// never arrives while the permission reads granted. The one supported remedy is the person changing it
// in Settings, so the launcher takes them to that exact page instead of describing where it is.
- (void)openPermissions {
    NSURL *url=[NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if(!url) { WKLog("host", @"permissions: this system has no app settings page"); return; }
    if(self.openAppSettingsURL) { self.openAppSettingsURL(url); return; }
    UIApplication *app=UIApplication.sharedApplication;
    if(![app canOpenURL:url]) {
        WKLog("host", @"permissions: this system will not open the app's settings page");
        return;
    }
    [app openURL:url options:@{} completionHandler:^(BOOL opened) {
        WKLog("host", @"permissions: opened this app's settings page: %@", opened?@"yes":@"no");
    }];
}

// The game's add-on folder, in the file browser. The picker is the documented way
// to start Files at a directory; an alert with a path would be a worse answer to
// the same request, because the user came here to put files in it.
- (void)openAddonDirectory {
    NSError *error=nil;
    NSString *addons=[self addOnsDirectoryWithError:&error];
    if (!addons) { [self presentAddonsUnavailable:error]; return; }
    // The game makes this folder on its first run. Until then there is nothing to
    // open, so make it rather than refuse.
    NSFileManager *files=NSFileManager.defaultManager;
    if (![files fileExistsAtPath:addons]) {
        [files createDirectoryAtPath:addons withIntermediateDirectories:YES attributes:nil error:&error];
        if (![files fileExistsAtPath:addons]) { [self presentAddonsUnavailable:error]; return; }
    }
    NSURL *folder=[NSURL fileURLWithPath:addons isDirectory:YES];
    if (self.openAddonDirectoryURL) { self.openAddonDirectoryURL(folder); return; }
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder]];
    picker.directoryURL=folder;
    picker.allowsMultipleSelection=NO;
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
// Two pickers come through here. The add-on folder has nothing to take from it:
// it was opened so the user can put files in it with the browser's own
// controls. The restore picker's choice is the snapshot to bring back, and only
// a ZIP inside WTF/Backups is accepted - the archive checks the rest.
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *backups=_backupsDirectory;
    _backupsDirectory=nil;
    // Only the restore picker resumes a restore. Checking the picker's own
    // directory as well means a stale flag can never turn an add-on folder
    // selection into one.
    if (!backups || !urls.count || ![controller.directoryURL.path isEqual:backups]) return;
    NSURL *url=urls.firstObject;
    NSString *root=[backups stringByResolvingSymlinksInPath].stringByStandardizingPath;
    NSString *path=[url.path stringByResolvingSymlinksInPath].stringByStandardizingPath;
    NSString *name=url.lastPathComponent;
    if (![path hasPrefix:[root stringByAppendingString:@"/"]] || ![name.lowercaseString hasSuffix:@".zip"]) {
        [self presentMessage:WKLocalized(@"home.restore.notBackup.title") message:WKLocalized(@"home.restore.notBackup.message")];
        return;
    }
    [self restoreBackupNamed:name];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    _backupsDirectory=nil;
}
#pragma mark - Forever UI file operations

// The working directory of the inspected Forever installation, or nil when the
// selected edition is not Forever or is not ready. These rows are about Forever
// only: another edition's files are never read or written by them.
- (nullable NSString *)foreverWorkingDirectory {
    if (![_product[@"id"] isEqualToString:TKForeverUIEdition]) return nil;
    if (_installation.state!=TKWoWInstallationReady || !_installation.app) return nil;
    return [_library workingDirectoryForApp:_installation.app error:NULL];
}
- (BOOL)foreverActionAllowed {
    return [self foreverWorkingDirectory]!=nil && !_busy && !_starting && !_sessionUsed && !_uiOperation;
}
- (void)presentMessage:(NSString *)title message:(nullable NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
    WKPresentWhenFree(self, ^{ [self presentViewController:alert animated:YES completion:nil]; });
}
// A snapshot of the complete Forever UI. It is an explicit user action here, and
// it is also the rollback point the two destructive rows make for themselves.
- (void)backupUI {
    if (![self foreverActionAllowed]) return;
    NSString *directory=[self foreverWorkingDirectory];
    if (!directory) return;
    WKLog("ui", @"backup: starting");
    _uiOperation=YES; [self render];
    __weak TKWoWViewController *weakSelf=self;
    dispatch_async(TKForeverUIQueue(), ^{
        NSError *error=nil;
        NSString *name=[TKForeverUI createUIBackupInWorkingDirectory:directory edition:TKForeverUIEdition error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWViewController *self=weakSelf; if(!self) return;
            self->_uiOperation=NO; [self render];
            if (name) {
                WKLog("ui", @"backup: wrote a snapshot");
                [self presentMessage:WKLocalized(@"home.backup.done.title") message:WKLocalizedFormat(@"home.backup.done.message",name)];
            } else {
                WKLog("ui", @"backup: failed: %@", error.localizedDescription?:@"unknown reason");
                [self presentMessage:WKLocalized(@"home.backup.failed.title")
                    message:error.localizedDescription?WKLocalizedFormat(@"home.backup.failed.reason",error.localizedDescription):WKLocalized(@"home.backup.failed.message")];
            }
        });
    });
}
// Destructive, so it is confirmed first. Forever regenerates its graphics
// defaults on the next launch; everything else in the UI is backable and kept.
- (void)resetGraphics {
    if (![self foreverActionAllowed]) return;
    NSString *directory=[self foreverWorkingDirectory];
    if (!directory) return;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"home.reset.confirm.title")
        message:WKLocalized(@"home.reset.confirm.message")
        preferredStyle:UIAlertControllerStyleAlert];
    __weak TKWoWViewController *weakSelf=self;
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.reset.action") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action; [weakSelf performGraphicsReset:directory];
    }]];
    [self presentSheet:sheet anchor:_resetButton];
}
- (void)performGraphicsReset:(NSString *)directory {
    if (_busy || _starting || _sessionUsed || _uiOperation) return;
    _uiOperation=YES; [self render];
    __weak TKWoWViewController *weakSelf=self;
    dispatch_async(TKForeverUIQueue(), ^{
        NSError *error=nil;
        // No backup, no reset: the destructive half never runs alone.
        NSString *backup=[TKForeverUI createUIBackupInWorkingDirectory:directory edition:TKForeverUIEdition error:&error];
        BOOL reset=backup?[TKForeverUI resetGraphicsInWorkingDirectory:directory error:&error]:NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWViewController *self=weakSelf; if(!self) return;
            self->_uiOperation=NO; [self render];
            if (!backup) {
                WKLog("ui", @"reset: aborted, no backup: %@", error.localizedDescription?:@"unknown reason");
                [self presentMessage:WKLocalized(@"home.reset.noBackup.title")
                    message:WKLocalizedFormat(@"home.reset.noBackup.message",error.localizedDescription?:@"")];
            } else if (!reset) {
                WKLog("ui", @"reset: backup kept, settings not reset: %@", error.localizedDescription?:@"unknown reason");
                [self presentMessage:WKLocalized(@"home.reset.incomplete.title")
                    message:WKLocalizedFormat(@"home.reset.incomplete.message",backup,error.localizedDescription?:@"")];
            } else {
                WKLog("ui", @"reset: graphics removed, backup kept");
                [self presentMessage:WKLocalized(@"home.reset.done.title") message:WKLocalizedFormat(@"home.reset.done.message",backup)];
            }
        });
    });
}
// The browser opens at the game's WTF/Backups folder and the user picks the
// snapshot to bring back. A fresh snapshot of the current state is made first,
// so the restore can itself be undone.
- (void)restoreUI {    if (![self foreverActionAllowed]) return;
    NSString *directory=[self foreverWorkingDirectory];
    if (!directory) return;
    NSError *error=nil;
    NSString *wtf=[TKForeverUI wtfDirectoryInWorkingDirectory:directory create:NO error:&error];
    NSString *backups=wtf?[wtf stringByAppendingPathComponent:@"Backups"]:nil;
    NSArray<NSString *> *zips=backups?[[NSFileManager.defaultManager contentsOfDirectoryAtPath:backups error:NULL]
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            (void)bindings;
            return [name.lowercaseString hasSuffix:@".zip"];
        }]]:@[];
    if (!zips.count) {
        [self presentMessage:WKLocalized(@"home.restore.none.title")
            message:WKLocalized(@"home.restore.none.message")];
        return;
    }
    NSURL *folder=[NSURL fileURLWithPath:backups isDirectory:YES];
    _backupsDirectory=folder.path;
    if (self.chooseBackupFile) { self.chooseBackupFile(folder); return; }
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeZIP]];
    picker.directoryURL=folder;
    picker.allowsMultipleSelection=NO;
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)restoreBackupNamed:(NSString *)name {
    if (![self foreverActionAllowed]) return;
    NSString *directory=[self foreverWorkingDirectory];
    if (!directory) return;
    _uiOperation=YES; [self render];
    __weak TKWoWViewController *weakSelf=self;
    dispatch_async(TKForeverUIQueue(), ^{
        NSError *error=nil;
        NSString *fresh=[TKForeverUI createUIBackupInWorkingDirectory:directory edition:TKForeverUIEdition error:&error];
        BOOL restored=NO;
        if (!fresh) {
            error=[NSError errorWithDomain:TKForeverUIErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:
                WKLocalizedFormat(@"home.restore.safetyFailed",error.localizedDescription?:@"")}];
        } else {
            restored=[TKForeverUI restoreUIBackupNamed:name inWorkingDirectory:directory edition:TKForeverUIEdition error:&error];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWViewController *self=weakSelf; if(!self) return;
            self->_uiOperation=NO; [self render];
            if (restored) {
                WKLog("ui", @"restore: completed from the selected snapshot");
                [self presentMessage:WKLocalized(@"home.restore.done.title") message:WKLocalizedFormat(@"home.restore.done.message",name,fresh)];
            } else {
                WKLog("ui", @"restore: not completed: %@", error.localizedDescription?:@"unknown reason");
                [self presentMessage:WKLocalized(@"home.restore.failed.title")
                    message:error.localizedDescription?WKLocalizedFormat(@"home.restore.failed.reason",error.localizedDescription):WKLocalized(@"home.restore.failed.message")];
            }
        });
    });
}
// Exactly one `SET GamePadEnable "1"` or `"0"` in the active Config.wtf. It
// changes no bindings and touches neither GamePadConfig_*.json nor
// gamecontrollerdb.txt.
- (void)gamepadChanged:(UISwitch *)sender {
    if (![self foreverActionAllowed]) { sender.on=!_gamepadEnabled; return; }
    NSString *directory=[self foreverWorkingDirectory];
    if (!directory) { sender.on=!_gamepadEnabled; return; }
    BOOL want=sender.on;
    _uiOperation=YES; [self render];
    __weak TKWoWViewController *weakSelf=self;
    dispatch_async(TKForeverUIQueue(), ^{
        NSError *error=nil;
        BOOL stored=[TKForeverUI setGamepad:want inWorkingDirectory:directory error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            TKWoWViewController *self=weakSelf; if(!self) return;
            self->_uiOperation=NO; [self render];
            if (stored) {
                WKLog("ui", @"gamepad UI: %@", want?@"enabled":@"disabled");
                [self presentMessage:want?WKLocalized(@"home.gamepad.on.title"):WKLocalized(@"home.gamepad.off.title")
                    message:WKLocalized(@"home.gamepad.message")];
            } else {
                WKLog("ui", @"gamepad UI: not changed: %@", error.localizedDescription?:@"unknown reason");
                [self presentMessage:WKLocalized(@"home.gamepad.unchanged.title")
                    message:error.localizedDescription?WKLocalizedFormat(@"home.gamepad.unchanged.reason",error.localizedDescription):WKLocalized(@"home.gamepad.unchanged.message")];
            }
        });
    });
}
// The HUD preference lives in the touch layout store. Read-modify-write keeps
// every existing value (opacity, scales, haptics, positions) and the change
// notification is what the in-game settings page and the host view listen to.
- (void)overlayChanged:(UISwitch *)sender {
    if (_busy || _starting) { sender.on=!_overlayEnabled; return; }
    BOOL enabled=sender.on;
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    id stored=[defaults objectForKey:TKForeverLayoutKey];
    NSMutableDictionary *layout=[stored isKindOfClass:NSDictionary.class]?[stored mutableCopy]:[NSMutableDictionary new];
    layout[@"performanceOverlayEnabled"]=@(enabled);
    [defaults setObject:layout forKey:TKForeverLayoutKey];
    [NSNotificationCenter.defaultCenter postNotificationName:TKForeverLayoutDidChange object:defaults];
    WKLog("ui", @"performance overlay: %@", enabled?@"enabled":@"disabled");
    [self render];
}
// This is selected before starting Forever. The guest backing scale is fixed
// when its display bridge loads, so changing it never tears down a live game.
- (void)chooseRenderProfile {
    if (_busy || _starting || _running || _sessionUsed) return;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:WKLocalized(@"home.render.title")
        message:WKLocalized(@"home.render.message") preferredStyle:UIAlertControllerStyleActionSheet];
    __weak TKWoWViewController *weakSelf=self;
    void (^choose)(CGFloat,NSString *,NSString *)=^(CGFloat scale,NSString *name,NSString *shown) {
        TKWoWViewController *self=weakSelf; if (!self) return;
        [NSUserDefaults.standardUserDefaults setObject:@(scale) forKey:@"WolkaraForeverBackingScale"];
        WKLog("ui", @"render profile: %@", name);
        NSString *directory=[self foreverWorkingDirectory];
        if (!directory) { [self render]; return; }
        // The old implementation exposed a performance preset but never called
        // it. Keep the virtual-display choice and the game's own render scale in
        // one explicit, reversible profile change. Every profile retains a 60 Hz
        // foreground cap and a low background cap; only Performance uses 0.75.
        NSDictionary *settings=scale<=0.75?TKForeverUI.performancePreset:@{
            @"renderScale": @"1.0", @"gxForegroundFPS": @"60",
            @"gxBackgroundFPS": @"30", @"vsync": @"1",
        };
        self->_uiOperation=YES; [self render];
        dispatch_async(TKForeverUIQueue(), ^{
            NSError *error=nil;
            NSString *backup=[TKForeverUI createUIBackupInWorkingDirectory:directory edition:TKForeverUIEdition error:&error];
            BOOL applied=backup && [TKForeverUI setCVars:settings inWorkingDirectory:directory error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                TKWoWViewController *self=weakSelf; if (!self) return;
                self->_uiOperation=NO; [self render];
                if (applied) {
                    WKLog("ui", @"render profile settings: %@", name);
                    [self presentMessage:WKLocalized(@"home.render.ready.title") message:WKLocalizedFormat(@"home.render.ready.message",shown,backup)];
                } else {
                    WKLog("ui", @"render profile settings not changed: %@", error.localizedDescription?:@"unknown reason");
                    [self presentMessage:WKLocalized(@"home.render.failed.title") message:WKLocalizedFormat(@"home.render.failed.message",error.localizedDescription?:@"")];
                }
            });
        });
    };
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.render.performance.action") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { choose(.75,@"performance",WKLocalized(@"home.render.performance")); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.render.balanced.action") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { choose(1.0,@"balanced",WKLocalized(@"home.render.balanced")); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"home.render.quality.action") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { choose(2.0,@"quality",WKLocalized(@"home.render.quality")); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet anchor:_renderProfileButton];
}
// Navigation only: the Files browser opens at Forever's WTF folder. The folder is
// created only here, only for a ready Forever installation, and nothing else is.
- (void)openSettingsFolder {
    if (![self foreverActionAllowed]) return;
    NSString *directory=[self foreverWorkingDirectory];
    if (!directory) return;
    NSError *error=nil;
    NSString *wtf=[TKForeverUI wtfDirectoryInWorkingDirectory:directory create:YES error:&error];
    if (!wtf) { [self presentMessage:WKLocalized(@"home.settingsFolder.unavailable.title")
        message:error.localizedDescription?WKLocalizedFormat(@"home.settingsFolder.unavailable.reason",error.localizedDescription):WKLocalized(@"home.settingsFolder.unavailable.message")]; return; }
    NSURL *folder=[NSURL fileURLWithPath:wtf isDirectory:YES];
    if (self.openSettingsFolderURL) { self.openSettingsFolderURL(folder); return; }
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder]];
    picker.directoryURL=folder;
    picker.allowsMultipleSelection=NO;
    picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
// Mac-Ever's CurseForge page, in the browser. The user downloads the ZIP there
// and comes back to Install Addons (Curse & Direct); opening the page is not an
// installation and is never reported as one.
- (void)downloadMacEver {
    NSURL *url=[NSURL URLWithString:@"https://www.curseforge.com/wow/addons/mac-ever"];
    if (!url) return;
    if (self.openExternalURL) { self.openExternalURL(url); return; }
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL opened) {
        WKLog("host", @"mac-ever: download page opened: %@", opened?@"yes":@"no");
    }];
}
- (void)presentAddonsUnavailable:(nullable NSError *)error {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:WKLocalized(@"home.addons.unavailable.title")
        message:error.localizedDescription?WKLocalizedFormat(@"home.addons.unavailable.reason",error.localizedDescription):WKLocalized(@"home.addons.unavailable.message")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
    WKPresentWhenFree(self, ^{ [self presentViewController:alert animated:YES completion:nil]; });
}
- (nullable NSString *)addOnsDirectoryWithError:(NSError **)error {
    NSString *directory=[_library workingDirectoryForApp:_installation.app error:error];
    return directory?[directory stringByAppendingPathComponent:@"Interface/AddOns"]:nil;
}

- (void)previewAddonBrowser {
    [self loadViewIfNeeded];
    NSError *error=nil;
    // The preview can arrive before the first check has finished; resolve the
    // library's app directly rather than depending on _installation.
    TKApp *app=_installation.app;
    if (!app) { [_library discover]; app=_library.defaultApp; }
    NSString *directory=app?[_library workingDirectoryForApp:app error:&error]:nil;
    NSString *addons=directory?[directory stringByAppendingPathComponent:@"Interface/AddOns"]:nil;
    if (!addons) { WKLog("ui", @"addons preview: %@", error.localizedDescription ?: @"no installation"); return; }
    NSString *edition=_product[@"name"]?:@"Forever";
    TKWoWAddonManagerViewController *manager=[[TKWoWAddonManagerViewController alloc]
        initWithAddOnsDirectory:addons edition:edition browse:YES];
    [self presentPage:manager];
}
- (void)manageAddons {
    NSError *error=nil;
    NSString *addons=[self addOnsDirectoryWithError:&error];
    if (!addons) { [self presentAddonsUnavailable:error]; return; }
    TKWoWAddonManagerViewController *manager=[[TKWoWAddonManagerViewController alloc] initWithAddOnsDirectory:addons edition:_product[@"name"]];
    [self presentPage:manager];
}
- (UILabel *)startupStatusLabel { [self loadViewIfNeeded]; return _detailLabel; }
- (void)beginStartup {
    [self loadViewIfNeeded];
    [self cancel]; _starting=YES; _running=NO; _startupFailure=nil;
    _detailLabel.text=WKLocalized(@"home.status.starting.detail");
    _diagnosticsButton.hidden=YES;
    [self render]; [_launchProgress start];
    [self.view layoutIfNeeded];
}
- (void)finishStartupWithMessage:(NSString *)message failed:(BOOL)failed {
    _starting=NO; _running=NO; _startupFailure=failed?message:nil;
    [_launchProgress stop]; _diagnosticsButton.hidden=!failed;
    [self render];
}
// Called when the guest's own window appears. Until then the page says it is
// starting; from here the game is running, not loading.
- (void)guestDidStartRunning {
    if (!_starting || _running) return;
    _starting=NO; _running=YES;
    [_launchProgress stop];
    WKLog("ui", @"home: the game is running");
    [self render];
}
- (void)closeApp {
    WKLog("ui", @"home: closing the app at the user's request");
    exit(0);
}
- (void)diagnostics { if (self.showDiagnostics) self.showDiagnostics(); }
- (void)about {
    UIViewController *controller=[UIViewController new]; controller.title=WKLocalized(@"home.about.title");
    controller.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UITextView *text=[UITextView new]; text.editable=NO;
    text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; text.adjustsFontForContentSizeCategory=YES;
    text.textContainerInset=UIEdgeInsetsMake(20,20,20,20);
    text.accessibilityLanguage=WKLocalization.shared.languageCode;
    NSMutableString *credits=[WKLocalized(@"about.intro") mutableCopy];
    // Four documents, and which is which matters. This app is a fork that ships upstream's
    // code, so it carries its own licence and notice and it keeps theirs; they are told
    // apart by name, which is why ours are prefixed in the bundle. The first version
    // listed two names and quietly showed whatever it found, which was upstream's
    // documents under our attribution - and when nothing matched it showed nothing at
    // all, silently. The list itself lives beside the log line that reports it, so the two
    // cannot disagree, and a missing document says so on the page.
    for (NSArray<NSString *> *document in WKBundledDocuments()) {
        NSString *name=document[1];
        NSString *heading=WKLocalized(document[0]);
        NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name];
        NSString *notice=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        // The documents themselves are the licensors' words and are shown as they ship.
        if (notice) [credits appendFormat:@"\n\n———— %@ ————\n%@\n",heading,notice];
        else [credits appendFormat:@"\n\n———— %@ ————\n%@\n",heading,WKLocalizedFormat(@"about.documentMissing",name)];
    }
    text.text=credits; controller.view=text;
    [self.navigationController pushViewController:controller animated:YES];
}
@end
