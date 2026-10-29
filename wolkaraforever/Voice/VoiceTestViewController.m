// WolkaraForever: trying the voice button before the game is started, in full.
//
// This screen is deliberately only an output. The button does not get its own copy of
// the routing: Shell/main.m sends the mapped trigger to the microphone, so what is
// exercised here is the same path the game will use. All this screen does is take the
// words instead of the game, and say what it heard.
//
// It is also the one place the *state* of a dictation session is visible, which is what
// the state machine added for the 2026-10-16 audit is for: authorizing, listening,
// finalizing. A session that never leaves "finalizing" and one that never starts look
// identical from the outside otherwise.
//
// Drawn from WolkaraForeverTheme, so it is the same navy and gold as the settings screen and
// the Add-on Manager beside it.

#import "VoiceTestViewController.h"

#import <GameController/GameController.h>

#import "Dictation.h"
#import "VoiceSettings.h"
#import "Trigger.h"
#import "../Input/InputElement.h"
#import "../Controller/ControllerInspector.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"

@interface AKVoiceTestViewController ()
@property (nonatomic, strong) UILabel *buttonLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UITextView *box;
@property (nonatomic, strong) UILabel *hint;
@end

@implementation AKVoiceTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = WKLocalized(@"voice.test.title").uppercaseString;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = WKInk();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done")
        style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    self.navigationItem.leftBarButtonItem.tintColor = WKGold();

    UIScrollView *scroll = [UIScrollView new];
    scroll.accessibilityIdentifier = @"voice.test.scroll";
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *rows = [[UIStackView alloc] init];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 20;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:rows];

    [rows addArrangedSubview:WKNote(WKLocalized(@"voice.test.note"))];

    self.buttonLabel = WKLabel(16, UIFontWeightSemibold, UIColor.whiteColor);
    self.buttonLabel.accessibilityIdentifier = @"voice.test.button";
    self.stateLabel = WKLabel(15, UIFontWeightRegular, WKMuted());
    self.stateLabel.accessibilityIdentifier = @"voice.test.state";
    [rows addArrangedSubview:[self card:@[self.buttonLabel, self.stateLabel]]];

    self.box = [[UITextView alloc] init];
    self.box.accessibilityIdentifier = @"voice.test.box";
    self.box.backgroundColor = WKPanel();
    self.box.textColor = UIColor.whiteColor;
    self.box.tintColor = WKGold();
    self.box.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.box.adjustsFontForContentSizeCategory = YES;
    self.box.layer.cornerRadius = 12;
    self.box.layer.borderWidth = 1;
    self.box.layer.borderColor = [WKGold() colorWithAlphaComponent:0.24].CGColor;
    self.box.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    // Editable on purpose: the text that arrived is theirs to correct, and doing that
    // here is how the dictionary and the mode get judged.
    [self.box.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [rows addArrangedSubview:self.box];

    self.hint = WKNote(@"");
    self.hint.accessibilityIdentifier = @"voice.test.hint";
    [rows addArrangedSubview:self.hint];

    UIButton *clear = WKRowButton(@"voice.test.clear");
    [clear setTitle:WKLocalized(@"common.clear") forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clearBox) forControlEvents:UIControlEventTouchUpInside];
    [rows addArrangedSubview:clear];

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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    AKDictation *dictation = AKDictation.shared;
    __weak AKVoiceTestViewController *weakSelf = self;
    dictation.transcriptHandler = ^(NSString *text) {
        [weakSelf appendTranscript:text];
    };
    dictation.listeningChanged = ^(BOOL listening) {
        [weakSelf showListening:listening];
    };
    dictation.stateChanged = ^(AKDictationState state) {
        [weakSelf showState:state];
    };
    dictation.problemHandler = ^(NSString *message) {
        weakSelf.hint.text = message;
    };
    [self refreshButton];
    [self showState:dictation.state];
    WKLog("voice", @"test screen armed on %@", [AKVoiceSettings.shared mappingSummaryForDevice:[self deviceIdentity]]);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    AKDictation *dictation = AKDictation.shared;
    // Cancel, not end. Ending asks the recogniser for its last words and delivers them
    // - and the screen that asked for them is going away, so the words would be typed
    // into the game as the sheet closes. Nothing heard here is worth that.
    [dictation cancel];
    dictation.transcriptHandler = nil;
    dictation.listeningChanged = nil;
    dictation.stateChanged = nil;
    dictation.problemHandler = nil;
}

- (void)done { WKDismissPage(self); }

#pragma mark - What arrives

// Shown exactly as the game would receive it: the text, and the trailing space if that
// option is on. One utterance per line, because the box is read by eye.
- (void)appendTranscript:(NSString *)text {
    if (!text.length) {
        double peak = AKVoiceLoudestSample();
        self.hint.text = WKLocalizedFormat(@"voice.test.nothingHeard", peak);
        return;
    }
    if (AKVoiceSettings.shared.trailingSpace) text = [text stringByAppendingString:@" "];
    NSString *current = self.box.text ?: @"";
    self.box.text = current.length ? [current stringByAppendingFormat:@"\n%@", text] : text;
    NSMutableString *said = [NSMutableString stringWithFormat:@"%@",
        WKLocalizedCountFormat(@"voice.test.heard",(NSInteger)text.length,(unsigned long)text.length)];
    if (AKVoiceSettings.shared.autoSubmit) [said appendString:WKLocalized(@"voice.test.return")];
    self.hint.text = said;
    [self.box scrollRangeToVisible:NSMakeRange(self.box.text.length, 0)];
}

- (void)clearBox {
    self.box.text = @"";
    self.hint.text = nil;
}

#pragma mark - What to press, and what it is doing

- (nullable NSString *)deviceIdentity {
    GCController *pad = GCController.controllers.firstObject;
    return pad ? AKControllerIdentity(pad) : nil;
}

- (void)refreshButton {
    GCController *pad = GCController.controllers.firstObject;
    NSString *device = [self deviceIdentity];
    NSString *summary = [AKVoiceSettings.shared mappingSummaryForDevice:device];
    BOOL toggle = AKVoiceSettings.shared.mode == AKVoiceModeToggle;
    // The settings object's own word for no mapping, shown in the app's language.
    if ([summary isEqualToString:@"Not set"]) summary = WKLocalized(@"voice.mapping.notSet");
    NSString *state = AKVoiceSettings.shared.enabled ? @"" : WKLocalized(@"voice.test.off");
    self.buttonLabel.text = [NSString stringWithFormat:@"%@\n%@%@",
        pad ? WKLocalizedFormat(@"voice.mapping.device", summary, pad.vendorName)
            : WKLocalizedFormat(@"voice.mapping.noController", summary),
        toggle ? WKLocalized(@"voice.test.tapOnce")
               : WKLocalized(@"voice.test.hold"),
        state.length ? [@"\n" stringByAppendingString:state] : @""];
}

- (void)showListening:(BOOL)listening {
    // The coarse answer, kept because the switch from "off" to "on" is what the user
    // cares about most; showState: refines it.
    if (!listening) self.stateLabel.textColor = WKMuted();
}

- (void)showState:(AKDictationState)state {
    NSString *text = nil;
    switch (state) {
    case AKDictationStateIdle: text = WKLocalized(@"voice.state.off"); break;
    case AKDictationStateAuthorizing: text = WKLocalized(@"voice.state.authorizing"); break;
    case AKDictationStateListening: text = WKLocalized(@"voice.state.listening"); break;
    case AKDictationStateFinalizing: text = WKLocalized(@"voice.state.finalizing"); break;
    }
    self.stateLabel.text = text;
    BOOL busy = state != AKDictationStateIdle;
    self.stateLabel.textColor = busy ? WKGold() : WKMuted();
}

#pragma mark - Small pieces

- (UIView *)card:(NSArray<UIView *> *)rows {
    UIView *panel = WKCard();
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
    ]];
    return panel;
}

@end
