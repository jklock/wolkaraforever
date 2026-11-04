#import "ControllerManagerViewController.h"

#import "../Controller/ControllerManager.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WolkaraForeverTheme.h"
#import "../Controller/ControllerProfile.h"
#import "../Input/Trigger.h"
#import "ControllerPadDiagram.h"

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
    // The controller, drawn: what a mapping is, instead of a list to read.
    TKWoWControllerPadDiagram *_diagram;
    // Controls the drawing has no place for - paddles, Share, a touchpad - land here as taps.
    UIStackView *_chipsStack;
    // The rows on screen in chip order, so a tap names a binding rather than an index into a list
    // the page rebuilt underneath it.
    NSArray<AKControllerBinding *> *_rowBindings;
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

    UILabel *bindingsHeading = CMLabel(14, UIFontWeightRegular, CMMuted());
    _bindingsHeading = bindingsHeading;

    _diagram = [TKWoWControllerPadDiagram new];
    _diagram.translatesAutoresizingMaskIntoConstraints = NO;
    __weak TKWoWControllerManagerViewController *weakDiagramSelf = self;
    _diagram.onSourceTapped = ^(NSString *source) {
        TKWoWControllerManagerViewController *strongSelf = weakDiagramSelf;
        AKControllerModel *model = [strongSelf selectedModel];
        if (strongSelf && model) [strongSelf chooseTargetForSource:source identity:model.identity];
    };
    [_diagram.heightAnchor constraintEqualToAnchor:_diagram.widthAnchor multiplier:0.62].active = YES;

    _chipsStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    _chipsStack.axis = UILayoutConstraintAxisVertical;
    _chipsStack.spacing = 4;

    // The box for everything the picture cannot show. It is the same control as the old "reassign"
    // button, because that is what it is: press something on the pad, then say what it drives.
    _learnButton = [self boxButton:@"controllerManager.learn" title:WKLocalized(@"controller.learn.box")
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
                                              rows:@[_modelsControl, bindingsHeading, _diagram,
                                                     _learnButton, _hintLabel, _cancelButton,
                                                     _chipsStack, _resetButton]]];
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
    _hintLabel.text = WKLocalized(@"controller.learn.hint");
    _disclosureLabel.text = WKLocalized(@"controller.disclosure");
    // The box and the two commands are configured buttons; setTitle: does nothing to them.
    UIButtonConfiguration *boxConfiguration = _learnButton.configuration;
    boxConfiguration.title = WKLocalized(@"controller.learn.box");
    _learnButton.configuration = boxConfiguration;
    [_cancelButton setTitle:WKLocalized(@"controller.cancel") forState:UIControlStateNormal];
    [_resetButton setTitle:WKLocalized(@"controller.reset") forState:UIControlStateNormal];
    NSArray<NSString *> *sections = @[@"controller.section.routing", @"controller.section.model"];
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

// The catch-box: a field, because it is somewhere to put a control you press rather than a
// command to run.
- (UIButton *)boxButton:(NSString *)identifier title:(NSString *)title action:(SEL)action {
    UIButton *box = [UIButton buttonWithType:UIButtonTypeSystem];
    box.accessibilityIdentifier = identifier;
    UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration;
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:@"plus.circle"];
    configuration.imagePadding = 10;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(16, 16, 16, 16);
    configuration.baseForegroundColor = CMGold();
    configuration.background.backgroundColor = [CMGold() colorWithAlphaComponent:0.08];
    configuration.background.cornerRadius = 12;
    configuration.background.strokeColor = [CMGold() colorWithAlphaComponent:0.45];
    configuration.background.strokeWidth = 1;
    box.configuration = configuration;
    box.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [box addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return box;
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
            // On, but the guest adapter only loads when a session starts: say that rather
            // than "no controller", which would be true and useless.
            if (manager.enabled && !manager.guestFacadePresent)
                _statusLabel.text = WKLocalized(@"controller.status.pending");
            else if (manager.physicalControllerConnected)
                _statusLabel.text = WKLocalized(@"controller.status.connecting");
            else
                _statusLabel.text = WKLocalized(@"controller.status.nocontroller");
            break;
        case AKControllerRoutingStateRouting:
            _statusLabel.text = WKLocalized(@"controller.status.routing");
            break;
        case AKControllerRoutingStateFailed:
            _statusLabel.text = manager.guestFacadeAvailable
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

    AKControllerModel *model = models.count ? models[selected] : nil;
    _learnButton.enabled = model != nil && !manager.learning;
    _cancelButton.hidden = !manager.learning;
    _hintLabel.hidden = !manager.learning;
    _resetButton.enabled = model.customised;

    // What Tolkara is using on this model, asked once per render. The set comes from the feature
    // that owns the choice, so this page cannot disagree with the page that made it.
    NSSet<NSString *> *withheld = [NSSet setWithArray:
        model ? [manager withheldSourcesForIdentity:model.identity] : @[]];
    NSArray<AKControllerBinding *> *bindings = model.bindings ?: @[];

    NSMutableDictionary<NSString *, AKControllerBinding *> *bySource = [NSMutableDictionary dictionary];
    NSUInteger reachable = 0, routed = 0;
    for (AKControllerBinding *binding in bindings) {
        bySource[binding.source] = binding;
        if (!binding.available) continue;
        reachable++;
        if ([withheld containsObject:binding.source]) continue;
        if (binding.target.length && ![binding.target isEqualToString:AKControllerTargetNone]) routed++;
    }
    // The picture is the page. Its ink carries the same numbers this summary does, so the two can
    // never tell a different story.
    _diagram.bindings = bySource;
    _diagram.withheld = withheld;
    _diagram.waiting = manager.learning;
    _bindingsHeading.text = [NSString stringWithFormat:WKLocalized(@"controller.summary"),
                             (unsigned long)reachable, (unsigned long)routed,
                             (unsigned long)withheld.count];

    // Everything the picture has no place for, one tap each - paddles, Share, a touchpad, and any
    // control this pad reports that the drawing does not know. This is the box's answer as well as
    // its input: press something once and it lands here, already mappable.
    for (UIView *view in _chipsStack.arrangedSubviews) {
        [_chipsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<NSString *> *drawn = [TKWoWControllerPadDiagram drawnSources];
    NSMutableArray<AKControllerBinding *> *chips = [NSMutableArray array];
    for (AKControllerBinding *binding in bindings)
        if (![drawn containsObject:binding.source] && binding.source.length) [chips addObject:binding];
    // Controls this pad does not have go last: what it can actually do belongs at the top.
    [chips sortUsingComparator:^NSComparisonResult(AKControllerBinding *a, AKControllerBinding *b) {
        if (a.available != b.available) return a.available ? NSOrderedAscending : NSOrderedDescending;
        return [a.sourceDisplay compare:b.sourceDisplay];
    }];
    NSUInteger chipIndex = 0;
    for (AKControllerBinding *binding in chips)
        [_chipsStack addArrangedSubview:[self chipForBinding:binding index:chipIndex++ withheld:withheld]];
    _chipsStack.hidden = chips.count == 0;
    _rowBindings = [chips copy];

    if (!bindings.count) {
        UILabel *empty = CMLabel(15, UIFontWeightRegular, CMMuted());
        empty.text = WKLocalized(@"controller.nomodels");
        empty.accessibilityIdentifier = @"controllerManager.empty";
        [_chipsStack addArrangedSubview:empty];
        _chipsStack.hidden = NO;
    }
}

// One control the drawing cannot show: the control on the left, what it drives on the right, and a
// tap to change it. Same shape as a row, one line each, because there are only ever a few.
- (UIButton *)chipForBinding:(AKControllerBinding *)binding index:(NSUInteger)index
                    withheld:(NSSet<NSString *> *)withheld {
    BOOL kept = [withheld containsObject:binding.source];
    NSString *state;
    UIColor *colour;
    if (kept) {
        state = WKLocalized(@"controller.withheld.dictation");
        colour = CMGold();
    } else if (!binding.available) {
        state = WKLocalized(@"controller.row.absent");
        colour = CMMuted();
    } else if (!binding.target.length || [binding.target isEqualToString:AKControllerTargetNone]) {
        state = WKLocalized(@"controller.row.unmapped");
        colour = CMMuted();
    } else {
        state = binding.targetDisplay;
        colour = UIColor.whiteColor;
    }
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration;
    configuration.title = [NSString stringWithFormat:@"%@  →  %@", binding.sourceDisplay, state];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(7, 12, 7, 12);
    configuration.baseForegroundColor = colour;
    configuration.background.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.06];
    configuration.background.cornerRadius = 10;
    chip.configuration = configuration;
    chip.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    chip.tag = (NSInteger)index;
    chip.accessibilityIdentifier = [NSString stringWithFormat:@"controllerManager.binding.%lu",
                                    (unsigned long)index];
    chip.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", binding.sourceDisplay, state];
    [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
    return chip;
}

- (void)chipTapped:(UIButton *)sender {
    AKControllerModel *model = [self selectedModel];
    if (!model || sender.tag < 0 || (NSUInteger)sender.tag >= _rowBindings.count) return;
    [self chooseTargetForSource:_rowBindings[(NSUInteger)sender.tag].source identity:model.identity];
}

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
