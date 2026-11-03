#import "ControllerManagerViewController.h"

#import "../Controller/ControllerManager.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WolkaraForeverTheme.h"

static UIColor *CMGold(void) { return [UIColor colorWithRed:0.88 green:0.73 blue:0.43 alpha:1]; }
static UIColor *CMMuted(void) { return [UIColor colorWithRed:0.66 green:0.72 blue:0.78 alpha:1]; }

static UILabel *CMLabel(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

@interface TKWoWControllerManagerViewController ()
@end

@implementation TKWoWControllerManagerViewController {
    UISwitch *_routingSwitch;
    UILabel *_routingTitleLabel;
    UILabel *_statusLabel;
    UISegmentedControl *_modelsControl;
    UIStackView *_bindingsStack;
    UILabel *_bindingsHeading;
    UIButton *_learnButton, *_cancelButton, *_resetButton;
    UILabel *_hintLabel, *_disclosureLabel;
    // The card headings, in the order they were added, so a language change rewrites them
    // where they are instead of rebuilding the page and losing what it is showing.
    NSMutableArray<UILabel *> *_headings;
    // The identity the page is showing. Kept across renders so a connect or disconnect
    // does not move the user to another pad's mappings while they are editing.
    NSString *_selectedIdentity;
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) return self;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithRed:0.025 green:0.045 blue:0.075 alpha:1];
    self.title = WKLocalized(@"controller.title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    UIStackView *column = [UIStackView new];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 16;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [column.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [column.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [column.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [column.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [column.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],
    ]];

    // The switch. The label is fixed and the control says the state, the same shape the
    // launcher's own switches use.
    UILabel *routingTitle = CMLabel(17, UIFontWeightRegular, UIColor.whiteColor);
    routingTitle.text = WKLocalized(@"controller.enabled");
    routingTitle.accessibilityIdentifier = @"controllerManager.enabled.label";
    routingTitle.isAccessibilityElement = NO;
    _routingTitleLabel = routingTitle;
    [routingTitle setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _routingSwitch = [UISwitch new];
    _routingSwitch.onTintColor = CMGold();
    _routingSwitch.accessibilityIdentifier = @"controllerManager.enabled";
    _routingSwitch.accessibilityLabel = WKLocalized(@"controller.enabled");
    [_routingSwitch addTarget:self action:@selector(routingChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *routingRow = [[UIStackView alloc] initWithArrangedSubviews:@[routingTitle, _routingSwitch]];
    routingRow.axis = UILayoutConstraintAxisHorizontal;
    routingRow.alignment = UIStackViewAlignmentCenter;

    _statusLabel = CMLabel(15, UIFontWeightRegular, CMMuted());
    _statusLabel.accessibilityIdentifier = @"controllerManager.status";

    _modelsControl = [[UISegmentedControl alloc] initWithItems:@[]];
    _modelsControl.accessibilityIdentifier = @"controllerManager.models";
    _modelsControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    [_modelsControl addTarget:self action:@selector(modelChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *bindingsHeading = CMLabel(15, UIFontWeightSemibold, CMMuted());
    bindingsHeading.text = WKLocalized(@"controller.binding.header").uppercaseString;
    _bindingsHeading = bindingsHeading;
    _bindingsStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _bindingsStack.axis = UILayoutConstraintAxisVertical;
    _bindingsStack.spacing = 4;

    _learnButton = [self commandButton:@"controllerManager.learn" title:WKLocalized(@"controller.learn")
                                action:@selector(beginLearning)];
    _cancelButton = [self commandButton:@"controllerManager.cancel" title:WKLocalized(@"controller.cancel")
                                 action:@selector(cancelLearning)];
    _cancelButton.hidden = YES;
    _resetButton = [self commandButton:@"controllerManager.reset" title:WKLocalized(@"controller.reset")
                                action:@selector(resetProfile)];

    _hintLabel = CMLabel(14, UIFontWeightRegular, CMGold());
    _hintLabel.text = WKLocalized(@"controller.learn.hint");
    _hintLabel.accessibilityIdentifier = @"controllerManager.hint";
    _hintLabel.hidden = YES;

    _disclosureLabel = CMLabel(13, UIFontWeightRegular, CMMuted());
    _disclosureLabel.text = WKLocalized(@"controller.disclosure");
    _disclosureLabel.accessibilityIdentifier = @"controllerManager.disclosure";

    [column addArrangedSubview:[self cardWithTitle:WKLocalized(@"controller.section.routing")
                                              rows:@[routingRow, _statusLabel]]];
    [column addArrangedSubview:[self cardWithTitle:WKLocalized(@"controller.section.model")
                                              rows:@[_modelsControl, bindingsHeading, _bindingsStack]]];
    [column addArrangedSubview:[self cardWithTitle:WKLocalized(@"controller.section.change")
                                              rows:@[_hintLabel, _learnButton, _cancelButton, _resetButton]]];
    [column addArrangedSubview:_disclosureLabel];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(managerChanged:)
                                               name:AKControllerManagerDidChangeNotification object:nil];
    // The app language is a setting of this app, not of the game, and the launcher changes
    // it without a relaunch; a page that kept its old words until it was reopened would be
    // the same bug the launcher's own page was fixed for.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appLanguageChanged:)
                                               name:WKLocalizationDidChangeNotification object:nil];
    // The manager may be used by another page too; this is the only place the learn result
    // is consumed, so it is set here and cleared when the page goes away.
    __weak TKWoWControllerManagerViewController *weakSelf = self;
    AKControllerManager.shared.onLearned = ^(NSString *identity, NSString *source) {
        TKWoWControllerManagerViewController *self = weakSelf;
        [self learntSource:source identity:identity];
    };
    [self localize];
    [self render];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Leaving the page with the mapper armed is exactly the bug the voice page's arming
    // deadline exists to prevent: a press made later would rewrite the profile.
    [AKControllerManager.shared cancelLearning];
    _selectedIdentity = nil;
    if (AKControllerManager.shared.onLearned) AKControllerManager.shared.onLearned = nil;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Building blocks

- (UIView *)cardWithTitle:(NSString *)title rows:(NSArray<UIView *> *)rows {
    UIView *box = [UIView new];
    box.backgroundColor = [UIColor colorWithRed:0.055 green:0.085 blue:0.125 alpha:1];
    box.layer.cornerRadius = 14;
    box.layer.borderWidth = 1;
    box.layer.borderColor = [CMGold() colorWithAlphaComponent:0.18].CGColor;
    UILabel *heading = CMLabel(13, UIFontWeightSemibold, CMMuted());
    heading.text = title.uppercaseString;
    if (!_headings) _headings = [NSMutableArray array];
    [_headings addObject:heading];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:[@[heading] arrayByAddingObjectsFromArray:rows]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-14],
    ]];
    return box;
}

- (UIButton *)commandButton:(NSString *)identifier title:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityIdentifier = identifier;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration;
    configuration.title = title;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 4, 8, 4);
    configuration.baseForegroundColor = CMGold();
    button.configuration = configuration;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    return button;
}

#pragma mark - Render

- (void)managerChanged:(NSNotification *)note {
    (void)note;
    [self render];
}

// Every fixed word on the page, in the app's language, in one place. Called when the page is
// built and again whenever the language changes.
- (void)localize {
    WKLocalization *localization = WKLocalization.shared;
    self.title = WKLocalized(@"controller.title");
    _routingTitleLabel.text = WKLocalized(@"controller.enabled");
    _routingSwitch.accessibilityLabel = WKLocalized(@"controller.enabled");
    _bindingsHeading.text = WKLocalized(@"controller.binding.header").uppercaseString;
    _hintLabel.text = WKLocalized(@"controller.learn.hint");
    _disclosureLabel.text = WKLocalized(@"controller.disclosure");
    [_learnButton setTitle:WKLocalized(@"controller.learn") forState:UIControlStateNormal];
    [_cancelButton setTitle:WKLocalized(@"controller.cancel") forState:UIControlStateNormal];
    [_resetButton setTitle:WKLocalized(@"controller.reset") forState:UIControlStateNormal];
    NSArray<NSString *> *sections = @[@"controller.section.routing", @"controller.section.model",
                                      @"controller.section.change"];
    for (NSUInteger index = 0; index < _headings.count && index < sections.count; index++)
        _headings[index].text = WKLocalized(sections[index]).uppercaseString;
    // VoiceOver is told the language of the words it is about to read.
    self.view.accessibilityLanguage = localization.languageCode;
}

- (void)appLanguageChanged:(NSNotification *)note {
    (void)note;
    [self localize];
    [self render];
}

- (void)render {
    if (!self.isViewLoaded) return;
    AKControllerManager *manager = AKControllerManager.shared;
    _routingSwitch.on = manager.enabled;

    switch (manager.state) {
        case AKControllerRoutingStateDisabled:
            _statusLabel.text = WKLocalized(@"controller.status.disabled");
            break;
        case AKControllerRoutingStateWaiting:
            _statusLabel.text = manager.physicalControllerConnected
                ? WKLocalized(@"controller.status.connecting")
                : WKLocalized(@"controller.status.nocontroller");
            break;
        case AKControllerRoutingStateRouting:
            _statusLabel.text = WKLocalized(@"controller.status.routing");
            break;
        case AKControllerRoutingStateFailed:
            _statusLabel.text = manager.guestFacadePresent
                ? WKLocalized(@"controller.status.failed")
                : WKLocalized(@"controller.status.nofacade");
            break;
    }

    NSArray<AKControllerModel *> *models = manager.models;
    // Keep the model the user is editing, unless it has gone away; then fall back to the
    // first one rather than showing an empty page with a pad connected.
    BOOL stillPresent = NO;
    for (AKControllerModel *model in models)
        if ([model.identity isEqualToString:_selectedIdentity]) { stillPresent = YES; break; }
    if (!stillPresent) _selectedIdentity = models.firstObject.identity;
    _modelsControl.hidden = models.count == 0;
    [_modelsControl removeAllSegments];
    NSUInteger selected = 0;
    for (NSUInteger index = 0; index < models.count; index++) {
        AKControllerModel *model = models[index];
        // A count is shown only when it is more than one, because that is when the shared
        // mapping matters - and the disclosure below says why.
        NSString *title = model.count > 1
            ? [NSString stringWithFormat:@"%@ (%lu)", model.displayName, (unsigned long)model.count]
            : model.displayName;
        [_modelsControl insertSegmentWithTitle:title atIndex:index animated:NO];
        if ([model.identity isEqualToString:_selectedIdentity]) selected = index;
    }
    if (models.count) _modelsControl.selectedSegmentIndex = (NSInteger)selected;

    for (UIView *view in _bindingsStack.arrangedSubviews) {
        [_bindingsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    AKControllerModel *model = models.count ? models[selected] : nil;
    _learnButton.enabled = model != nil && !manager.learning;
    _cancelButton.hidden = !manager.learning;
    _hintLabel.hidden = !manager.learning;
    _resetButton.enabled = model.customised;

    NSArray<AKControllerBinding *> *bindings = model.bindings ?: @[];
    NSUInteger index = 0;
    for (AKControllerBinding *binding in bindings) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        row.accessibilityIdentifier = [NSString stringWithFormat:@"controllerManager.binding.%lu", (unsigned long)index++];
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        // A row the pad cannot produce is shown, not hidden: the choice belongs to the
        // profile, and the next pad of this model may well have the control.
        row.enabled = binding.available;
        NSString *title = [NSString stringWithFormat:@"%@  →  %@%@", binding.sourceDisplay, binding.targetDisplay,
                           binding.reserved ? WKLocalized(@"controller.reserved") : @""];
        UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration;
        configuration.title = binding.available && model ? title : [title stringByAppendingFormat:@"  (%@)", WKLocalized(@"controller.unavailable")];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 0, 6, 0);
        configuration.baseForegroundColor = binding.available ? UIColor.whiteColor : CMMuted();
        row.configuration = configuration;
        row.tag = (NSInteger)index - 1;
        [row addTarget:self action:@selector(bindingTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_bindingsStack addArrangedSubview:row];
    }
    if (!bindings.count) {
        UILabel *empty = CMLabel(15, UIFontWeightRegular, CMMuted());
        empty.text = WKLocalized(@"controller.nomodels");
        empty.accessibilityIdentifier = @"controllerManager.empty";
        [_bindingsStack addArrangedSubview:empty];
    }
}

#pragma mark - Actions

- (void)routingChanged:(UISwitch *)sender {
    AKControllerManager.shared.enabled = sender.on;
    WKLog("input", @"controller manager: routing %@ from the launcher", sender.on ? @"on" : @"off");
    [self render];
}

- (void)modelChanged:(UISegmentedControl *)sender {
    NSArray<AKControllerModel *> *models = AKControllerManager.shared.models;
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)models.count) return;
    _selectedIdentity = models[(NSUInteger)sender.selectedSegmentIndex].identity;
    [self render];
}

- (AKControllerModel *)selectedModel {
    for (AKControllerModel *model in AKControllerManager.shared.models)
        if ([model.identity isEqualToString:_selectedIdentity]) return model;
    return nil;
}

- (void)bindingTapped:(UIButton *)sender {
    AKControllerModel *model = [self selectedModel];
    if (!model || sender.tag < 0 || (NSUInteger)sender.tag >= model.bindings.count) return;
    AKControllerBinding *binding = model.bindings[(NSUInteger)sender.tag];
    [self chooseTargetForSource:binding.source identity:model.identity];
}

- (void)beginLearning {
    AKControllerModel *model = [self selectedModel];
    if (!model) return;
    [AKControllerManager.shared beginLearningForIdentity:model.identity];
    WKLog("input", @"controller manager: learning a source for %@", model.identity);
    [self render];
}

- (void)cancelLearning {
    [AKControllerManager.shared cancelLearning];
    [self render];
}

// "Press or move source, then select virtual target - in that order, because the user
// already knows which physical control they can reach.
- (void)learntSource:(NSString *)source identity:(NSString *)identity {
    if (![identity isEqualToString:_selectedIdentity]) { [self render]; return; }
    [self chooseTargetForSource:source identity:identity];
}

- (void)chooseTargetForSource:(NSString *)source identity:(NSString *)identity {
    NSArray<AKControllerTarget *> *targets = AKControllerTarget.targets;
    NSString *sourceDisplay = [source copy];
    for (AKControllerBinding *binding in [self selectedModel].bindings)
        if ([binding.source isEqualToString:source]) sourceDisplay = binding.sourceDisplay;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:WKLocalized(@"controller.targets.title")
        message:sourceDisplay preferredStyle:UIAlertControllerStyleActionSheet];
    for (AKControllerTarget *target in targets) {
        [sheet addAction:[UIAlertAction actionWithTitle:target.display style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
            (void)action;
            [self bindSource:source toTarget:target.identifier identity:identity];
        }]];
    }
    // "Not assigned" is a choice, not a cancellation: a control the user does not want to
    // drive anything is a real answer and has to survive a reload.
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"controller.binding.unassigned")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [self bindSource:source toTarget:AKControllerTargetNone identity:identity];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)bindSource:(NSString *)source toTarget:(NSString *)target identity:(NSString *)identity {
    AKControllerProfile *profile = [AKControllerManager.shared profileForIdentity:identity];
    [profile bindSource:source toTarget:target];
    [AKControllerManager.shared applyProfileChangeForIdentity:identity];
    [self render];
}

- (void)resetProfile {
    AKControllerModel *model = [self selectedModel];
    if (!model) return;
    [AKControllerManager.shared resetProfileForIdentity:model.identity];
    [self render];
}

@end
