#import "TouchControls.h"
#import "AKSupport.h"
#import "AKHostLocalization.h"
#import "InterfaceMode.h"
#import "TouchTrackpad.h"
#import "TouchCamera.h"
#import "ControllerPointer.h"
#import "TouchControllerLog.h"
#import "TouchGamepadLayout.h"
#import "TouchGamepad.h"
#import "TouchHaptics.h"
#import "TouchAreas.h"
#import "TouchTextBridge.h"
#import "TouchWorldSignal.h"
#import <objc/message.h>

// Null until the app's shell says which keys are the user's; null means "nothing is owned",
// which is the behaviour without the feature and what a fixture that links only the adapter
// gets.
// Posted when the game's own text view exists, with that view as the object. Dictation
// types into it and nowhere else; the alternative - searching every window in every
// scene for something that answers a private selector - is not a thing to do while a
// game is running. Shell/main.m is the observer, because it is what knows about both
// this adapter and the voice module.
NSNotificationName const AKTouchGameTextInputDidAppearNotification = @"AKTouchGameTextInputDidAppear";

// The draft editor's composition, as an event rather than as text. See the header: the phase is
// the whole payload, and the app turns it into the bounded `keyboard-dictation: composition.*`
// line. Nothing here reads or forwards what was composed.
NSNotificationName const AKTouchDraftCompositionDidChangeNotification = @"AKTouchDraftCompositionDidChange";
NSString *const AKTouchDraftCompositionPhaseKey = @"phase";
NSString *const AKTouchDraftCompositionCommit = @"commit";
NSString *const AKTouchDraftCompositionCancel = @"cancel";

// The speech language as the composer shows and asks for it. `stored` is the bounded spelling
// the voice module persists; this file never decides what a language is, it only names one.
NSNotificationName const AKTouchSpeechLanguageRequestNotification = @"AKTouchSpeechLanguageRequest";
NSNotificationName const AKTouchSpeechLanguageDidChangeNotification = @"AKTouchSpeechLanguageDidChange";
NSString *const AKTouchSpeechLanguageStoredKey = @"stored";

// The value in force, as last published by the shell. A file static rather than an ivar because
// a composer is built and thrown away with the keyboard, and the choice must survive that.
static NSString *AKSpeechLanguageStored;

// The localization key naming a stored language. Anything else is System, which is also what the
// voice module migrates an unknown value to.
static NSString *AKSpeechLanguageNameKey(NSString *stored) {
    if ([stored isEqualToString:@"en-US"]) return @"voice.language.english";
    if ([stored isEqualToString:@"de-DE"]) return @"voice.language.german";
    if ([stored isEqualToString:@"fr-FR"]) return @"voice.language.french";
    if ([stored isEqualToString:@"es-ES"]) return @"voice.language.spanish";
    return @"voice.language.system";
}

NSNotificationName const AKTouchKeyboardRequestNotification = @"AKTouchKeyboardRequestNotification";
// Posted when the user has asked to leave twice and the guest still refused to quit: the shell,
// which owns the session and what it has to flush, closes WolkaraForever. Named as a string on the
// shell's side for the same reason as the two notifications above - the adapter is a dylib the
// app does not link.
NSNotificationName const AKTouchCloseAppNotification = @"AKTouchCloseAppNotification";
// The microphone key on the layer's own keyboard. The voice module is not this one's to
// include, and the shell is the only place that links both, so the key announces and the
// shell starts or stops dictation.
NSNotificationName const AKTouchDictationToggleNotification = @"AKTouchDictationToggleNotification";
// The keys the launcher's and the platform's switches read. The trackpad string
// is the one the platform already stored, so an existing choice carries over.
NSString *const AKTouchControlsDefaultsKey = @"AKTouchControls";

// The Composer's crossings. See TouchControls.h for why they are notifications.
NSNotificationName const AKChatComposerOpenNotification = @"AKChatComposerOpen";
NSString *const AKChatComposerSourceKey = @"source";
NSString *const AKChatComposerPhaseKey = @"phase";
NSNotificationName const AKChatComposerVoiceRequestNotification = @"AKChatComposerVoiceRequest";
NSString *const AKChatComposerActionKey = @"action";
NSString *const AKChatComposerGenerationKey = @"generation";
NSNotificationName const AKChatComposerVoiceEventNotification = @"AKChatComposerVoiceEvent";
NSString *const AKChatComposerEventKey = @"event";
NSString *const AKChatComposerTextKey = @"text";
NSString *const AKChatComposerReasonKey = @"reason";
NSNotificationName const AKChatComposerOpenResultNotification = @"AKChatComposerOpenResult";
NSString *const AKChatComposerOutcomeKey = @"outcome";
// The guest's Return, used by the Composer's chat target; Escape is posted in
// ChatComposer.m, which owns the closing decision.
static unsigned short const AKKeyReturnCode = 36;
static NSString *const AKTouchTrackpadDefaultsKey = @"TKTouchTrackpadEnabled";
// iPad touch's own trackpad switch. Its plain touches are a click where the finger is (0055), and a trackpad
// turned on in another interface must not carry into it: on the iPad (IPAD RUN 2) the shared switch, left on
// from an earlier interface, made every tap on the character screen click at the cursor instead.
static NSString *const AKTouchTrackpadIPadTouchDefaultsKey = @"WolkaraForeverIPadTouchTrackpadEnabled";
// Whether the top toolbar is folded into its handle. Folded unless the user left it open.
static NSString *const AKTouchToolbarCollapsedDefaultsKey = @"WolkaraForeverToolbarCollapsed";
// An open toolbar folds itself away after this long without a tap on it.
static const NSTimeInterval AKTouchToolbarAutoCollapse = 6;
// A software keyboard's keys are several hundred points tall; a keyboard frame
// this small is the shortcut bar alone, which is what iPadOS shows for a
// hardware keyboard. Its microphone key is part of the keys that are hidden.
static CGFloat const AKKeyboardKeysHeight = 150;
// The draft card's height in each mode. Classic is the height every release through v1.0.10 has
// had; the Composer adds one 44-point action row beneath the draft and keeps every control where
// it was.
static CGFloat const AKComposerCardHeightClassic = 82;
static CGFloat const AKComposerCardHeightComposer = 130;
// The composer's placeholder when nothing has been dictated or typed: it says what the field
// does, so an empty box is not mistaken for the game's own text.
//
// The mobile interface sends a line to the chat from the keyboard, so its placeholder says so.
// The Standard interface keeps the sentence it has always had. Chosen once, when the controls
// are made, from the same key every other gated path reads.
static NSString *AKComposerDefaultLabel(BOOL mobile) {
    return AKHostLocalized(mobile ? @"touch.draft.placeholder.mobile" : @"touch.draft.placeholder");
}
// The draft card follows the player's text size. It sits over a game, so the card keeps the
// proportions it has always drawn and grows its rows instead of reflowing the game underneath.
//
// The fonts come from `preferredFontForTextStyle:`, which at the default category returns exactly
// the sizes the card has always used - Caption 1 is 12, Headline is 17, Subheadline is 15 - and
// which UIKit keeps current while `adjustsFontForContentSizeCategory` is on. The heights are read
// back from those fonts, so a title is never given less room than it needs.
static UIFont *AKComposerFont(UIFontTextStyle style, BOOL bold) {
    UIFont *base = [UIFont preferredFontForTextStyle:style];
    if (!bold) return base;
    UIFontDescriptor *descriptor = base.fontDescriptor;
    descriptor = [descriptor fontDescriptorWithSymbolicTraits:
                  descriptor.symbolicTraits | UIFontDescriptorTraitBold];
    return descriptor ? ([UIFont fontWithDescriptor:descriptor size:0] ?: base) : base;
}
// The label's row, the action row and a destination chip: their historic minimums, or the height
// of the text they hold at the player's size, whichever is larger.
static CGFloat AKComposerLabelBox(UIFont *font) { return MAX(16, ceil(font.lineHeight)); }
static CGFloat AKComposerActionBox(UIFont *font) { return MAX(44, ceil(font.lineHeight) + 16); }
static CGFloat AKComposerChipBox(UIFont *font) { return MAX(32, ceil(font.lineHeight) + 8); }
// GameController's own class, asked by name: this adapter's headers carry a
// GCKeyboard of their own for the guest.
static BOOL hardwareKeyboardAttached(void) {
    Class cls = NSClassFromString(@"GCKeyboard"); if (!cls) return NO;
    SEL sel = NSSelectorFromString(@"coalescedKeyboard"); if (![cls respondsToSelector:sel]) return NO;
    id (*call)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return call((id)cls, sel) != nil;
}

@interface AKTouchControls (KeyboardState)
- (void)updateKeyboardButton;
- (void)updateDraftButtons;
- (void)replaceGameText:(NSString *)text;
- (void)sendChatText:(NSString *)text;
// Brings up the layer's own keys when iPadOS has no software keyboard to give.
- (void)showLayerKeyboard;
// YES while the user has asked for the draft keyboard and it has not been
// dismissed: the draft editor uses it to decide whether to take focus back when
// a system panel (dictation) has finished with it.
- (BOOL)keyboardRequested;
// The draft editor gave up the keyboard on its own (not for dictation): the request it was opened for is over, so it
// takes the keyboard again only when its owner asks (device fix 2).
- (void)draftEditorLetGo;
@end

// The Composer's card, which this file draws because it is the file that owns the draft editor,
// the keyboard geometry and the guest's key path.
@interface AKTouchControls (ChatComposer)
- (void)beginChatComposer;
- (void)applyComposerState;
- (BOOL)composerActive;
- (BOOL)composerInReviewMode;
- (void)draftEditorChanged:(NSString *)text;
- (void)composerTakesDraft:(NSString *)text;
- (void)showComposerSettings;
@end

// What the layer's keyboard asks its owner to do. Words go to the game the same
// way dictation's do; the special keys are the guest's own key events.
@protocol AKTouchKeyboardSink <NSObject>
- (void)keyboardViewType:(NSString *)text;
- (void)keyboardViewBackspace;
- (void)keyboardViewReturn;
- (void)keyboardViewShowSystemKeyboard;
- (void)keyboardViewToggleDictation;
@end

@interface AKTouchControls () <AKTouchKeyboardSink, AKTouchTextSink>
@end

// A normal, visible UIKit document. Editing and dictation stay local until
// Replace is requested; never reset the text context on every keyboard callback.
@interface AKKeyboardTextView : UITextView <UITextViewDelegate>
@property (nonatomic, weak) AKTouchControls *inputOwner;
- (BOOL)forwardCommittedText;
- (BOOL)sendDraftToChat;
- (void)discardDraft;
- (BOOL)canModifyDraft;
- (BOOL)canReplaceField;
@end

@implementation AKKeyboardTextView {
    NSMutableSet *_dictationPlaceholders;
    BOOL _acceptingInput, _didSubmitDraft, _resignedForDictation;
    // Whether UIKit is holding provisional (marked) text in this document. The marked text
    // itself stays native and local: this is only so a commit and a cancellation can be told
    // apart and announced as an event, never read.
    BOOL _composing;
    // Read once, as the controls do: Standard keeps idiOS's Done key replacing the selected
    // field, which is the behaviour every release through v1.0.7 has.
    BOOL _mobileInterface;
    // iPad touch (AKInterfaceModeIsTouchPlay), read once with the interface: the draft's own iPad touch rules below
    // (a typed newline is Return, only its owner opens it) apply there and nowhere else.
    BOOL _touchPlay;
    NSUInteger _session;
}
- (instancetype)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)container {
    if ((self = [super initWithFrame:frame textContainer:container])) {
        self.delegate = self;
        _dictationPlaceholders = [NSMutableSet new];
        self.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        self.textColor = UIColor.whiteColor;
        self.tintColor = UIColor.systemCyanColor;
        self.font = [UIFont systemFontOfSize:17];
        self.layer.cornerRadius = 8;
        self.accessibilityLabel = AKHostLocalized(@"touch.draft.label");
        self.accessibilityHint = AKHostLocalized(@"touch.draft.hint");
        self.accessibilityLanguage = AKHostLanguageCode();
        self.accessibilityIdentifier = @"wolkaraforever.keyboard.draft";
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.smartQuotesType = UITextSmartQuotesTypeNo;
        self.smartDashesType = UITextSmartDashesTypeNo;
        self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        _mobileInterface = AKInterfaceModeIsMobile();
        _touchPlay = AKInterfaceModeIsTouchPlay();
        self.returnKeyType = _mobileInterface ? UIReturnKeySend : UIReturnKeyDone;
        self.secureTextEntry = NO;
    }
    return self;
}
- (UIView *)inputAccessoryView { return self.inputOwner.inputAccessoryView; }
- (BOOL)canModifyDraft { return _acceptingInput && !_dictationPlaceholders.count && !self.markedTextRange; }
- (BOOL)canReplaceField { return [self canModifyDraft] && (self.hasText || !_didSubmitDraft); }
- (void)textViewDidChange:(UITextView *)view {
    (void)view;
    // iPad touch: a newline that reached the end of the draft past the delegate is the keyboard's Return too: taken out,
    // and sent. A pasted text with lines in it is left alone (its newlines become spaces when it is sent).
    if (_touchPlay && _acceptingInput && ([self.text hasSuffix:@"\n"] || [self.text hasSuffix:@"\r"])) {
        [super setText:[[self.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@""]];
        _didSubmitDraft = NO;
        [self returnPressed];
        return;
    }
    _didSubmitDraft = NO;
    [self.inputOwner draftEditorChanged:self.text];
    [self.inputOwner updateDraftButtons];
}
- (void)textViewDidChangeSelection:(UITextView *)view { (void)view; [self.inputOwner updateDraftButtons]; }
- (void)discardDraft {
    BOOL wasComposing = _composing || self.markedTextRange != nil;
    [super setText:@""];
    [self.undoManager removeAllActions];
    // A draft thrown away with provisional text in it is a cancelled composition: what was
    // being composed never became text anywhere.
    if (wasComposing) {
        _composing = NO;
        [self announceComposition:AKTouchDraftCompositionCancel];
    }
    [self.inputOwner updateDraftButtons];
}
- (BOOL)forwardCommittedText {
    if (![self canReplaceField]) return NO;
    // Drafts cannot send Return/Tab or other control keys by pasting text.
    // Those keys remain explicit actions in the accessory bar.
    NSString *text = [[self.text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]
        componentsJoinedByString:@" "];
    [self discardDraft];
    // Once cleared after submission, repeated taps/queued Done callbacks must
    // not turn a successful replacement into an accidental empty replacement.
    _didSubmitDraft = YES;
    [self.inputOwner updateDraftButtons];
    [self.inputOwner replaceGameText:text];
    return YES;
}
// Return on the keyboard: the words go to the game's chat the way a player types them, and
// the keyboard goes away. Slash commands are chat lines too, so /reload works the same way.
- (BOOL)sendDraftToChat {
    if (![self canModifyDraft]) return NO;
    NSString *text = [[[self.text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]
        componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    // Once a line has gone, a repeated or queued Return has nothing to send: a bare Return
    // would open the game's chat box again. A first Return with nothing typed still is one.
    if (!text.length && _didSubmitDraft) return NO;
    // Review mode: Return is an explicit Send, and it goes through the Composer's transaction -
    // one insertion, one Return, one Escape - rather than straight into the guest.
    if ([self.inputOwner composerInReviewMode]) {
        if (!text.length) return NO;
        _didSubmitDraft = YES;
        [self.inputOwner composerTakesDraft:text];
        return YES;
    }
    [self discardDraft];
    _didSubmitDraft = YES;
    [self.inputOwner sendChatText:text];
    return YES;
}
// iPad touch: only its owner opens the draft editor; something else asking it to take the keyboard is refused. UIKit's
// AutoFill gathers every text input in the window into a login group and, with the password field closed, asks the
// group's other members to take the keyboard and fills them: in the fixture the chat draft took the account's e-mail
// address and came up with it, one tap from sending it to the game's chat. Every other mode is UIKit's answer.
- (BOOL)canBecomeFirstResponder {
    if (_touchPlay && !self.inputOwner.keyboardRequested) return NO;
    return [super canBecomeFirstResponder];
}
- (BOOL)becomeFirstResponder {
    if (!self.isFirstResponder) _didSubmitDraft = NO;
    _acceptingInput = YES;
    BOOL accepted = [super becomeFirstResponder];
    _acceptingInput = accepted;
    [self.inputOwner updateKeyboardButton];
    return accepted;
}
- (BOOL)resignFirstResponder {
    BOOL accepted = [super resignFirstResponder];
    if (accepted) {
        _session++;
        if (_dictationPlaceholders.count) {
            // The system dictation UI takes focus while the microphone listens.
            // The draft and the pending result are the user's: keep both, and
            // take focus back when the session ends (endDictationSessionIfIdle).
            // Only a pending dictation placeholder says so: text a keyboard is
            // still composing is discarded like any other draft.
            _resignedForDictation = YES;
            AKLog(@"draft editor resigned with dictation pending; keeping the draft");
        } else {
            _acceptingInput = NO;
            [_dictationPlaceholders removeAllObjects];
            // Closing the keyboard is how a composition is abandoned, so the draft - and any
            // provisional text in it - goes, and the cancellation is announced once.
            [self discardDraft];
            if (_touchPlay) [self.inputOwner draftEditorLetGo];
        }
    }
    [self.inputOwner updateKeyboardButton];
    return accepted;
}
// The dictation session has finished. If it left the editor without focus, take
// it back so the dictated draft is visible and Replace works, as it was before.
- (void)endDictationSessionIfIdle {
    if (_dictationPlaceholders.count || self.markedTextRange || !_resignedForDictation) return;
    _resignedForDictation = NO;
    if (!self.inputOwner.keyboardRequested) return;
    AKLog(@"dictation session ended without focus; restoring the draft keyboard");
    __weak AKKeyboardTextView *weakSelf = self;
    [NSRunLoop.mainRunLoop performInModes:@[NSRunLoopCommonModes] block:^{
        AKKeyboardTextView *input = weakSelf;
        if (input && input.inputOwner.keyboardRequested && !input.isFirstResponder) [input becomeFirstResponder];
    }];
}
// The keyboard's Return. Mobile: Send puts the draft in the game's chat, exactly as the Send button does (Replace is the
// button that only fills the selected field). Standard: Done replaces the field, as it always has. Deferred until UIKit
// finishes the edit that brought it; this never mutates its document from inside that edit.
- (void)returnPressed {
    BOOL mobile = _mobileInterface;
    NSUInteger session = _session;
    __weak AKKeyboardTextView *weakSelf = self;
    [NSRunLoop.mainRunLoop performInModes:@[NSRunLoopCommonModes] block:^{
        AKKeyboardTextView *input = weakSelf;
        if (!input || input->_session != session) return;
        if (mobile) [input sendDraftToChat]; else [input forwardCommittedText];
    }];
}
- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    (void)textView; (void)range;
    if ([text isEqual:@"\n"]) { [self returnPressed]; return NO; }
    return _acceptingInput;
}
// iPad touch: the keyboard's Return can also arrive as a newline typed straight in (on the iPad the blue Send key did not
// send; only the Send button did). There every way in is the same Return: never a newline in the draft.
- (void)insertText:(NSString *)text {
    BOOL wasComposing = _composing || self.markedTextRange != nil;
    if (_touchPlay && _acceptingInput && ([text isEqual:@"\n"] || [text isEqual:@"\r"])) [self returnPressed];
    else if (_acceptingInput) [super insertText:text];
    // UIKit hands a composed sequence over as one insertion. Announcing the commit here is
    // what makes "committed" mean the same thing to the log and to the guest: the text that
    // reaches the game is the string UIKit committed, not a re-derivation of it.
    if (wasComposing) {
        _composing = NO;
        [self announceComposition:AKTouchDraftCompositionCommit];
    }
}
- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    if (_acceptingInput) [super replaceRange:range withText:text];
}
- (void)setMarkedText:(NSString *)text selectedRange:(NSRange)range {
    if (_acceptingInput) [super setMarkedText:text selectedRange:range];
    // An empty marked string is how UIKit ends a composition, but whether it ended as a commit
    // or a cancellation is only known when `insertText:` or `unmarkText` arrives. So the flag
    // is raised here and cleared by whichever of those comes next.
    if (_acceptingInput && text.length) _composing = YES;
}
- (void)unmarkText {
    BOOL wasComposing = _composing || self.markedTextRange != nil;
    if (_acceptingInput) [super unmarkText];
    if (wasComposing) {
        _composing = NO;
        [self announceComposition:AKTouchDraftCompositionCancel];
    }
}
// The one place the two phases are produced. Only the phase goes anywhere: a composition's
// text is the user's, and the log is not a place for it.
- (void)announceComposition:(NSString *)phase {
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchDraftCompositionDidChangeNotification
                                                     object:self
                                                   userInfo:@{AKTouchDraftCompositionPhaseKey: phase}];
}
- (id)insertDictationResultPlaceholder {
    // Dictation can start while the system panel, not this editor, holds focus:
    // the result is still the user's draft, so accept it from here on. UIKit also
    // requires a placeholder for the session to start at all: refusing it is how
    // "the microphone is visible but tapping it does nothing" looks.
    _acceptingInput = YES;
    // UITextView implements the dictation selectors on some systems and not on
    // others, and sending one it does not have aborts the app. Ask first, and
    // hand back our own token when the superclass has nothing, because the
    // session cannot start without a placeholder.
    id placeholder = nil;
    if ([UITextView instancesRespondToSelector:@selector(insertDictationResultPlaceholder)]) {
        placeholder = [super insertDictationResultPlaceholder];
    }
    if (!placeholder) placeholder = [[NSObject alloc] init];
    [_dictationPlaceholders addObject:placeholder];
    AKLog(@"dictation placeholder inserted=%d pending=%lu accepting=%d", placeholder != nil, (unsigned long)_dictationPlaceholders.count, _acceptingInput);
    [self.inputOwner updateDraftButtons];
    return placeholder;
}
- (void)removeDictationResultPlaceholder:(id)placeholder willInsertResult:(BOOL)willInsert {
    if (![_dictationPlaceholders containsObject:placeholder]) return;
    if ([UITextView instancesRespondToSelector:@selector(removeDictationResultPlaceholder:willInsertResult:)]) {
        [super removeDictationResultPlaceholder:placeholder willInsertResult:willInsert];
    }
    [_dictationPlaceholders removeObject:placeholder];
    AKLog(@"dictation placeholder removed willInsertResult=%d pending=%lu", willInsert, (unsigned long)_dictationPlaceholders.count);
    [self.inputOwner updateDraftButtons];
    [self endDictationSessionIfIdle];
}
// Lengths only: never log or retain what was dictated.
- (void)insertDictationResult:(NSArray<UIDictationPhrase *> *)dictationResult {
    NSUInteger characters = 0;
    for (UIDictationPhrase *phrase in dictationResult) characters += phrase.text.length;
    AKLog(@"dictation result: %lu phrases, %lu characters", (unsigned long)dictationResult.count, (unsigned long)characters);
    // UITextView does not implement this selector. UIKit sends it to whichever
    // responder holds the session's placeholder, so forwarding it to super
    // raises NSInvalidArgumentException and the app dies the instant dictation
    // finishes. Insert the phrases as ordinary input instead, the same way the
    // dictated text would have arrived.
    _acceptingInput = YES;
    for (UIDictationPhrase *phrase in dictationResult) {
        if (phrase.text.length) [self insertText:phrase.text];
    }
    [self.inputOwner updateDraftButtons];
}
- (void)dictationRecognitionFailed {
    AKLog(@"dictation recognition failed (markedText=%d, placeholders=%lu)", self.markedTextRange != nil, (unsigned long)_dictationPlaceholders.count);
    // UITextView does not implement this optional callback. Preserve the
    // completed draft; only discard the provisional recognition segment.
    BOOL wasComposing = _composing || self.markedTextRange != nil;
    if (self.markedTextRange) {
        [super setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
        [super unmarkText];
    }
    if (wasComposing) {
        _composing = NO;
        [self announceComposition:AKTouchDraftCompositionCancel];
    }
    [_dictationPlaceholders removeAllObjects];
    [self.inputOwner updateDraftButtons];
    [self endDictationSessionIfIdle];
}
@end

// The layer's own keyboard.
//
// iPadOS hides the software keyboard when it believes a hardware keyboard is
// attached, and what it reports then is the shortcut bar alone or nothing at all.
// Measured on Dadpad, 2026-10-22: "system keyboard shown draftFirstResponder=1
// height=0", with the game's login field unable to take the @ an e-mail address
// needs, and no other route to type one. A custom input view is shown whatever
// the hardware says, so these keys are always there. They type through the same
// delegate dictation uses, which turns text into the guest's own key events, so
// the game's field sees ordinary typing. The system-keyboard key hands the input
// view back for dictation's microphone when iPadOS will show it.
@interface AKTouchKeyboardView : UIView
@property (nonatomic, weak) id<AKTouchKeyboardSink> sink;
@end

@implementation AKTouchKeyboardView {
    BOOL _shift, _symbols;
    UIStackView *_column;
    NSArray<NSDictionary *> *_specs;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        _column = [UIStackView new];
        _column.axis = UILayoutConstraintAxisVertical;
        _column.spacing = 6;
        _column.distribution = UIStackViewDistributionFillEqually;
        _column.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_column];
        [NSLayoutConstraint activateConstraints:@[
            [_column.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [_column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        ]];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self rebuild];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 236); }
- (void)rebuild {
    for (UIView *view in _column.arrangedSubviews) { [_column removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSMutableArray<NSDictionary *> *specs = [NSMutableArray new];
    NSArray<NSArray<NSString *> *> *rows;
    if (_symbols) {
        rows = @[@[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0"],
                 @[@"-", @"_", @"+", @"=", @"/", @":", @";", @"(", @")"],
                 @[@"#", @"$", @"%", @"&", @"*", @"\"", @"'", @"!", @"?"],
                 @[@"ABC", @" ", @"@", @".", @"🎤", @"⌨", @"↵"]];
    } else {
        NSString *top = _shift ? @"QWERTYUIOP" : @"qwertyuiop";
        NSString *home = _shift ? @"ASDFGHJKL" : @"asdfghjkl";
        NSString *bottom = _shift ? @"ZXCVBNM" : @"zxcvbnm";
        NSMutableArray<NSString *> *third = [NSMutableArray arrayWithObject:@"⇧"];
        for (NSUInteger i = 0; i < bottom.length; i++) [third addObject:[bottom substringWithRange:NSMakeRange(i, 1)]];
        [third addObject:@"⌫"];
        rows = @[[self keysIn:top], [self keysIn:home], third,
                 @[@"123", @" ", @"@", @".", @"🎤", @"⌨", @"↵"]];
    }
    for (NSArray<NSString *> *row in rows) {
        NSMutableArray<UIView *> *buttons = [NSMutableArray new];
        for (NSString *title in row) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            [button setTitle:title forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:title.length > 1 ? 15 : 20];
            button.tintColor = UIColor.whiteColor;
            button.backgroundColor = [self actionTitle:title] ? [UIColor colorWithWhite:0.34 alpha:1]
                                                              : [UIColor colorWithWhite:0.26 alpha:1];
            button.layer.cornerRadius = 6;
            button.tag = (NSInteger)specs.count;
            button.accessibilityIdentifier = [@"wolkaraforever.layerkey." stringByAppendingString:
                [self actionTitle:title] ?: [self accessibilityNameFor:title]];
            NSString *nameKey = AKKeyAccessibilityNameKey(title);
            button.accessibilityLabel = nameKey ? AKHostLocalized(nameKey) : [self accessibilityNameFor:title];
            [button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
            [specs addObject:@{@"title": title}];
            [buttons addObject:button];
        }
        UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:buttons];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = 5;
        line.distribution = UIStackViewDistributionFillEqually;
        [_column addArrangedSubview:line];
    }
    _specs = specs;
}
- (NSArray<NSString *> *)keysIn:(NSString *)letters {
    NSMutableArray<NSString *> *keys = [NSMutableArray new];
    for (NSUInteger i = 0; i < letters.length; i++) [keys addObject:[letters substringWithRange:NSMakeRange(i, 1)]];
    return keys;
}
// The keys that are actions rather than characters, by the title drawn on them.
- (NSString *)actionTitle:(NSString *)title {
    if ([title isEqual:@"⇧"]) return @"shift";
    if ([title isEqual:@"⌫"]) return @"delete";
    if ([title isEqual:@"↵"]) return @"return";
    if ([title isEqual:@"🎤"]) return @"dictate";
    if ([title isEqual:@"⌨"]) return @"system";
    if ([title isEqual:@"123"]) return @"page";
    if ([title isEqual:@"ABC"]) return @"page";
    return nil;
}
- (NSString *)accessibilityNameFor:(NSString *)title {
    if ([title isEqual:@"⇧"]) return @"Shift";
    if ([title isEqual:@"⌫"]) return @"Backspace";
    if ([title isEqual:@"↵"]) return @"Return";
    if ([title isEqual:@"🎤"]) return @"Dictate";
    if ([title isEqual:@"⌨"]) return @"System keyboard";
    if ([title isEqual:@"123"]) return @"Numbers and symbols";
    if ([title isEqual:@"ABC"]) return @"Letters";
    if ([title isEqual:@" "]) return @"Space";
    return title;
}
// The localization key for a named key, or nil when the key is its own name in every language:
// a letter, a digit or a punctuation character. The English names above stay as they are, because
// they are also the accessibility identifiers the tests and the device matrix look up; only what a
// reader hears is translated.
static NSString *AKKeyAccessibilityNameKey(NSString *title) {
    if ([title isEqual:@"⇧"]) return @"touch.key.shift";
    if ([title isEqual:@"⌫"]) return @"touch.key.backspace";
    if ([title isEqual:@"↵"]) return @"touch.key.return";
    if ([title isEqual:@"🎤"]) return @"touch.key.dictate";
    if ([title isEqual:@"⌨"]) return @"touch.key.systemKeyboard";
    if ([title isEqual:@"123"]) return @"touch.key.numbers";
    if ([title isEqual:@"ABC"]) return @"touch.key.letters";
    if ([title isEqual:@" "]) return @"touch.key.space";
    return nil;
}
- (void)keyTapped:(UIButton *)button {
    if (button.tag < 0 || button.tag >= (NSInteger)_specs.count) return;
    NSString *title = _specs[(NSUInteger)button.tag][@"title"];
    id<AKTouchKeyboardSink> sink = self.sink;
    if ([title isEqual:@"⇧"]) { _shift = !_shift; [self rebuild]; return; }
    if ([title isEqual:@"123"]) { _symbols = YES; [self rebuild]; return; }
    if ([title isEqual:@"ABC"]) { _symbols = NO; [self rebuild]; return; }
    if ([title isEqual:@"⌫"]) { [sink keyboardViewBackspace]; return; }
    if ([title isEqual:@"↵"]) { [sink keyboardViewReturn]; return; }
    if ([title isEqual:@"🎤"]) { [sink keyboardViewToggleDictation]; return; }
    if ([title isEqual:@"⌨"]) { [sink keyboardViewShowSystemKeyboard]; return; }
    [sink keyboardViewType:title];
    // A shifted letter is one capital, as on every other keyboard.
    if (_shift && !_symbols) { _shift = NO; [self rebuild]; }
}
@end

// iPad touch, mockup 82: while the chat keyboard is up, a touch on the game (not the toolbar, not the composer)
// closes the keyboard and reaches nothing - no click, no key, no draft sent. Over the game, under the toolbar and
// the composer; it takes a touch only while the chat composer has the keyboard.
@interface AKTouchKeyboardGate : UIView
@property (nonatomic, weak) AKTouchControls *controls;
@end
@implementation AKTouchKeyboardGate
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.accessibilityIdentifier = @"wolkaraforever.keyboard.gate";
        self.isAccessibilityElement = NO;
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return self.controls.textKind == AKTextKindChat && [self pointInside:point withEvent:event] ? self : nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)touches; (void)event;
    if (self.controls.textKind != AKTextKindChat) return;
    AKLog(@"keyboard: a tap on the game closes the chat; nothing sent");
    [self.controls dismissKeyboard];
}
// The rest of that finger is swallowed: it reaches nothing.
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
@end

// Which view of this app has the keyboard now, if any (device fix 2): an action sent to no target goes to the first
// responder, and the first one to answer is it. With no first responder it reaches the window, the scene or the
// application, which are not "a view that has the keyboard".
static __weak UIResponder *gAKTouchFoundResponder;
@interface UIResponder (AKTouchFirstResponder)
- (void)ak_touchFindFirstResponder:(id)sender;
@end
@implementation UIResponder (AKTouchFirstResponder)
- (void)ak_touchFindFirstResponder:(id)sender { (void)sender; gAKTouchFoundResponder = self; }
@end
static UIResponder *AKTouchFirstResponder(void) {
    gAKTouchFoundResponder = nil;
    [UIApplication.sharedApplication sendAction:@selector(ak_touchFindFirstResponder:) to:nil from:nil forEvent:nil];
    UIResponder *found = gAKTouchFoundResponder;
    gAKTouchFoundResponder = nil;
    if (!found || [found isKindOfClass:UIWindow.class] || [found isKindOfClass:UIApplication.class] ||
        [found isKindOfClass:UIScene.class] || found == (id)UIApplication.sharedApplication.delegate) return nil;
    return found;
}

// The chat's channels (mockup 82): each chip makes the line a slash line. Whisper is the reply to the last
// whisper (/r): the app cannot read a name from the game.
static NSString *const AKChatChipKeys[] = {@"say", @"party", @"guild", @"whisper", @"yell"};
static NSString *const AKChatChipPrefixes[] = {@"/s ", @"/p ", @"/g ", @"/r ", @"/y "};
static const NSInteger AKChatChipCount = 5;

@implementation AKTouchControls {
    UIButton *_keyboardButton, *_trackpadButton, *_gamepadButton, *_settingsButton, *_leaveButton;
    UIButton *_toolbarHandle;
    BOOL _toolbarCollapsed, _mobileInterface, _touchPlay;
    NSTimer *_toolbarCollapseTimer;
    UIButton *_insertDraftButton, *_clearDraftButton;
    UIButton *_speechLanguageButton;
    UILabel *_composerLabel;
    BOOL _gamepadEnabled, _keyboardRequested, _systemKeyboardSeen, _ownKeyboard;
    // Which keyboard request a late check belongs to: one made for an earlier request does nothing.
    NSUInteger _keyboardRequest;
    CGFloat _systemKeyboardHeight;
    UIView *_accessory, *_composer;
    // The Composer's card: the classic controls (Clear, Replace) and the Composer row (Cancel,
    // destination chips, speak, settings, Send). One set is visible at a time, and the classic one
    // is what every release through v1.0.10 has shown.
    UIView *_composerRow;
    NSLayoutConstraint *_classicEditorTrailing, *_classicEditorBottom;
    NSLayoutConstraint *_composerEditorTrailing, *_composerEditorBottom;
    UIButton *_composerCancelButton, *_composerSendButton, *_composerListenButton, *_composerSettingsButton;
    UIScrollView *_composerChips;
    NSLayoutConstraint *_composerHeight;
    // The label's and the action row's own heights, and the values they currently carry: the card
    // is these plus its fixed parts, so a larger text size grows the card and never the editor.
    NSLayoutConstraint *_composerLabelHeight;
    CGFloat _composerLabelRowHeight, _composerActionRowHeight;
    BOOL _applyingComposerDraft;
    AKTouchKeyboardView *_layerKeyboard;
    NSTimer *_holdTimer;
    AKKeyboardTextView *_keyboardInput;
    // The direct touch camera, with this app's lifecycle around it: one gesture at a time, one
    // way out of it, and a centroid jump treated as a new gesture rather than a drag.
    AKTouchCameraGesture _camera;
    CGSize _cameraSurface;
    // A controller's touchpad as the pointer, when the user switched that on in the launcher.
    AKControllerPointer _controllerPointer;
    AKTouchHaptics *_haptics;
    AKTouchGamepad *_gamepad;
    // iPad touch: the walk stick only (rule 3), its own layer below this toolbar. Nil in every other mode.
    AKTouchGamepad *_walkStick;
    BOOL _tookOwnPlace;
    // Whether one of the game's password fields has the keyboard: the game asked for secure
    // event input (Carbon adapter, patch 0058).
    BOOL _protectedField;
    // iPad touch: the keyboard for the game's password box, typed by hand (rule 9; no AutoFill since ruling A41). Nil in
    // every other mode.
    AKTouchTextBridge *_textBridge;
    // iPad touch: whether the player is in the world, read from the add-on's secure-input pulses (ruling A24); it
    // decides whether TouchPlay's buttons are on screen (AKTouchAreas.live). Nil in every other mode.
    AKTouchWorldSignal *_worldSignal;
    // The keyboard passes between the composer and the password field: the game's view must not take it between.
    BOOL _handingOver;
    // iPad touch: whether the game's secure event input is on right now, as last announced (device fix 2). The box's
    // focus (_protectedField) is believed on a player's tap only while it is.
    BOOL _secureOn;
    // iPad touch: the login screen (the game's start, or the game's password box seen since the player was last in the
    // world). Out of the world there, the composer types into the game's account box: its Return is Tab, never Login.
    BOOL _loginScreen;
    // iPad touch: how far the game is slid up for the password keyboard (0 when not).
    CGFloat _slide;
    AKTouchKeyboardGate *_gate;
    // iPad touch's chat: the chips row above the keys, the chosen chip (-1: the game's own channel), and Send.
    UIView *_chips;
    UIStackView *_chipStack;
    NSInteger _chatChannel;
    UIButton *_sendButton;
}

// The launcher's switch, and the platform's install path, ask this before the
// controls are added. A stored choice wins; without one they are on, because
// this product wants them on every device it runs on.
+ (BOOL)enabled {
    NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:AKTouchControlsDefaultsKey];
    return [saved isKindOfClass:NSNumber.class] ? saved.boolValue : YES;
}

static void AKEmitTouch(void *context, AKTrackpadAction action, double x, double y, unsigned button) {
    AKTouchControls *controls = (__bridge AKTouchControls *)context;
    switch (action) {
        case AKTrackpadMove: [controls.delegate touchMoveBy:CGPointMake(x, y)]; break;
        case AKTrackpadScroll: [controls.delegate touchScrollBy:CGPointMake(x, y)]; break;
        case AKTrackpadDown: [controls.delegate touchButton:button pressed:YES]; break;
        case AKTrackpadUp: [controls.delegate touchButton:button pressed:NO]; break;
    }
}

- (UIButton *)buttonWithSymbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.45];
    button.layer.cornerRadius = 22;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.4].CGColor;
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(buttonTouchDown) forControlEvents:UIControlEventTouchDown];
    [self addSubview:button];
    return button;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.zPosition = 100001;
        // VoiceOver reads what is under this view in the app's language, not the iPad's, so a
        // German HUD and German keyboard keys are pronounced as German.
        self.accessibilityLanguage = AKHostLanguageCode();
        _haptics = [AKTouchHaptics new];
        _keyboardInput = [[AKKeyboardTextView alloc] initWithFrame:CGRectMake(0, 0, 1, 1) textContainer:nil];
        _keyboardInput.inputOwner = self;
        // Announced, not reached for. The game's text input is this view, not the draft
        // editor: this one is the layer's UIKeyInput, and its delegate is what posts the
        // key events into the guest. The draft editor is a UITextView that holds words for
        // Replace and cannot reach the game at all. Announcing the wrong one is not a
        // cosmetic mistake - the first transcript sent to it aborted the app with
        // "-[AKKeyboardTextView touchInsertText:]: unrecognized selector" (measured on
        // Dadpad, 2026-10-21).
        [NSNotificationCenter.defaultCenter postNotificationName:AKTouchGameTextInputDidAppearNotification
                                                        object:self];
        // The shell publishes the recogniser's language; this keeps the composer's control
        // showing what is actually stored, including a change made elsewhere.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(speechLanguageDidChange:)
                                                   name:AKTouchSpeechLanguageDidChangeNotification object:nil];
        [self buildComposer];
        _keyboardButton = [self buttonWithSymbol:@"keyboard" label:AKHostLocalized(@"touch.keyboard.show") action:@selector(toggleKeyboard)];
        _keyboardButton.accessibilityIdentifier = @"tolkara.keyboard";
        _trackpadButton = [self buttonWithSymbol:@"cursorarrow" label:AKHostLocalized(@"touch.trackpad.enable") action:@selector(toggleTrackpad)];
        // Optical centering for the left-leaning symbol; keep its hit area fixed.
        _trackpadButton.imageView.transform = CGAffineTransformMakeTranslation(4, 0);
        _trackpadButton.accessibilityIdentifier = @"tolkara.trackpad";
        _gamepadButton = [self buttonWithSymbol:@"gamecontroller" label:AKHostLocalized(@"touch.gamepad.automatic") action:@selector(toggleGamepad)];
        _gamepadButton.accessibilityIdentifier = @"tolkara.gamepad";
        _settingsButton = [self buttonWithSymbol:@"gearshape" label:AKHostLocalized(@"touch.settings") action:@selector(showControlSettings)];
        _settingsButton.accessibilityIdentifier = @"wolkaraforever.controlSettings";
        // A way out of the game from any screen. Until this existed, a guest screen with no
        // quit of its own - the login screen is one - left the user with no control that
        // returned to WolkaraForever's launcher at all, and closing the app was the only exit
        // (reported on Dadpad, 2026-10-21). It closes WolkaraForever, which ends the guest with it.
        _leaveButton=[self buttonWithSymbol:@"house" label:AKHostLocalized(@"touch.leave") action:@selector(leaveGame)];
        _leaveButton.accessibilityIdentifier=@"wolkaraforever.leaveGame";
        _leaveButton.accessibilityHint=AKHostLocalized(@"touch.leave.hint");
        // Said once at build time so a device run can be read back without a tap.
        AKLog(@"toolbar: leave game control on the toolbar (house; asks the guest to terminate)");
        // The interface the user chose, read once: the controls live as long as the guest
        // does, and the launcher writes the key before a guest starts. Standard (iPadOS)
        // keeps the toolbar it has always had - five buttons across the top, always open.
        _mobileInterface = AKInterfaceModeIsMobile();
        // iPad touch: the TouchPlay add-on draws the buttons, so the controller overlay and its
        // virtual gamepad are never made (see the guard where the gamepad is created). Read once, with
        // the interface, for the same reason.
        _touchPlay = AKInterfaceModeIsTouchPlay();
        // iPad touch: the password box's own keyboard, and the chat strip's tap opens the chat (ruling A7).
        _chatChannel = -1;
        if (_touchPlay) {
            // A game start is "not in the world" until the add-on's pulse says it entered (ruling A24).
            _worldSignal = [AKTouchWorldSignal new];
            __weak AKTouchControls *weakWorld = self;
            _worldSignal.changed = ^(AKTouchWorldState state) { [weakWorld worldChanged:state]; };
        }
        if (_touchPlay && AKTouchTextBridgeWanted()) {
            _textBridge = [AKTouchTextBridge new];
            _loginScreen = YES;   // a game starts at the login screen
            _textBridge.sink = self;
            __weak AKTouchControls *weakControls = self;
            _textBridge.openChat = ^{
                AKTouchControls *controls = weakControls;
                if (controls && !controls->_keyboardInput.isFirstResponder) [controls becomeFirstResponder];
            };
            _textBridge.activeChanged = ^(BOOL active) {
                AKTouchControls *controls = weakControls;
                if (!controls) return;
                // Back to the game's view, as the composer does when it closes - unless the keyboard is passing to the
                // composer (it would drop and come back), or the field lost it to another view (the Passwords sheet):
                // then the game's view takes it only if nothing else has it, and the field stays ready for AutoFill.
                if (!active && !controls->_handingOver && !controls->_keyboardInput.isFirstResponder) [controls takeKeyboardBackFromField];
                [controls updateKeyboardButton];
                [controls slideGameForPassword:active && controls->_textBridge.kind == AKTextKindPassword];
            };
            // The game's password box, once secure input has stayed on past the debounce (a pulse of the add-on's never
            // gets here): it takes the keyboard, from the chat composer too. From the composer, the keyboard passes
            // straight to the field (the composer gives it up and drops its draft).
            // The scene, not UIApplication: during UIApplicationWillResignActiveNotification, which is when the game turns
            // secure input off for Face ID's sheet, UIApplication still says active (device fix 2).
            _textBridge.appIsActive = ^BOOL { AKTouchControls *controls = weakControls; return controls ? [controls appIsActive] : YES; };
            _textBridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) {
                AKTouchControls *controls = weakControls;
                if (!controls) return;
                controls->_protectedField = YES;
                // The password box out of the world: this is the login screen (switching accounts lands here too).
                if (controls->_worldSignal.state == AKTouchWorldOut) controls->_loginScreen = YES;
                BOOL fromComposer = opening && controls->_keyboardInput.isFirstResponder;
                if (fromComposer) {
                    controls->_handingOver = YES;
                    controls->_keyboardRequested = NO;
                    if (controls->_ownKeyboard) {
                        controls->_ownKeyboard = NO; controls->_keyboardInput.inputView = nil; [controls->_keyboardInput reloadInputViews];
                    }
                }
                open();
                if (fromComposer) {
                    controls->_handingOver = NO;
                    if (controls->_keyboardInput.isFirstResponder) [controls dismissKeyboard];   // the field did not take it
                }
                AKLog(@"keyboard: the game's password box has focus");
                [controls updateKeyboardButton];
            };
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(chatAreaTapped:)
                                                       name:AKTouchChatAreaTappedNotification object:nil];
        }
        if (_mobileInterface) {
            // The handle folds the five buttons away so they do not sit over the game, and
            // brings them back with one tap.
            _toolbarHandle = [self buttonWithSymbol:@"chevron.compact.down" label:AKHostLocalized(@"touch.toolbar.show") action:@selector(toggleToolbar)];
            _toolbarHandle.accessibilityIdentifier = @"wolkaraforever.toolbarHandle";
            NSNumber *collapsed = [NSUserDefaults.standardUserDefaults objectForKey:AKTouchToolbarCollapsedDefaultsKey];
            _toolbarCollapsed = [collapsed isKindOfClass:NSNumber.class] ? collapsed.boolValue : YES;
            [self applyToolbarCollapsed];
        }
        _gamepadButton.accessibilityHint = AKHostLocalized(@"touch.gamepad.hint");
        NSNumber *gamepad = [NSUserDefaults.standardUserDefaults objectForKey:@"TKTouchGamepadEnabled"];
        _gamepadEnabled = gamepad ? gamepad.boolValue : YES;
        [self setGamepadVisible:NO];
        _trackpadButton.accessibilityHint = AKHostLocalized(@"touch.trackpad.hint");
        __weak AKTouchControls *weakSelf = self;
        NSMutableArray<UIAction *> *actions = [NSMutableArray new];
        NSArray<NSString *> *buttons = @[AKHostLocalized(@"touch.mouse.left"), AKHostLocalized(@"touch.mouse.right"),
                                         AKHostLocalized(@"touch.mouse.middle")];
        for (unsigned i = 0; i < buttons.count; i++) {
            [actions addObject:[UIAction actionWithTitle:buttons[i] image:nil identifier:nil handler:^(UIAction *action) {
                (void)action;
                AKTouchControls *controls = weakSelf;
                [controls cancelTouches];
                [controls.delegate touchButton:i pressed:YES];
                [controls.delegate touchButton:i pressed:NO];
            }]];
        }
        _trackpadButton.menu = [UIMenu menuWithTitle:@"Mouse buttons" children:actions];
        NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:[self trackpadDefaultsKey]];
        // Mobile: direct touch by default - a tap clicks where the finger is and a hold
        // right-clicks (patch 0055), which reads better than a cursor moved like a trackpad.
        // Standard: the default it has always had, a trackpad on a phone and off on an iPad.
        // iPad touch reads only its own switch, off until it is turned on in iPad touch.
        self.trackpadEnabled = saved ? saved.boolValue
            : (_mobileInterface ? NO : UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone);
        if (_touchPlay) AKLog(@"touch controls: iPad touch's trackpad is %@ (%@)", self.trackpadEnabled ? @"on" : @"off",
                              saved ? @"turned so in iPad touch" : @"its default; another interface's switch does not apply");
        if (_touchPlay) {
            // The toolbar's dock follows TouchPlay's buttons: in the world or not, and new buttons after a reload.
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(toolbarDockInputsChanged:) name:AKTouchAreasLiveDidChangeNotification object:nil];
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(toolbarDockInputsChanged:) name:AKTouchContractDidChangeNotification object:nil];
        }
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspendInput:) name:UIApplicationWillResignActiveNotification object:nil];
        // iPad touch: the game's password box that asked while the app was away gets its field now.
        if (_textBridge) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backgroundInput:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowResigned:) name:UIWindowDidResignKeyNotification object:nil];
        // The app's relay, by name (launcher/Input/ControllerTouchpad.h): that code is not linked
        // from here. Posted on the main queue only, and only while the user's switch is on.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(controllerTouchpad:)
            name:@"AKControllerTouchpadPointer" object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(controlAppearanceChanged:)
            name:AKGamepadLayoutDidChangeNotification object:NSUserDefaults.standardUserDefaults];
        // The card follows the player's text size, including a change made while the game runs.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contentSizeCategoryChanged:)
            name:UIContentSizeCategoryDidChangeNotification object:nil];    // Whether the system keyboard (and so its dictation button) exists at all on
    // this device, and whether UIKit is talking to our draft editor when it does.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemKeyboardShown:) name:UIKeyboardDidShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemKeyboardHidden:) name:UIKeyboardDidHideNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardRequestedByGuest:) name:AKTouchKeyboardRequestNotification object:nil];
    // The Carbon adapter's announcement, by name: that library is not linked from here.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(secureEventInputChanged:)
        name:@"AKSecureEventInputDidChangeNotification" object:nil];
        [self controlAppearanceChanged:nil];
        [self applyComposerTextSize];
        [self beginChatComposer];
    }
    return self;
}

- (void)controlAppearanceChanged:(NSNotification *)notification {
    (void)notification;
    AKGamepadLayout *layout = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    _haptics.enabled = layout.hapticsEnabled;
    // The arrangement, the stick buttons and the zones are in the same dictionary, so the
    // gamepad has to read it again whenever it changes - including when the launcher wrote it.
    [_gamepad reloadLayout];
    NSMutableArray *buttons = [@[_trackpadButton, _keyboardButton, _gamepadButton, _settingsButton, _leaveButton]
        mutableCopy];
    // The handle exists only in the mobile interface; an array literal would refuse a nil.
    if (_toolbarHandle) [buttons addObject:_toolbarHandle];
    for (UIButton *button in buttons) button.alpha = layout.opacity;
}
- (void)buttonTouchDown { [_haptics buttonPressed]; [self restartToolbarCollapseTimer]; }

#pragma mark - Folding toolbar

- (void)applyToolbarCollapsed {
    // Standard has no handle and never folds: every button stays where it was.
    if (!_mobileInterface) {
        for (UIButton *button in @[_trackpadButton, _gamepadButton, _settingsButton, _leaveButton])
            button.hidden = NO;
        _keyboardButton.hidden = NO;
        return;
    }
    // Folded, the keyboard stays: it is the button a player reaches for most (the chat).
    for (UIButton *button in @[_trackpadButton, _leaveButton])
        button.hidden = _toolbarCollapsed;
    // The controller overlay's toggle and settings gear: in iPad touch there is no overlay for them
    // to act on, so they are never shown, folded or open. Everywhere else they fold with the rest.
    for (UIButton *button in @[_gamepadButton, _settingsButton])
        button.hidden = _touchPlay || _toolbarCollapsed;
    _keyboardButton.hidden = NO;
    [_toolbarHandle setImage:[UIImage systemImageNamed:_toolbarCollapsed ? @"chevron.compact.down" : @"chevron.compact.up"]
                    forState:UIControlStateNormal];
    _toolbarHandle.accessibilityLabel = AKHostLocalized(_toolbarCollapsed ? @"touch.toolbar.show" : @"touch.toolbar.hide");
    [self setNeedsLayout];
    if (self.superview) [self placeToolbarInHost:self.superview];
}
- (void)setToolbarCollapsed:(BOOL)collapsed {
    if (!_mobileInterface) return;
    if (_toolbarCollapsed == collapsed) return;
    _toolbarCollapsed = collapsed;
    [NSUserDefaults.standardUserDefaults setBool:collapsed forKey:AKTouchToolbarCollapsedDefaultsKey];
    [self applyToolbarCollapsed];
    AKLog(@"toolbar: %@", collapsed ? @"folded into its handle" : @"opened");
}
// The areas' live switch, or the contract itself, changed: the toolbar's place may too. The live switch is already
// set when it is posted, so the toolbar moves at once; the contract's notification reaches the areas by the same
// route, so that one waits a turn for them to take the new contract first.
- (void)toolbarDockInputsChanged:(NSNotification *)notification {
    void (^move)(void) = ^{
        [self setNeedsLayout];
        if (self.superview) [self placeToolbarInHost:self.superview];
    };
    if ([notification.name isEqualToString:AKTouchContractDidChangeNotification]) dispatch_async(dispatch_get_main_queue(), move);
    else if (NSThread.isMainThread) move();
    else dispatch_async(dispatch_get_main_queue(), move);
}
- (void)toggleToolbar {
    [self setToolbarCollapsed:!_toolbarCollapsed];
    [self restartToolbarCollapseTimer];
}
// Common modes, because the guest drives the main run loop in modes of its own while it
// runs; a default-mode timer would wait for the game to return to the default mode.
- (void)restartToolbarCollapseTimer {
    [_toolbarCollapseTimer invalidate];
    _toolbarCollapseTimer = nil;
    if (!_mobileInterface || _toolbarCollapsed) return;
    __weak AKTouchControls *weakSelf = self;
    _toolbarCollapseTimer = [NSTimer timerWithTimeInterval:AKTouchToolbarAutoCollapse repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        AKTouchControls *controls = weakSelf;
        if (!controls) return;
        controls->_toolbarCollapseTimer = nil;
        // Typing uses the keyboard button to close; the toolbar waits for the keyboard.
        if (controls.keyboardVisible) { [controls restartToolbarCollapseTimer]; return; }
        [controls setToolbarCollapsed:YES];
    }];
    [NSRunLoop.mainRunLoop addTimer:_toolbarCollapseTimer forMode:NSRunLoopCommonModes];
}

// Place the toolbar from the host's own bounds.
//
// Standard: centred horizontally just below the top, 252 by 44, the geometry every release
// through v1.0.7 has had.
//
// Mobile: centred horizontally at the bottom of the screen, between the thumbs, where a phone
// player reaches it (asked for on the iPhone Duo, 2026-11-06), folded into a 96 by 34 handle
// unless the user opened it. While the keyboard is up it goes back just below the top: the
// keyboard and the draft editor above it take the bottom, and the keyboard button is how
// typing is closed.
//
// iPad touch: always the top-centre band, folded or open (AKTouchToolbarDockFor; run 5); it follows the button list when it
// changes.
//
// Measured on the device: centring on host.safeAreaLayoutGuide put the toolbar 103pt right of
// the screen centre, so the guide is not the screen here. The bounds are. Frame placement
// also settles the tug of war with the host's own constraints for us - they are dropped once,
// by collecting them and deactivating the collection, so the list being walked is not the one
// being changed.
- (void)placeToolbarInHost:(UIView *)host {
    if (self.superview != host) return;
    if (!_tookOwnPlace) {
        _tookOwnPlace = YES;
        NSMutableArray<NSLayoutConstraint *> *theirs = [NSMutableArray array];
        for (NSLayoutConstraint *constraint in host.constraints)
            if (constraint.firstItem == self || constraint.secondItem == self)
                [theirs addObject:constraint];
        for (NSLayoutConstraint *constraint in theirs) constraint.active = NO;
        self.translatesAutoresizingMaskIntoConstraints = YES;
    }
    static unsigned logged;
    CGFloat width, height;
    if (!_mobileInterface) { width = 252; height = 44; }
    else if (_toolbarCollapsed) { width = 96; height = 34; }
    else { width = _touchPlay ? 208 : 304; height = 44; }   // iPad touch: four buttons, not six
    CGRect bounds = host.bounds;
    BOOL top = !_mobileInterface || self.keyboardVisible;
    CGFloat centreX = bounds.size.width / 2;
    // iPad touch: always the top-centre band, folded or open, whatever the game shows - in the world, out of it or with a
    // window open (run 5: out of the world it used to drop to 1.0.10's bottom centre, where the open toolbar's keyboard
    // button sat over TouchPlay's info card). TouchPlay keeps that band clear; the dock follows the button list (not
    // whether it is on screen), so the toolbar never moves when a window opens or closes.
    if (_touchPlay) {
        top = YES;
        AKTouchToolbarDock dock = AKTouchToolbarDockFor([AKTouchAreas areasForView:host].contract, bounds.size, host.safeAreaInsets,
                                                        CGSizeMake(208, 44), CGSizeMake(96, 34));
        centreX = dock.centreX;
    }
    CGFloat y = top ? host.safeAreaInsets.top + 8 : bounds.size.height - host.safeAreaInsets.bottom - 8 - height;
    // iPad touch: the game is slid up for the password keyboard; the toolbar stays where it is on screen.
    self.frame = CGRectMake(floor(centreX - width / 2), y + _slide, width, height);
    if (logged < 3) {
        logged++;
        AKLog(@"toolbar host bounds=%.0fx%.0f insets top=%.0f left=%.0f bottom=%.0f placed x=%.0f y=%.0f centre=%.0f (screen centre %.0f)",
              bounds.size.width, bounds.size.height, host.safeAreaInsets.top, host.safeAreaInsets.left,
              host.safeAreaInsets.bottom, self.frame.origin.x, y, CGRectGetMidX(self.frame), bounds.size.width / 2);
    }
}


- (void)layoutSubviews {
    [super layoutSubviews];
    // A rotation or a resize changes the space the remembered centroid was measured in, so the
    // gesture is closed rather than dragged by a delta that belongs to a different screen.
    CGSize surface = self.superview.bounds.size;
    if (!CGSizeEqualToSize(surface, _cameraSurface)) {
        if (AKTouchCameraIsActive(&_camera)) [self cancelCameraGesture:@"resize"];
        _cameraSurface = surface;
    }
    if (self.superview) [self placeToolbarInHost:self.superview];
    // The Composer's action row is positioned here, not by constraints. Its own height and floor
    // constraints were missing from the layout engine's set for it - they read active, carried the
    // right values and were installed on the row, and constraintsAffectingLayoutForAxis: never
    // returned them - so the row measured 0 and the draft editor took its 44 points (measured
    // 2026-11-16 with lldb, on both matrix simulators). A frame set in the layout pass is not
    // something the engine can lose, and the row's own children are still laid out against it.
    if (_composerRow.superview && !_composerRow.hidden) {
        CGFloat card = CGRectGetHeight(_composer.bounds);
        CGFloat box = MIN(_composerActionRowHeight, card / 2);
        _composerRow.frame = CGRectMake(8, card - 8 - box,
                                        MAX(0, CGRectGetWidth(_composer.bounds) - 16), MAX(0, box));
    }
    _trackpadButton.frame = CGRectMake(0, 0, 44, 44);
    _keyboardButton.frame = _toolbarCollapsed ? CGRectMake(0, 0, 44, 34) : CGRectMake(52, 0, 44, 44);
    _keyboardButton.layer.cornerRadius = _toolbarCollapsed ? 17 : 22;
    _gamepadButton.frame = CGRectMake(104, 0, 44, 44);
    _settingsButton.frame = CGRectMake(156, 0, 44, 44);
    // iPad touch packs the four buttons it shows: trackpad, keyboard, leave, handle.
    _leaveButton.frame = CGRectMake(_touchPlay ? 104 : 208, 0, 44, 44);
    _toolbarHandle.frame = _toolbarCollapsed ? CGRectMake(52, 0, 44, 34) : CGRectMake(_touchPlay ? 156 : 260, 0, 44, 44);
    _toolbarHandle.layer.cornerRadius = _toolbarCollapsed ? 17 : 22;
}
- (void)setTrackpadEnabled:(BOOL)enabled {
    [self cancelCameraGesture:@"settings"];
    _trackpadEnabled = enabled;
    _trackpadButton.tintColor = enabled ? UIColor.systemCyanColor : UIColor.whiteColor;
    _trackpadButton.accessibilityLabel = enabled ? AKHostLocalized(@"touch.trackpad.disable") : AKHostLocalized(@"touch.trackpad.enable");
    _trackpadButton.accessibilityValue = enabled ? AKHostLocalized(@"touch.value.on") : AKHostLocalized(@"touch.value.off");
    [self.delegate touchTrackpadChanged:enabled];
}
- (void)toggleTrackpad {
    self.trackpadEnabled = !self.trackpadEnabled;
    [NSUserDefaults.standardUserDefaults setBool:self.trackpadEnabled forKey:[self trackpadDefaultsKey]];
}
// The trackpad switch this interface reads and writes: iPad touch's own, or the one every other interface shares.
- (NSString *)trackpadDefaultsKey { return _touchPlay ? AKTouchTrackpadIPadTouchDefaultsKey : AKTouchTrackpadDefaultsKey; }
- (BOOL)gamepadEnabled { return _gamepadEnabled; }
- (BOOL)configuring { return _gamepad.configuring; }
- (void)showControlSettings {
    // iPad touch has no controller overlay, hence no settings sheet; the gear is hidden there.
    if (_touchPlay) return;
    [self cancelCameraGesture:@"settings"]; [self dismissKeyboard];
    // The gamepad owns the settings sheet, so we open it here rather than asking a
    // host that may have no such thing.
    [_gamepad toggleSettings];
    if ([self.delegate respondsToSelector:@selector(touchControlSettings)]) [self.delegate touchControlSettings];
}
// Leaving the game from a screen that has no quit of its own.
//
// The guest is a real Cocoa application in this process: asking its own NSApp to terminate
// runs its applicationShouldTerminate:/applicationWillTerminate: handlers first, which is how
// the game saves its settings, and only then does the translated AppKit end the process. That
// is the same path the game's own Exit item takes; nothing is killed and no memory is written.
//
// The confirmation says the rest plainly because there is no way around it: one guest per
// process, so WolkaraForever cannot put its launcher back afterwards - opening WolkaraForever again does.
- (void)leaveGame {
    [self cancelCameraGesture:@"leave"]; [self dismissKeyboard];
    // One question, and no request to the guest.
    //
    // Asking the guest's own application object to terminate was tried first and is not kept.
    // The client answered `NSTerminateCancel`, so the tap did nothing at all - the exact dead
    // end this control exists to remove - and on the same run it faulted with EXC_BAD_ACCESS
    // shortly afterwards (ERROR #132, Dadpad, 2026-10-21): a half-asked shutdown that is then
    // cancelled is not a state to put a running client in for a UI convenience. WolkaraForever ends
    // its own process instead, and says plainly what that costs.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:AKHostLocalized(@"touch.leave.title")
        message:AKHostLocalized(@"touch.leave.message")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"touch.leave.keep") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"touch.leave.close") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action;
        AKLog(@"leave game: the user chose to close WolkaraForever");
        [NSNotificationCenter.defaultCenter postNotificationName:AKTouchCloseAppNotification object:nil];
    }]];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}
- (void)setGamepadVisible:(BOOL)visible {
    _gamepadButton.tintColor = visible ? UIColor.systemCyanColor : UIColor.whiteColor;
    _gamepadButton.accessibilityValue = _gamepadEnabled ? (visible ? AKHostLocalized(@"touch.gamepad.value.active") :
        AKHostLocalized(@"touch.gamepad.value.automatic")) : AKHostLocalized(@"touch.gamepad.value.off");
}
- (void)toggleGamepad {
    // iPad touch has no gamepad to switch, and the stored preference belongs to the modes that do.
    if (_touchPlay) return;
    _gamepadEnabled = !_gamepadEnabled;
    [NSUserDefaults.standardUserDefaults setBool:_gamepadEnabled forKey:@"TKTouchGamepadEnabled"];
    _gamepad.enabled = _gamepadEnabled;
    [self setGamepadVisible:_gamepad.visible];
    if ([self.delegate respondsToSelector:@selector(touchGamepadPreferenceChanged:)])
        [self.delegate touchGamepadPreferenceChanged:_gamepadEnabled];
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)keyboardVisible { return _keyboardInput.isFirstResponder || _textBridge.active; }
- (AKTextKind)textKind {
    if (_keyboardInput.isFirstResponder) return AKTextKindChat;
    return _textBridge.active ? _textBridge.kind : AKTextKindNone;
}
- (BOOL)becomeFirstResponder {
    // The chat composer and the password field never share the keyboard: the composer takes it from the field
    // directly (the field gives it up), never through the game's view.
    _handingOver = _textBridge.active;
    _composer.hidden = NO;
    _gamepad.keyboardVisible = YES;
    _walkStick.keyboardVisible = YES;
    if ([self.delegate respondsToSelector:@selector(touchKeyboardVisibilityChanged:)])
        [self.delegate touchKeyboardVisibilityChanged:YES];
    _keyboardRequested = YES;
    _systemKeyboardSeen = NO;
    // iPad touch: the keyboard's Return reads what it does - Next in the login's account box (Tab), Send for the chat.
    // Every other mode keeps the key the draft editor was made with.
    if (_touchPlay) _keyboardInput.returnKeyType = [self typingIntoLoginAccountBox] ? UIReturnKeyNext : UIReturnKeySend;
    BOOL accepted = [_keyboardInput becomeFirstResponder];
    if (_textBridge.active || _textBridge.kind != AKTextKindNone) [_textBridge end];
    _handingOver = NO;
    [self updateKeyboardButton];
    [self checkSystemKeyboard:++_keyboardRequest late:NO];
    return accepted;
}
// A hardware keyboard hides the software keyboard, and with it the dictation
// button. When that happens the layer supplies the keys itself: a login field
// that cannot be typed into is not a state to leave the user in.
//
// Without a hardware keyboard (an iPhone), iOS's own keyboard is coming, only late when the
// phone is busy. On 2026-11-09 it took longer than 0.8 s at the login screen, the layer's keys
// replaced it, and the player could not type the password. So without a hardware keyboard the
// layer waits much longer before giving up on iOS's keyboard.
static const NSTimeInterval AKSystemKeyboardWait = 0.8, AKSystemKeyboardLateWait = 4;
- (void)checkSystemKeyboard:(NSUInteger)request late:(BOOL)late {
    __weak AKTouchControls *weakSelf = self;
    NSTimeInterval wait = late ? AKSystemKeyboardLateWait - AKSystemKeyboardWait : AKSystemKeyboardWait;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AKTouchControls *controls = weakSelf;
        if (!controls || controls->_keyboardRequest != request || !controls.keyboardVisible || controls->_ownKeyboard) return;
        // The layer's own keys are the composer's; the password field (iPad touch) never gets them.
        if (!controls->_keyboardInput.isFirstResponder) return;
        BOOL hardware = hardwareKeyboardAttached();
        if (!late) AKLog(@"hardware keyboard %@", hardware ? @"attached" : @"absent");
        if (!controls->_systemKeyboardSeen) {
            if (!hardware && !late) {
                AKLog(@"software keyboard not up yet and no hardware keyboard: waiting for it");
                [controls checkSystemKeyboard:request late:YES];
                return;
            }
            AKLog(@"software keyboard did not appear; showing the layer's own keys");
            [controls showLayerKeyboard];
        } else if (controls->_systemKeyboardHeight < AKKeyboardKeysHeight) {
            AKLog(@"software keyboard keys are not on screen (height %.0f); showing the layer's own keys", controls->_systemKeyboardHeight);
            [controls showLayerKeyboard];
        }
    });
}
- (BOOL)keyboardRequested { return _keyboardRequested; }
- (void)draftEditorLetGo { if (!_handingOver) _keyboardRequested = NO; }
- (BOOL)resignFirstResponder {
    BOOL accepted = [_keyboardInput resignFirstResponder];
    [self updateKeyboardButton];
    return accepted;
}
- (void)updateKeyboardButton {
    // The composer is the chat's; the password field has none (the game's box shows the dots).
    _composer.hidden = !_keyboardInput.isFirstResponder;
    if (self.superview) [self placeToolbarInHost:self.superview];
    [self updateDraftButtons];
    // The card and the row follow the keyboard: with review mode on, the keyboard coming up is
    // what puts the Composer row (and its microphone) on screen.
    [self applyComposerState];
    [_keyboardButton setImage:[UIImage systemImageNamed:self.keyboardVisible ? @"keyboard.chevron.compact.down" : @"keyboard"] forState:UIControlStateNormal];
    // iPad touch, the game's password box focused and no keyboard up: the button brings the Passwords field back.
    _keyboardButton.accessibilityLabel = self.keyboardVisible ? AKHostLocalized(@"touch.keyboard.hide")
        : (_textBridge && _protectedField) ? AKHostLocalized(@"touch.keyboard.typePassword") : AKHostLocalized(@"touch.keyboard.show");
    _gamepad.keyboardVisible = self.keyboardVisible;
    _walkStick.keyboardVisible = self.keyboardVisible;
    if ([self.delegate respondsToSelector:@selector(touchKeyboardVisibilityChanged:)])
        [self.delegate touchKeyboardVisibilityChanged:self.keyboardVisible];
}
- (void)toggleKeyboard {
    [self cancelCameraGesture:@"keyboard"];
    if (self.keyboardVisible) [self dismissKeyboard];
    // iPad touch: while the game's password box has focus, the keyboard is the Passwords field (rule 9).
    else if (_textBridge) [self openKeyboardForPlayer:@"the toolbar's keyboard button"];
    else [self becomeFirstResponder];
}
// iPad touch (device fix 2): the player asked for the keyboard - the toolbar's button, the chat strip, or a game key. It
// always opens: whatever an earlier password left behind ends here. The game's password box gets the Passwords field
// only while the game still has secure input on (a remembered focus without it is stale: the chat opens), and a keyboard
// that nothing took is asked for once more after every responder in the window lets go.
- (void)openKeyboardForPlayer:(NSString *)source {
    if (_protectedField && !_secureOn && [self appIsActive]) {
        AKLog(@"keyboard: %@: the game's password box no longer has secure input on; the old password state is cleared", source);
        _protectedField = NO;
    }
    BOOL password = _protectedField;
    for (int attempt = 0; attempt < 2; attempt++) {
        if (attempt) {
            UIResponder *holder = AKTouchFirstResponder();
            AKLog(@"keyboard: %@: nothing took the keyboard (it is with %@); asking again", source,
                  holder ? NSStringFromClass(holder.class) : @"nobody");
            [self.window endEditing:YES];
            [self.superview becomeFirstResponder];
        }
        if (password) [_textBridge beginForKind:AKTextKindPassword];
        else [_textBridge beginForKind:AKTextKindChat];
        if (self.keyboardVisible) break;
    }
    AKLog(@"keyboard: %@ %@", source, !self.keyboardVisible ? @"could not open the keyboard"
          : password ? @"opens the password field" : @"opens the chat");
    [self updateKeyboardButton];
}
- (BOOL)appIsActive {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    UIWindowScene *scene = self.window.windowScene;
    return !scene || scene.activationState == UISceneActivationStateForegroundActive;
}
- (void)appBecameActive:(NSNotification *)note {
    (void)note;
    [_textBridge tick];
}
// The password field gave up the keyboard. Closed by the bridge: the game's view takes it back at once, as when the
// composer closes. Lost to another view: that view keeps it; only if nothing has it does the game's view take it, so
// a hardware keyboard still reaches the game.
- (void)takeKeyboardBackFromField {
    if (_textBridge.kind == AKTextKindNone) { [self.superview becomeFirstResponder]; return; }
    __weak AKTouchControls *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        AKTouchControls *controls = weakSelf;
        if (!controls || controls.keyboardVisible || AKTouchFirstResponder()) return;
        [controls.superview becomeFirstResponder];
    });
}
// iPadOS has no software keyboard to give (it believes a hardware keyboard is
// attached), so the layer supplies the keys itself. A custom input view is shown
// whatever the hardware says, and it keeps the game's field usable: without it
// there is no way to type the @ an e-mail address needs at the login screen.
- (void)showLayerKeyboard {
    if (!_layerKeyboard) {
        _layerKeyboard = [[AKTouchKeyboardView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 236)];
        _layerKeyboard.sink = self;
    }
    _ownKeyboard = YES;
    if (_touchPlay) _keyboardRequested = YES;   // the layer's keys are a keyboard asked for, like the toolbar's button
    _keyboardInput.inputView = _layerKeyboard;
    _composer.hidden = NO;
    BOOL focused = _keyboardInput.isFirstResponder || [_keyboardInput becomeFirstResponder];
    if (!focused) AKLog(@"the draft editor could not take focus (window=%@)", _keyboardInput.window ? @"yes" : @"no");
    [_keyboardInput reloadInputViews];
    // The layer's keys are the size of a keyboard's keys, so the "no keys on
    // screen" test must not read them as the shortcut bar next time.
    _systemKeyboardHeight = 0;
    [self updateKeyboardButton];
    AKLog(@"the layer's own keyboard is up (iPadOS has no software keyboard to give)");
}
- (void)keyboardViewType:(NSString *)text {
    // The same route dictation takes: the adapter turns the words into the
    // guest's own key events, so the field the game has focused takes them.
    if ([self.delegate respondsToSelector:@selector(touchInsertText:)]) {
        [self.delegate touchInsertText:text];
    } else {
        // No game behind the controls: keep the words in the draft instead.
        [_keyboardInput setText:[_keyboardInput.text stringByAppendingString:text]];
    }
}
- (void)keyboardViewBackspace { [self.delegate touchSpecialKey:51 characters:@"\x7f"]; }
- (void)keyboardViewReturn { [self.delegate touchSpecialKey:36 characters:@"\r"]; }
// The microphone key. Dictation belongs to the voice module, which this one cannot include;
// the shell links both and is what answers, exactly as it does for Leave game. In review mode
// the same key is the Composer's entry: one card, one owner of the draft, and an explicit Send.
- (void)keyboardViewToggleDictation {
    if (self.composerInReviewMode) {
        AKLog(@"the layer's keyboard asked for dictation; the Composer takes it");
        [self openChatComposerFromSource:AKChatComposerSourceKeyboard];
        if (AKChatComposer.shared.draftEditable) [AKChatComposer.shared resumeCapture];
        [self applyComposerState];
        return;
    }
    AKLog(@"the layer's keyboard asked for dictation");
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchDictationToggleNotification object:self];
}
- (void)keyboardViewShowSystemKeyboard {
    _ownKeyboard = NO;
    if (_touchPlay) _keyboardRequested = YES;
    _keyboardInput.inputView = nil;
    if (!_keyboardInput.isFirstResponder) [_keyboardInput becomeFirstResponder];
    [_keyboardInput reloadInputViews];
    [self updateKeyboardButton];
    AKLog(@"the keyboard is iPadOS's again (for dictation)");
}
- (void)dismissKeyboard {
    [_textBridge end];
    _keyboardRequested = NO;
    // Back to iPadOS's own keyboard for the next request: dictation's microphone
    // only exists on it.
    if (_ownKeyboard) { _ownKeyboard = NO; _keyboardInput.inputView = nil; [_keyboardInput reloadInputViews]; }
    if (self.keyboardVisible) {
        [self resignFirstResponder];
        if (!_handingOver) [self.superview becomeFirstResponder];
    }
}
// The guest owns its text/selection. Explicit Replace replaces the field.
// Accessory keys still allow editing existing text directly in the guest.
// Touches pass through the toolbar except on its own chrome.
//
// The platform's version named the two buttons it had; this names every control the layer
// puts on the same strip, which is the same rule with the layer's controls in it. It was
// lost when the layer rewrote this file, and without it the toolbar claims every point in
// its frame - so a tap in the gap between two buttons goes to the toolbar instead of to the
// game. The platform's own test is what caught it.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    NSMutableArray<UIView *> *controls = [@[_trackpadButton, _keyboardButton, _gamepadButton,
                                             _settingsButton, _leaveButton, _composer] mutableCopy];
    // The handle exists only in the mobile interface; an array literal would refuse a nil.
    if (_toolbarHandle) [controls addObject:_toolbarHandle];
    for (UIView *control in controls) {
        if (control && !control.hidden && CGRectContainsPoint(control.frame, point)) return YES;
    }
    return NO;
}

- (BOOL)hasText { return YES; }
// The text-input traits, carried over from the platform's version of this class. It is what
// makes iPadOS treat these controls as a text input and offer the layer's own accessory row
// for them, and the platform's test asserts the two that decide that. They were lost when
// the layer rewrote this file; restored verbatim, because none of the layer's changes need
// them to differ.
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UITextSmartQuotesType)smartQuotesType { return UITextSmartQuotesTypeNo; }
- (UITextSmartDashesType)smartDashesType { return UITextSmartDashesTypeNo; }
- (UITextSmartInsertDeleteType)smartInsertDeleteType { return UITextSmartInsertDeleteTypeNo; }
- (UIKeyboardType)keyboardType { return UIKeyboardTypeDefault; }
- (UIReturnKeyType)returnKeyType { return UIReturnKeyDefault; }
// Secure, so the system never offers to remember or spell-check what is typed at the game.
- (BOOL)isSecureTextEntry { return YES; }
- (void)insertText:(NSString *)text { [self.delegate touchInsertText:text]; }
// Dictation types into whatever the controls announced as the game's text input, and it
// asks for these two selectors when it does. They are the adapter's own converter - the
// delegate turns text into key events and posts them to the guest - so this view says the
// same thing to the same place, once, and does nothing else with the words.
- (void)touchInsertText:(NSString *)text {
    if ([self.delegate respondsToSelector:@selector(touchInsertText:)]) [self.delegate touchInsertText:text];
}
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters {
    if ([self.delegate respondsToSelector:@selector(touchSpecialKey:characters:)])
        [self.delegate touchSpecialKey:code characters:characters];
}
- (void)replaceGameText:(NSString *)text {
    // A host with no draft panel leaves this out; the button then does nothing
    // rather than crashing.
    if ([self.delegate respondsToSelector:@selector(touchReplaceText:)]) [self.delegate touchReplaceText:text];
}
- (void)deleteBackward { [self.delegate touchSpecialKey:51 characters:@"\x7f"]; }
// Nothing tells this layer whether the game's chat box is open, so sending must not depend
// on it. A command starts with "/", the game's own key that opens the box with the slash in
// it. A message is preceded by F12, which the Interface mobile add-on binds to "open the box
// on the chosen conversation"; with the box already open, F12 types nothing (the adapter
// never makes text of a function key: patch 0057). Either way the words land in the box and
// Return sends them. The log names the kind of line only: this keyboard also types
// passwords, and their length is not the log's business.
static const unsigned short AKKeyF12 = 111;
- (void)secureEventInputChanged:(NSNotification *)note {
    BOOL enabled = [note.userInfo[@"enabled"] boolValue];
    [_worldSignal secureInputChanged:enabled];
    if (!_textBridge) { _protectedField = enabled; return; }
    _secureOn = enabled;
    // iPad touch. The add-on's pulses (ruling A24) and the game's password box both arrive here; they are told apart
    // by how long secure input stays on. The signal reads them for the world (TouchPlay's buttons); the bridge opens the
    // password field only for an "on" that outlasts its debounce, and tells us then (secureFocusConfirmed), so a
    // pulse never flashes the password keyboard, is never the player's typing, and never opens or closes the chat
    // composer.
    // The scene's state, not only UIApplication's: the game turns secure input off inside
    // UIApplicationWillResignActiveNotification (Face ID's sheet, mid-AutoFill), when UIApplication still says active and
    // only the scene says inactive (device fix 2: read as active, that off closed the field and the fill went nowhere).
    BOOL appActive = [self appIsActive];
    if (enabled) {
        // A secure input that starts in the world has to last longer to be the password box (ruling A27); the signal has
        // just settled whatever was due, so what it says is what this "on" began in.
        _textBridge.inWorld = _worldSignal.state != AKTouchWorldOut;   // a window open is still the world
        [_textBridge secureInputChanged:YES appActive:appActive];
        return;
    }
    if (!appActive) {
        // The game turns secure input off when the app resigns active (Control Centre, a notification, Face ID's sheet)
        // and on again on return; its box has the focus all along. Not the box losing it: the bridge keeps its field, and
        // the controls keep knowing the box is the game's focus - the bridge only re-confirms an "on" it has no field
        // open for, so clearing this here would leave the toolbar's keyboard and Send on the plain composer, typing the
        // password as chat.
        [_textBridge secureInputChanged:NO appActive:NO];
        return;
    }
    // Off while the app is active: the box really lost focus, and the field closes. The bridge first, so nothing it does
    // can leave the box's focus remembered after it.
    [_textBridge secureInputChanged:NO appActive:YES];
    BOOL wasProtected = _protectedField;
    _protectedField = NO;
    if (wasProtected) AKLog(@"keyboard: the game's password box lost focus");
    [self updateKeyboardButton];
}
/// The add-on's pulses say the player entered or left the world (ruling A24), or opened a window in it (ruling A32):
/// TouchPlay's buttons are live, or not; with a window open the walk stick stays live, auto-run included (ruling A34).
- (void)worldChanged:(AKTouchWorldState)state {
    // In the world: past the login screen (back out at the character list it is not the login screen until its password
    // box shows again).
    if (state != AKTouchWorldOut) _loginScreen = NO;
    [self applyWorldToAreas];
}
// iPad touch, 17 Nov 2026 (Return in the account box pressed Login with no password): the composer is typing into the
// login screen's account box. The signal: out of the world (the add-on's pulses; no world entered yet, or two pulses
// since), the game's secure input off (not its password box), and the login screen (the game's start, or its password
// box seen since the player was last in the world). The app cannot see the game's boxes; this is what it can know.
- (BOOL)typingIntoLoginAccountBox {
    return _textBridge && _worldSignal && _worldSignal.state == AKTouchWorldOut && _loginScreen && !_protectedField && !_secureOn;
}
- (void)applyWorldToAreas {
    if (!_worldSignal || !self.superview) return;
    [[AKTouchAreas areasForView:self.superview] setLive:_worldSignal.state == AKTouchWorldIn
                                             windowOpen:_worldSignal.state == AKTouchWorldWindow];
}
// iPad touch, mockups 26, 29, 83: while the password keyboard is up the game slides up by
// AKTouchPasswordSlideFraction of its height, so the login box stays above the keys; back down when it closes.
// The whole game view moves (a translation), so a touch still lands where the player sees it, and the toolbar is
// moved down by the same amount to stay where it is on screen. The view's frame is put back when it comes down,
// in case the window was resized meanwhile.
- (void)slideGameForPassword:(BOOL)up {
    UIView *host = self.superview;
    if (!host) return;
    CGFloat slide = up ? round(host.bounds.size.height * AKTouchPasswordSlideFraction) : 0;
    if (slide == _slide) return;
    _slide = slide;
    AKLog(@"keyboard: the game %@", slide ? @"slides up above the password keyboard" : @"slides back down");
    // Touches keep working while it moves: without AllowUserInteraction UIKit stops hit-testing into a view while it
    // animates, so the game, the toolbar and the gate would miss taps during the slide.
    [UIView animateWithDuration:0.25 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        host.transform = slide ? CGAffineTransformMakeTranslation(0, -slide) : CGAffineTransformIdentity;
        if (!slide && host.superview && !CGRectEqualToRect(host.frame, host.superview.bounds)) host.frame = host.superview.bounds;
        [self placeToolbarInHost:host];
    } completion:nil];
}
// TouchPlay's chat strip was tapped (ruling A7): the chat keyboard, as the toolbar's keyboard button opens it.
- (void)chatAreaTapped:(NSNotification *)note {
    (void)note;
    // Ruling A32: with a window open or out of the world no touch area opens the keyboard - only the game focusing a box
    // does (its password box, below, is that). The strip is not live then, so this is a lift that raced the add-on's pulses.
    if (_worldSignal && !_worldSignal.inWorld && !_protectedField) {
        AKLog(@"keyboard: the chat strip's tap ignored (not in the world with nothing open)");
        return;
    }
    [self cancelTouches];
    // While the game's password box has focus (the login screen, where TouchPlay is not drawn), a tap there is
    // never the cleartext chat: it is the password field (ruling A24, interim).
    [self openKeyboardForPlayer:_protectedField ? @"the chat strip while the password box has focus" : @"the chat strip"];
}
- (void)sendChatText:(NSString *)text {
    if ([self typingIntoLoginAccountBox]) {
        // The account box: the name, then Tab - the game moves to its password box (whose own Return logs in). Never
        // Return here, and never a chat key. Nothing about the name is logged.
        if (text.length) [self.delegate touchInsertText:text];
        [self.delegate touchSpecialKey:48 characters:@"\t"];
        AKLog(@"keyboard: Return in the login's account box is Tab (to the password box), never Login");
        [self dismissKeyboard];
        return;
    }
    if (!text.length) {
        // Nothing typed: Return is just Return.
        [self.delegate touchSpecialKey:36 characters:@"\r"];
        return;
    }
    if (_protectedField) {
        // A password field has the keyboard (the game asked for secure event input), so this
        // line is not chat: type exactly what was written, then Return - the old keyboard's
        // sequence without its leading Return. A chat key has no business in a password
        // field. Nothing about the line is logged.
        [self.delegate touchInsertText:text];
        [self.delegate touchSpecialKey:36 characters:@"\r"];
        AKLog(@"keyboard: a line went to a protected field");
        [self dismissKeyboard];
        return;
    }
    // iPad touch: a chosen chip makes it that channel's slash line, which opens the chat by itself (no F12).
    if (_touchPlay && _chatChannel >= 0 && _chatChannel < AKChatChipCount && ![text hasPrefix:@"/"])
        text = [AKChatChipPrefixes[_chatChannel] stringByAppendingString:text];
    if (![text hasPrefix:@"/"]) [self.delegate touchSpecialKey:AKKeyF12 characters:@"\uF70F"];
    [self.delegate touchInsertText:text];
    [self.delegate touchSpecialKey:36 characters:@"\r"];
    AKLog(@"keyboard: a line went to the chat (%@)", [text hasPrefix:@"/"] ? @"command" : @"message");
    [self dismissKeyboard];
}

- (UIView *)inputAccessoryView { return _touchPlay ? [self chipsRow] : [self keyRow]; }
// 1.0.10's row of the game's own keys above the keyboard: Esc, Tab, arrows, backspace, Return, hide.
- (UIView *)keyRow {
    if (!_accessory) {
        UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
        row.distribution = UIStackViewDistributionFillEqually;
        row.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        NSArray<NSString *> *titles = @[@"Esc", @"Tab", @"←", @"→", @"⌫", @"↵", @"⌄"];
        for (NSUInteger i = 0; i < titles.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.tag = (NSInteger)i;
            button.tintColor = UIColor.whiteColor;
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.accessibilityIdentifier = [NSString stringWithFormat:@"wolkaraforever.keyboard.key.%lu", (unsigned long)i];
            button.accessibilityLabel = @[AKHostLocalized(@"touch.key.escape"), AKHostLocalized(@"touch.key.tab"),
                AKHostLocalized(@"touch.key.leftArrow"), AKHostLocalized(@"touch.key.rightArrow"),
                AKHostLocalized(@"touch.key.gameBackspace"), AKHostLocalized(@"touch.key.return"),
                AKHostLocalized(@"touch.keyboard.hide")][i];
            [button addTarget:self action:@selector(accessoryKey:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
        }
        _accessory = row;
        [self updateDraftButtons];
    }
    return _accessory;
}
// iPad touch's rows above the keys: the chat's chips (mockup 82: Say, Party, Guild, Whisper, Yell; one at a time, the
// chosen one tapped again goes back to the game's own channel), and under them 1.0.10's row of the game's keys, kept
// because Tab, Esc and the arrows are how one moves between the game's own fields (the login screen's).
- (UIView *)chipsRow {
    if (_chips) return _chips;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 52)];
    row.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:row.centerXAnchor],
                                              [stack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]]];
    for (NSInteger i = 0; i < AKChatChipCount; i++) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
        chip.tag = i;
        [chip setTitle:AKHostLocalized([@"touch.chat." stringByAppendingString:AKChatChipKeys[i]]) forState:UIControlStateNormal];
        [chip setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        chip.layer.cornerRadius = 18;
        chip.accessibilityIdentifier = [@"wolkaraforever.chat." stringByAppendingString:AKChatChipKeys[i]];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[[chip.heightAnchor constraintEqualToConstant:36],
                                                  [chip.widthAnchor constraintGreaterThanOrEqualToConstant:88]]];
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:chip];
    }
    _chipStack = stack;
    UIView *keys = [self keyRow];
    UIStackView *column = [[UIStackView alloc] initWithFrame:CGRectMake(0, 0, 320, 52 + 44)];
    column.axis = UILayoutConstraintAxisVertical;
    column.distribution = UIStackViewDistributionFill;
    for (UIView *part in @[row, keys]) {
        part.translatesAutoresizingMaskIntoConstraints = NO;
        [column addArrangedSubview:part];
    }
    [NSLayoutConstraint activateConstraints:@[[row.heightAnchor constraintEqualToConstant:52], [keys.heightAnchor constraintEqualToConstant:44]]];
    _chips = column;
    [self updateChips];
    return column;
}
- (void)chipTapped:(UIButton *)chip {
    _chatChannel = chip.tag == _chatChannel ? -1 : chip.tag;
    AKLog(@"keyboard: chat channel %@", _chatChannel >= 0 ? AKChatChipKeys[_chatChannel] : @"the game's own");
    [self updateChips];
}
- (void)updateChips {
    for (UIButton *chip in _chipStack.arrangedSubviews) {
        chip.selected = chip.tag == _chatChannel;
        chip.backgroundColor = chip.selected ? [UIColor colorWithRed:0.36 green:0.36 blue:0.62 alpha:1] : [UIColor colorWithWhite:1 alpha:0.14];
        chip.accessibilityTraits = chip.selected ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
    }
    _composerLabel.text = [self composerLabelText];
}
// The composer's label: the chosen channel's name, or what the field does.
- (NSString *)composerLabelText {
    if (_touchPlay && _chatChannel >= 0 && _chatChannel < AKChatChipCount)
        return AKHostLocalized([@"touch.chat." stringByAppendingString:AKChatChipKeys[_chatChannel]]);
    return AKComposerDefaultLabel(_mobileInterface);
}
- (void)sendDraft { [_keyboardInput sendDraftToChat]; }
- (void)accessoryKey:(UIButton *)button {
    if (button.tag == 6) { [self dismissKeyboard]; return; }
    // Replace and Return/Tab are deliberate separate steps. Do not accidentally
    // send an unfinished draft or switch the guest field during composition.
    if (_keyboardInput.text.length || ![_keyboardInput canModifyDraft]) return;
    const unsigned short codes[] = {53, 48, 123, 124, 51, 36};
    NSArray<NSString *> *characters = @[@"\x1b", @"\t", @"\uF702", @"\uF703", @"\x7f", @"\r"];
    if (button.tag >= 0 && button.tag < 6) [self.delegate touchSpecialKey:codes[button.tag] characters:characters[button.tag]];
}
- (void)insertDraft { [_keyboardInput forwardCommittedText]; }
- (void)clearDraft { if ([_keyboardInput canModifyDraft]) [_keyboardInput discardDraft]; }

// The composer's language control. Its value is what the shell last published - the adapter
// never invents a language - and its menu asks for one. Choosing is an event, not an input: no
// key and no text leave this method.
- (void)refreshSpeechLanguageButton {
    if (!_speechLanguageButton) return;
    NSString *stored = AKSpeechLanguageStored ?: @"system";
    NSString *name = AKHostLocalized(AKSpeechLanguageNameKey(stored));
    [_speechLanguageButton setTitle:name forState:UIControlStateNormal];
    // The button keeps its label and reports its state as a value, so a screen reader reads
    // "Language, German" rather than "Language, button".
    _speechLanguageButton.accessibilityValue = name;
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    for (NSString *choice in @[@"system", @"en-US", @"de-DE", @"fr-FR", @"es-ES"]) {
        UIAction *action = [UIAction actionWithTitle:AKHostLocalized(AKSpeechLanguageNameKey(choice))
                                              image:nil
                                         identifier:choice
                                            handler:^(UIAction *selected) {
            (void)selected;
            [self chooseSpeechLanguage:choice];
        }];
        action.state = [choice isEqualToString:stored] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    _speechLanguageButton.menu = [UIMenu menuWithTitle:AKHostLocalized(@"voice.language") children:actions];
}
- (void)speechLanguageDidChange:(NSNotification *)note {
    id stored = note.userInfo[AKTouchSpeechLanguageStoredKey];
    AKSpeechLanguageStored = [stored isKindOfClass:NSString.class] ? [stored copy] : @"system";
    [self refreshSpeechLanguageButton];
}
// The one place a choice leaves the adapter. One bounded value, no key and no text: this is
// recognition configuration, and the guest is not told anything by it.
- (void)chooseSpeechLanguage:(NSString *)stored {
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchSpeechLanguageRequestNotification
                                                     object:nil
                                                   userInfo:@{AKTouchSpeechLanguageStoredKey: stored ?: @"system"}];
}
- (void)updateDraftButtons {
    BOOL active = [self composerActive];
    BOOL ready = [_keyboardInput canModifyDraft];
    _insertDraftButton.enabled = !active && [_keyboardInput canReplaceField];
    _clearDraftButton.enabled = !active && ready && _keyboardInput.hasText;
    _sendButton.enabled = ready;
    for (UIButton *button in ((UIStackView *)_accessory).arrangedSubviews) {
        button.enabled = button.tag == 6 || (ready && !_keyboardInput.hasText);
    }
}

#pragma mark - The Chat Composer's card

// Whether a session is on screen. The two terminal states are not: Cancelled has closed the
// card, and Failed needs the card to stay up with the reason on it - that is the error state the
// review record names. With the keyboard up and review mode on, the card is the Composer even
// before a session starts, which is what gives the toolbar its microphone.
- (BOOL)composerActive {
    if (!self.composerInReviewMode) return NO;
    if (self.keyboardVisible) return YES;
    switch (AKChatComposer.shared.state) {
        case AKChatComposerStateOpening:
        case AKChatComposerStateListening:
        case AKChatComposerStateEditing:
        case AKChatComposerStateReady:
        case AKChatComposerStateSending:
        case AKChatComposerStateFailed:
            return YES;
        default:
            return NO;
    }
}

// Review then Send, with the Composer available: the product's answer for a new installation.
// Classic direct - what an existing player has - keeps every entry path doing exactly what it
// did before this feature existed.
// iPad touch keeps its own chat (rulings A7, A25): TouchPlay's chat strip and the toolbar open the
// classic draft with the touch chips and the gold Send, and Send is F12 + the line + Return (or the
// slash line). The Composer's review flow is jklock's answer for every other interface; in iPad touch
// it is never in force, whatever the stored mode, so a mapped button and the keyboard's Return take
// the classic path there (the open request answers "classic-direct").
- (BOOL)composerInReviewMode {
    if (_touchPlay) return NO;
    return AKChatComposerIsAvailable() && AKChatDeliveryModeInForce() == AKChatDeliveryModeReview;
}

- (void)beginChatComposer {
    AKChatComposer *composer = AKChatComposer.shared;
    composer.target = self;
    __weak AKTouchControls *weakSelf = self;
    // The microphone is the app's (Shell/main.m links AKDictation), so the request leaves here as
    // the same kind of notification the keyboard's microphone key already sends. The answer comes
    // back through chatComposerVoiceEvent: with the generation this request carried.
    composer.captureRequest = ^(BOOL start, NSUInteger generation) {
        AKTouchControls *controls = weakSelf;
        if (!controls) return;
        [NSNotificationCenter.defaultCenter
            postNotificationName:AKChatComposerVoiceRequestNotification
                          object:controls
                        userInfo:@{AKChatComposerActionKey: start ? @"begin" : @"cancel",
                                   AKChatComposerGenerationKey: @(generation)}];
    };
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(chatComposerDidChange:)
                   name:AKChatComposerDidChangeNotification object:composer];
    // A mapped button's press, posted by the shell, which is the only place that links both the
    // mapping and this library.
    [center addObserver:self selector:@selector(chatComposerOpenRequested:)
                   name:AKChatComposerOpenNotification object:nil];
    [center addObserver:self selector:@selector(chatComposerVoiceEvent:)
                   name:AKChatComposerVoiceEventNotification object:nil];
    // A controller that goes away mid-capture must not leave a microphone open or a draft that
    // sends itself.
    [center addObserver:self selector:@selector(chatComposerControllerGone:)
                   name:@"GCControllerDidDisconnectNotification" object:nil];
    [self applyComposerState];
}

- (void)chatComposerDidChange:(NSNotification *)note {
    (void)note;
    [self applyComposerState];
}

- (void)chatComposerOpenRequested:(NSNotification *)note {
    NSNumber *source = note.userInfo[AKChatComposerSourceKey];
    NSString *phase = note.userInfo[AKChatComposerPhaseKey];
    if ([phase isEqual:@"ended"]) {
        // A held button was released: the capture ends and the words stay in the draft. A
        // release never sends, whatever the recogniser has produced so far.
        if (AKChatComposer.shared.capturing) [AKChatComposer.shared pauseForEditing];
        [self applyComposerState];
        return;
    }
    [self openChatComposerFromSource:[source isKindOfClass:NSNumber.class]
        ? (AKChatComposerSource)source.integerValue : AKChatComposerSourceController];
}

- (void)chatComposerVoiceEvent:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    NSString *event = info[AKChatComposerEventKey];
    NSUInteger generation = [info[AKChatComposerGenerationKey] unsignedIntegerValue];
    NSString *text = [info[AKChatComposerTextKey] isKindOfClass:NSString.class] ? info[AKChatComposerTextKey] : @"";
    NSString *reason = [info[AKChatComposerReasonKey] isKindOfClass:NSString.class] ? info[AKChatComposerReasonKey] : @"";
    AKChatComposer *composer = AKChatComposer.shared;
    // The Composer decides what a stale generation means; nothing here reads the text.
    if ([event isEqual:@"draft"]) [composer speechDraft:text provisional:YES generation:generation];
    else if ([event isEqual:@"final"]) [composer speechFinished:text generation:generation];
    else if ([event isEqual:@"failure"]) [composer speechFailed:reason generation:generation];
    else if ([event isEqual:@"stopped"]) [composer speechStoppedWithReason:reason generation:generation];
    else AKLog(@"chat-composer: an event this build does not know (%@) was ignored", event);
    [self applyComposerState];
}

- (void)chatComposerControllerGone:(NSNotification *)note {
    (void)note;
    if (AKChatComposer.shared.capturing) AKLog(@"chat-composer: a controller went away during capture");
    [AKChatComposer.shared controllerDidDisconnect];
    [self applyComposerState];
}

- (void)reportComposerOpenOutcome:(NSString *)outcome source:(AKChatComposerSource)source {
    // Synchronous, so the shell's observer runs before the press handler returns. The outcome and
    // the source only: never the draft, never the words.
    [NSNotificationCenter.defaultCenter
        postNotificationName:AKChatComposerOpenResultNotification
                      object:self
                    userInfo:@{AKChatComposerOutcomeKey: outcome,
                               AKChatComposerSourceKey: @(source)}];
}

- (void)openChatComposerFromSource:(AKChatComposerSource)source {
    if (!self.composerInReviewMode) {
        AKLog(@"chat-composer: open asked for from source %ld, but the delivery mode is classic direct",
              (long)source);
        [self reportComposerOpenOutcome:@"classic-direct" source:source];
        return;
    }
    [self cancelTouches];
    AKChatComposer *composer = AKChatComposer.shared;
    BOOL opened = [composer openWithSource:source];
    // The card and the draft editor come up either way: a refused open has a reason to show, and
    // the player's next action is Cancel. The keyboard is what makes the draft typeable.
    if (!self.keyboardVisible) [self becomeFirstResponder];
    [self applyComposerState];
    if (opened) AKLog(@"chat-composer: card up for source %ld", (long)source);
    [self reportComposerOpenOutcome:(opened ? @"opened" : @"refused") source:source];
}

// The card's height in the two modes, grown by whatever the player's text size added to the label
// and the action row. At the default category it is exactly 82 and 130 - the heights every release
// through v1.0.10 has used - and the editor stays 48 points either way.
- (CGFloat)cardHeightForComposer:(BOOL)active {
    CGFloat grown = (_composerLabelRowHeight - 16) +
        (active ? _composerActionRowHeight - 44 : 0);
    return (active ? AKComposerCardHeightComposer : AKComposerCardHeightClassic) + grown;
}

// The player's text size changed, or the card was just built: re-read it. The fonts come from
// UIFontMetrics, which at the default category gives back the sizes the card has always had.
- (void)applyComposerTextSize {
    if (!_composer) return;
    _composerLabel.font = AKComposerFont(UIFontTextStyleCaption1, NO);
    UIFont *action = AKComposerFont(UIFontTextStyleHeadline, YES);
    _composerSendButton.titleLabel.font = action;
    _composerCancelButton.titleLabel.font = action;
    UIFont *chip = AKComposerFont(UIFontTextStyleSubheadline, NO);
    UIStackView *chips = (UIStackView *)_composerChips.subviews.firstObject;
    if ([chips isKindOfClass:UIStackView.class]) {
        for (UIView *view in chips.arrangedSubviews) {
            if (![view isKindOfClass:UIButton.class]) continue;
            ((UIButton *)view).titleLabel.font = chip;
            for (NSLayoutConstraint *constraint in view.constraints) {
                if (constraint.firstAttribute == NSLayoutAttributeHeight && !constraint.secondItem) {
                    constraint.constant = AKComposerChipBox(chip);
                }
            }
        }
    }
    _composerLabelRowHeight = AKComposerLabelBox(_composerLabel.font);
    _composerActionRowHeight = AKComposerActionBox(action);
    _composerLabelHeight.constant = _composerLabelRowHeight;
    BOOL active = [self composerActive];
    _composerHeight.constant = [self cardHeightForComposer:active];
    AKLog(@"toolbar: draft card text size %s (label=%.0f row=%.0f)",
          UIApplication.sharedApplication.preferredContentSizeCategory.UTF8String,
          _composerLabelRowHeight, _composerActionRowHeight);
}

- (void)contentSizeCategoryChanged:(NSNotification *)notification {
    (void)notification;
    [self applyComposerTextSize];
    [self setNeedsLayout];
    if (self.superview) [self placeToolbarInHost:self.superview];
}

// One place draws the card from the Composer's state: the label, the draft, which row is up, the
// card's height and what can be pressed.
- (void)applyComposerState {
    AKChatComposer *composer = AKChatComposer.shared;
    if (!AKChatComposerIsAvailable() && composer.state != AKChatComposerStateIdle &&
        composer.state != AKChatComposerStateCancelled) {
        // The flag was turned off while a session was open: rollback, once.
        AKLog(@"chat-composer: the Composer was switched off with a session open; rolling back");
        [composer composerWasTurnedOff];
    }
    BOOL active = [self composerActive];
    // The card is the draft's: up with the draft editor, never for iPad touch's password field (which also
    // counts as a visible keyboard). Outside iPad touch the two are the same thing.
    _composer.hidden = !(_keyboardInput.isFirstResponder || active || composer.state == AKChatComposerStateFailed);
    _composerRow.hidden = !active;
    if (_composer.superview) [self setNeedsLayout];
    // iPad touch has the gold Send where Replace was (mockup 82); Replace is never shown there.
    _insertDraftButton.hidden = active || _sendButton != nil;
    _clearDraftButton.hidden = active;
    _speechLanguageButton.hidden = active;

    // The two geometries are a switch, not a toggle: set all four every time, so the state is
    // idempotent and cannot be half-applied. The old code guarded the swap on one constraint's
    // current state (and kept the card height inside that guard), so the trailing and bottom
    // halves could disagree - the draft ended up pinned to the card's bottom and to the row's
    // top at once, which squeezed the action row to zero height and let the editor take the
    // difference. Measured 2026-11-16 through the touch fixture: card 130 (right), editor 96
    // (should be 48), action row 0 (should be 44), with both bottom pins live.
    _classicEditorTrailing.active = !active;
    _classicEditorBottom.active = !active;
    _composerEditorTrailing.active = active;
    _composerEditorBottom.active = active;
    _composerHeight.constant = [self cardHeightForComposer:active];

    NSString *stateText = nil;
    switch (composer.state) {
        case AKChatComposerStateOpening: stateText = AKHostLocalized(@"chat.composer.state.opening"); break;
        case AKChatComposerStateListening: stateText = AKHostLocalized(@"chat.composer.state.listening"); break;
        case AKChatComposerStateEditing: stateText = AKHostLocalized(@"chat.composer.state.editing"); break;
        case AKChatComposerStateReady: stateText = AKHostLocalized(@"chat.composer.state.ready"); break;
        case AKChatComposerStateSending: stateText = AKHostLocalized(@"chat.composer.state.sending"); break;
        case AKChatComposerStateCancelled: stateText = AKHostLocalized(@"chat.composer.state.cancelled"); break;
        case AKChatComposerStateFailed:
            // Both problem keys are named literally, so the table check can see they are used.
            stateText = AKHostLocalized([composer.problem isEqual:@"nothingHeard"]
                ? @"chat.composer.problem.nothingHeard" : @"chat.composer.problem.notSent");
            break;
        default:
            // Idle: the review card before a session starts. Its placeholder says what this card
            // does, because "Replaces the field" describes the classic one and would be a lie.
            // Classic: what the field does, or iPad touch's chosen chat channel (composerLabelText).
            stateText = self.composerInReviewMode ? AKHostLocalized(@"chat.composer.placeholder")
                                                 : [self composerLabelText];
            break;
    }
    BOOL failed = composer.state == AKChatComposerStateFailed;
    _composerLabel.text = stateText;
    _composerLabel.textColor = failed ? UIColor.systemOrangeColor : UIColor.lightGrayColor;
    _composerLabel.isAccessibilityElement = YES;
    _composerLabel.accessibilityLabel = stateText;
    _composerLabel.accessibilityIdentifier = @"wolkaraforever.composer.state";

    if (active || (self.composerInReviewMode && composer.state == AKChatComposerStateFailed)) {
        NSString *draft = composer.draft;
        if (![(_keyboardInput.text ?: @"") isEqualToString:draft]) {
            // Only when the Composer changed it - a transcript, a send that cleared it. Typing
            // already agrees with the draft, so the caret is never yanked while someone types.
            _applyingComposerDraft = YES;
            _keyboardInput.text = draft;
            _applyingComposerDraft = NO;
        }
        AKLog(@"chat-composer: state=%ld draft=%lu characters sendable=%d",
              (long)composer.state, (unsigned long)draft.length, (int)composer.canSend);
    }

    _composerSendButton.enabled = active && composer.canSend;
    _composerCancelButton.enabled = active;
    _composerListenButton.enabled = active && composer.state != AKChatComposerStateSending;
    [_composerListenButton setImage:[UIImage systemImageNamed:(composer.capturing ? @"mic.fill" : @"mic")]
                           forState:UIControlStateNormal];
    _composerListenButton.accessibilityLabel = AKHostLocalized(composer.capturing
        ? @"chat.composer.action.stop" : @"chat.composer.action.listen");
    // VoiceOver: the card says its condition as a value and reads in one fixed order,
    // exposing only the controls this mode shows - the classic card keeps Clear and
    // Replace, and the Composer card puts its own row after the draft.
    _composer.accessibilityValue = stateText;
    _composer.accessibilityViewIsModal = YES;
    _composer.accessibilityElements = active
        ? @[_composerLabel, _keyboardInput, _composerChips, _composerCancelButton,
            _composerListenButton, _composerSettingsButton, _composerSendButton]
        : @[_composerLabel, _keyboardInput, _clearDraftButton, _insertDraftButton];
    [self rebuildDestinationChips];
    [self updateDraftButtons];
    if (self.superview) [self placeToolbarInHost:self.superview];
}

- (void)rebuildDestinationChips {
    NSArray<AKChatDestination *> *destinations = AKChatDestinationStore.shared.enabled;
    NSString *key = [[destinations valueForKey:@"identifier"] componentsJoinedByString:@","];
    UIStackView *chips = (UIStackView *)_composerChips.subviews.firstObject;
    if (![chips isKindOfClass:UIStackView.class]) return;
    if ([key isEqual:_composerChips.accessibilityValue ?: @""] && chips.arrangedSubviews.count == destinations.count)
        return;
    for (UIView *view in chips.arrangedSubviews) { [chips removeArrangedSubview:view]; [view removeFromSuperview]; }
    for (AKChatDestination *destination in destinations) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:destination.title forState:UIControlStateNormal];
        chip.titleLabel.font = AKComposerFont(UIFontTextStyleSubheadline, NO);
        chip.titleLabel.adjustsFontForContentSizeCategory = YES;
        chip.layer.cornerRadius = 8;
        chip.backgroundColor = [UIColor colorWithWhite:0.26 alpha:1];
        chip.accessibilityIdentifier = [NSString stringWithFormat:@AKChatComposerDestinationIdentifierFormat,
                                        destination.identifier];
        chip.accessibilityHint = AKHostLocalized(@"chat.composer.destination.hint");
        [chip addTarget:self action:@selector(composerDestinationTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chips addArrangedSubview:chip];
        [chip.heightAnchor constraintEqualToConstant:AKComposerChipBox(chip.titleLabel.font)].active = YES;
        [chip.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    }
    _composerChips.accessibilityValue = destinations.count ? key : @"";
}

#pragma mark The card's own actions

// The draft editor speaks: the Composer's draft follows the visible text, and editing is what
// pauses capture. Guarded against the one loop that would matter - the Composer writing the
// draft back into the editor, which arrives here looking like a person typing.
- (void)draftEditorChanged:(NSString *)text {
    if (_applyingComposerDraft) return;
    if (!self.composerInReviewMode) return;
    [AKChatComposer.shared userChangedDraft:text];
}

// Return pressed in the draft editor while review mode is on: the same explicit Send, through
// the same transaction, so nothing reaches the guest twice.
- (void)composerTakesDraft:(NSString *)text {
    AKChatComposer *composer = AKChatComposer.shared;
    [composer userChangedDraft:text];
    [composer sendWithDestination:nil];
    [self applyComposerState];
}

- (void)composerCancel {
    [AKChatComposer.shared cancel];
    [self applyComposerState];
    [self dismissKeyboard];
}

- (void)composerSend { [AKChatComposer.shared sendWithDestination:nil]; }

- (void)composerDestinationTapped:(UIButton *)button {
    for (AKChatDestination *destination in AKChatDestinationStore.shared.enabled) {
        NSString *identifier = [NSString stringWithFormat:@AKChatComposerDestinationIdentifierFormat,
                                destination.identifier];
        if (![button.accessibilityIdentifier isEqual:identifier]) continue;
        AKLog(@"chat-composer: a destination chip was pressed (%@)", destination.identifier);
        [AKChatComposer.shared sendWithDestination:destination];
        return;
    }
}

- (void)composerListen {
    AKChatComposer *composer = AKChatComposer.shared;
    if (composer.state == AKChatComposerStateIdle) {
        // The toolbar's microphone, before any session: an Open like the layer
        // keyboard's key and the mapped button, so the game's chat is opened once and
        // listening starts. Capture with no open chat would record words with nowhere
        // to put them.
        AKLog(@"chat-composer: the card's microphone opens a session");
        [self openChatComposerFromSource:AKChatComposerSourceToolbar];
        return;
    }
    if (composer.capturing) [composer pauseForEditing];
    else [composer resumeCapture];
    [self applyComposerState];
}

#pragma mark The guest, as the Composer sees it

- (BOOL)chatTargetIsLive { return self.window != nil && self.delegate != nil; }

- (BOOL)chatOpen {
    if (![self chatTargetIsLive]) return NO;
    if (_protectedField) {
        // Secure event input is on: the game has a password field, where a chat key has no
        // business. Measured behaviour of the classic path, kept.
        AKLog(@"chat-composer: the guest's keyboard is in a protected field; chat was not opened");
        return NO;
    }
    [self.delegate touchSpecialKey:AKKeyReturnCode characters:@"\r"];
    return YES;
}

- (BOOL)chatInsertText:(NSString *)text {
    if (![self chatTargetIsLive] || !text.length) return NO;
    [self.delegate touchInsertText:text];
    return YES;
}

- (BOOL)chatPostKey:(unsigned short)code characters:(NSString *)characters {
    if (![self chatTargetIsLive]) return NO;
    [self.delegate touchSpecialKey:code characters:characters];
    return YES;
}

#pragma mark The Composer's settings

// Everything the Composer lets a player decide, in one sheet: the delivery mode (which is also
// how classic dictation comes back) and up to four destinations. It lives here rather than on
// the launcher's Voice page so that no approved launcher baseline changes in a feature release.
- (void)showComposerSettings {
    UIViewController *root = self.window.rootViewController;
    if (!root || root.presentedViewController) return;
    AKChatDestinationStore *store = AKChatDestinationStore.shared;
    BOOL review = AKChatDeliveryModeInForce() == AKChatDeliveryModeReview;
    NSString *mode = AKHostLocalized(review ? @"chat.composer.settings.mode.review"
                                            : @"chat.composer.settings.mode.classic");
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:AKHostLocalized(@"chat.composer.settings.title")
                         message:AKHostLocalizedFormat(@"chat.composer.settings.message", mode)
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak AKTouchControls *weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:AKHostLocalized(review
            ? @"chat.composer.settings.useClassic" : @"chat.composer.settings.useReview")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        AKTouchControls *controls = weakSelf;
        if (!controls) return;
        if (review) {
            // Classic direct is what a player had before the Composer; going back to it ends any
            // session that is open and sends nothing.
            [AKChatComposer.shared cancel];
            AKChatDeliveryModeSet(AKChatDeliveryModeClassicDirect);
        } else {
            AKChatDeliveryModeSet(AKChatDeliveryModeReview);
        }
        [controls applyComposerState];
    }]];
    if (store.all.count < [AKChatDestinationStore maximumCount]) {
        [sheet addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"chat.composer.settings.add")
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            [weakSelf askForDestination];
        }]];
    }
    for (AKChatDestination *destination in store.all) {
        [sheet addAction:[UIAlertAction actionWithTitle:AKHostLocalizedFormat(@"chat.composer.settings.remove",
                                                                              destination.title)
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            (void)action;
            NSMutableArray<AKChatDestination *> *kept = [NSMutableArray array];
            for (AKChatDestination *existing in store.all)
                if (![existing.identifier isEqual:destination.identifier]) [kept addObject:existing];
            [store replaceAll:kept];
            [weakSelf applyComposerState];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"chat.composer.settings.done")
                                              style:UIAlertActionStyleCancel handler:nil]];
    [root presentViewController:sheet animated:YES completion:nil];
}

- (void)askForDestination {
    UIViewController *root = self.window.rootViewController;
    if (!root || root.presentedViewController) return;
    UIAlertController *ask = [UIAlertController
        alertControllerWithTitle:AKHostLocalized(@"chat.composer.settings.add")
                         message:AKHostLocalized(@"chat.composer.settings.add.message")
                  preferredStyle:UIAlertControllerStyleAlert];
    [ask addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = AKHostLocalized(@"chat.composer.destination.title");
        field.accessibilityIdentifier = @"wolkaraforever.composer.destination.title";
    }];
    [ask addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = AKHostLocalized(@"chat.composer.destination.command");
        field.accessibilityIdentifier = @"wolkaraforever.composer.destination.command";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak AKTouchControls *weakSelf = self;
    [ask addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"chat.composer.settings.done")
                                            style:UIAlertActionStyleCancel handler:nil]];
    [ask addAction:[UIAlertAction actionWithTitle:AKHostLocalized(@"chat.composer.settings.save")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        UITextField *title = ask.textFields.firstObject;
        UITextField *command = ask.textFields.lastObject;
        AKChatDestinationStore *store = AKChatDestinationStore.shared;
        NSString *identifier = [NSString stringWithFormat:@"custom%lu",
                                (unsigned long)store.all.count + 1];
        AKChatDestination *destination = [AKChatDestination destinationWithIdentifier:identifier
                                                                               title:title.text ?: @""
                                                                             command:command.text ?: @""
                                                                             enabled:YES];
        NSMutableArray<AKChatDestination *> *next = [store.all mutableCopy] ?: [NSMutableArray array];
        [next addObject:destination];
        // Disabled on the way in unless the player says otherwise: a record is enabled by being
        // used, never by existing.
        if ([store replaceAll:next]) [weakSelf applyComposerState];
    }]];
    [root presentViewController:ask animated:YES completion:nil];
}
- (void)buildComposer {
    _composer = [[UIView alloc] initWithFrame:CGRectZero];
    _composer.hidden = YES;
    _composer.translatesAutoresizingMaskIntoConstraints = NO;
    _composer.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
    _composer.layer.cornerRadius = 12;
    _composer.layer.zPosition = self.layer.zPosition;
    UILabel *label = _composerLabel = [UILabel new];
    label.text = AKComposerDefaultLabel(AKInterfaceModeIsMobile());
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = UIColor.lightGrayColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;
    label.accessibilityIdentifier = @"wolkaraforever.composer.state";
    UIButton *insert = _insertDraftButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [insert setTitle:AKHostLocalized(@"touch.draft.replace") forState:UIControlStateNormal];
    insert.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    insert.accessibilityIdentifier = @"wolkaraforever.keyboard.insert";
    insert.accessibilityHint = AKHostLocalized(@"touch.draft.replace.hint");
    [insert addTarget:self action:@selector(insertDraft) forControlEvents:UIControlEventTouchUpInside];
    UIButton *clear = _clearDraftButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setImage:[UIImage systemImageNamed:@"xmark.circle"] forState:UIControlStateNormal];
    clear.accessibilityLabel = AKHostLocalized(@"touch.draft.clear");
    clear.accessibilityIdentifier = @"wolkaraforever.keyboard.clear";
    [clear addTarget:self action:@selector(clearDraft) forControlEvents:UIControlEventTouchUpInside];
    // The Composer's row: Cancel, the configured destination chips, speak, settings, Send. The
    // chips scroll sideways rather than being dropped, so four destinations on a phone in
    // landscape stay reachable and Send never moves. It sits below the draft, which is what makes
    // the card one row taller while the Composer is open.
    UIView *row = _composerRow = [UIView new];
    row.hidden = YES;
    _composerCancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_composerCancelButton setTitle:AKHostLocalized(@"chat.composer.action.cancel") forState:UIControlStateNormal];
    _composerCancelButton.titleLabel.font = AKComposerFont(UIFontTextStyleHeadline, YES);
    _composerCancelButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    _composerCancelButton.accessibilityIdentifier = @"wolkaraforever.composer.cancel";
    _composerCancelButton.accessibilityHint = AKHostLocalized(@"chat.composer.action.cancel.hint");
    [_composerCancelButton addTarget:self action:@selector(composerCancel) forControlEvents:UIControlEventTouchUpInside];
    _composerListenButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_composerListenButton setImage:[UIImage systemImageNamed:@"mic"] forState:UIControlStateNormal];
    _composerListenButton.accessibilityLabel = AKHostLocalized(@"chat.composer.action.listen");
    _composerListenButton.accessibilityIdentifier = @"wolkaraforever.composer.listen";
    [_composerListenButton addTarget:self action:@selector(composerListen) forControlEvents:UIControlEventTouchUpInside];
    _composerSettingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_composerSettingsButton setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    _composerSettingsButton.accessibilityLabel = AKHostLocalized(@"chat.composer.action.settings");
    _composerSettingsButton.accessibilityIdentifier = @"wolkaraforever.composer.settings";
    [_composerSettingsButton addTarget:self action:@selector(showComposerSettings) forControlEvents:UIControlEventTouchUpInside];
    _composerSendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_composerSendButton setTitle:AKHostLocalized(@"chat.composer.action.send") forState:UIControlStateNormal];
    _composerSendButton.titleLabel.font = AKComposerFont(UIFontTextStyleHeadline, YES);
    _composerSendButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    _composerSendButton.accessibilityIdentifier = @"wolkaraforever.composer.send";
    [_composerSendButton addTarget:self action:@selector(composerSend) forControlEvents:UIControlEventTouchUpInside];
    _composerChips = [UIScrollView new];
    _composerChips.showsHorizontalScrollIndicator = NO;
    _composerChips.accessibilityIdentifier = @"wolkaraforever.composer.destinations";
    UIStackView *chips = [UIStackView new];
    chips.axis = UILayoutConstraintAxisHorizontal;
    chips.spacing = 6;
    chips.translatesAutoresizingMaskIntoConstraints = NO;
    [_composerChips addSubview:chips];
    [NSLayoutConstraint activateConstraints:@[
        [chips.leadingAnchor constraintEqualToAnchor:_composerChips.contentLayoutGuide.leadingAnchor],
        [chips.trailingAnchor constraintEqualToAnchor:_composerChips.contentLayoutGuide.trailingAnchor],
        [chips.topAnchor constraintEqualToAnchor:_composerChips.contentLayoutGuide.topAnchor],
        [chips.bottomAnchor constraintEqualToAnchor:_composerChips.contentLayoutGuide.bottomAnchor],
        [chips.heightAnchor constraintEqualToAnchor:_composerChips.frameLayoutGuide.heightAnchor],
    ]];
    for (UIView *view in @[_composerCancelButton, _composerChips, _composerListenButton,
                           _composerSettingsButton, _composerSendButton]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_composerCancelButton.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [_composerCancelButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        // A minimum, so a larger text size makes the button taller instead of clipping its title.
        [_composerCancelButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [_composerChips.leadingAnchor constraintEqualToAnchor:_composerCancelButton.trailingAnchor constant:6],
        [_composerChips.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [_composerChips.heightAnchor constraintEqualToAnchor:row.heightAnchor],
        [_composerListenButton.leadingAnchor constraintEqualToAnchor:_composerChips.trailingAnchor constant:6],
        [_composerListenButton.widthAnchor constraintEqualToConstant:44],
        [_composerListenButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [_composerSettingsButton.leadingAnchor constraintEqualToAnchor:_composerListenButton.trailingAnchor],
        [_composerSettingsButton.widthAnchor constraintEqualToConstant:44],
        [_composerSettingsButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [_composerSendButton.leadingAnchor constraintEqualToAnchor:_composerSettingsButton.trailingAnchor],
        [_composerSendButton.widthAnchor constraintGreaterThanOrEqualToConstant:64],
        [_composerSendButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [_composerSendButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    // The recogniser's language, beside the draft it will type into. It is recognition
    // configuration rather than input: choosing a language posts one bounded value to the shell
    // and sends nothing to the guest. It is here rather than on the launcher's settings page
    // because that page is a reviewed baseline image, and this feature is additive.
    UIButton *language = _speechLanguageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    language.isAccessibilityElement = YES;
    language.accessibilityIdentifier = @"wolkaraforever.keyboard.language";
    language.accessibilityLabel = AKHostLocalized(@"voice.language");
    language.accessibilityHint = AKHostLocalized(@"voice.language.hint");
    language.titleLabel.font = [UIFont systemFontOfSize:13];
    language.showsMenuAsPrimaryAction = YES;
    // The action row is the one view in the card not laid out by constraints: see -layoutSubviews.
    NSMutableArray<UIView *> *parts = [@[label, _keyboardInput, language, clear, insert] mutableCopy];
    // iPad touch (mockup 82): a gold Send where Replace was; Replace (fill the game's selected field) is not part of it.
    if (AKInterfaceModeIsTouchPlay()) {
        UIButton *send = _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [send setTitle:AKHostLocalized(@"touch.chat.send") forState:UIControlStateNormal];
        UIColor *gold = [UIColor colorWithRed:1 green:0.83 blue:0.30 alpha:1];
        [send setTitleColor:gold forState:UIControlStateNormal];
        [send setTitleColor:[gold colorWithAlphaComponent:0.4] forState:UIControlStateDisabled];
        send.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        send.backgroundColor = [UIColor colorWithRed:0.55 green:0.04 blue:0.04 alpha:1];
        send.layer.cornerRadius = 8;
        send.layer.borderWidth = 2;
        send.layer.borderColor = gold.CGColor;
        send.accessibilityIdentifier = @"wolkaraforever.keyboard.send";
        [send addTarget:self action:@selector(sendDraft) forControlEvents:UIControlEventTouchUpInside];
        insert.hidden = YES;
        [parts addObject:send];
    }
    for (UIView *view in parts) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_composer addSubview:view];
    }
    [_composer addSubview:row];
    // The classic geometry, unchanged from every release through v1.0.10: the draft beside the
    // clear button and Replace, in a card 82 points tall.
    _classicEditorTrailing = [_keyboardInput.trailingAnchor constraintEqualToAnchor:language.leadingAnchor];
    _classicEditorBottom = [_keyboardInput.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-8];
    // The Composer's: the draft on its own line, the action row beneath it, and the card one
    // 44-point row taller.
    _composerEditorTrailing = [_keyboardInput.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-8];
    _composerEditorBottom = [_keyboardInput.bottomAnchor constraintEqualToAnchor:row.topAnchor constant:-4];
    for (NSLayoutConstraint *constraint in @[_composerEditorTrailing, _composerEditorBottom]) constraint.active = NO;
    _composerHeight = [_composer.heightAnchor constraintEqualToConstant:AKComposerCardHeightClassic];
    _composerLabelHeight = [label.heightAnchor constraintEqualToConstant:AKComposerLabelBox(label.font)];
    _composerLabelRowHeight = _composerLabelHeight.constant;
    _composerActionRowHeight = AKComposerActionBox(_composerSendButton.titleLabel.font);
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:12],
        [label.topAnchor constraintEqualToAnchor:_composer.topAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-12],
        _composerLabelHeight,
        [_keyboardInput.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:8],
        [_keyboardInput.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:4],
        [_keyboardInput.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-8],
        [_keyboardInput.trailingAnchor constraintEqualToAnchor:language.leadingAnchor],
        [language.heightAnchor constraintEqualToConstant:44],
        [language.widthAnchor constraintGreaterThanOrEqualToConstant:64],
        [language.centerYAnchor constraintEqualToAnchor:_keyboardInput.centerYAnchor],
        [language.trailingAnchor constraintEqualToAnchor:clear.leadingAnchor],
        [clear.widthAnchor constraintEqualToConstant:44],
        [clear.heightAnchor constraintEqualToConstant:44],
        [clear.centerYAnchor constraintEqualToAnchor:_keyboardInput.centerYAnchor],
        [insert.leadingAnchor constraintEqualToAnchor:clear.trailingAnchor],
        // Wide enough for "Replace" at the size it has always been drawn; the localised title
        // decides anything longer, so it is a minimum rather than a fixed width.
        [insert.widthAnchor constraintGreaterThanOrEqualToConstant:84],
        [insert.heightAnchor constraintEqualToConstant:44],
        [insert.centerYAnchor constraintEqualToAnchor:_keyboardInput.centerYAnchor],
        [insert.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-8],
        _classicEditorTrailing, _classicEditorBottom, _composerHeight,
    ]];
    [self refreshSpeechLanguageButton];
    if (_sendButton) [NSLayoutConstraint activateConstraints:@[
        [_sendButton.widthAnchor constraintEqualToConstant:84], [_sendButton.heightAnchor constraintEqualToConstant:52],
        [_sendButton.centerYAnchor constraintEqualToAnchor:_keyboardInput.centerYAnchor],
        [_sendButton.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-8],
    ]];
}
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [_composer removeFromSuperview];
    UIView *host = self.superview;
    if (!host) return;
    [host addSubview:_composer];
    if (_touchPlay) gTouchPlayControls = self;   // AKTouchReleaseEverything reaches the running guest's controls
    [_textBridge attachToView:host];
    [self applyWorldToAreas];   // a game start is out of the world (ruling A24)
    // The editor follows the keyboard; the toolbar stays fixed at the top.
    // No resizing of the game's rendering surface or reading of game memory.
    NSLayoutConstraint *width = [_composer.widthAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.widthAnchor constant:-24];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_composer.bottomAnchor constraintEqualToAnchor:host.keyboardLayoutGuide.topAnchor constant:-4],
        [_composer.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        width, [_composer.widthAnchor constraintLessThanOrEqualToConstant:800],
    ]];

    // Placement happens in layoutSubviews, by frame, from the host's own bounds - see
    // placeToolbarInHost. Constraints are the host's to set, and Apple says a view must
    // not set translatesAutoresizingMaskIntoConstraints on itself; frame placement from
    // the host's bounds is the one thing neither can argue with.
    // iPad touch has no controller overlay and attaches no virtual gamepad to the game: the sticks,
    // shoulders and face buttons are the add-on's to draw, and a layer of ours over them is what
    // swallowed its taps. The toolbar above stays. Every other mode makes it as it always has.
    if (!_gamepad && !_touchPlay) {
        _gamepad = [[AKTouchGamepad alloc] initWithHostView:host];
        __weak AKTouchControls *weakSelf = self;
        _gamepad.visibilityChanged = ^(BOOL visible) {
            AKTouchControls *controls = weakSelf;
            if (!controls) return;
            [controls cancelCameraGesture:@"controller"];
            [controls setGamepadVisible:visible];
        };
        _gamepad.enabled = _gamepadEnabled;
    }
    // ...and iPad touch has the walk stick in their place, under this toolbar so the toolbar keeps its
    // taps where it reaches into the walk half.
    if (!_walkStick && _touchPlay) _walkStick = [[AKTouchGamepad alloc] initWalkStickWithHostView:host below:self];
    // ...and the gate that closes the chat on a tap on the game: above the stick, under this toolbar and the composer.
    if (_touchPlay) {
        if (!_gate) { _gate = [[AKTouchKeyboardGate alloc] initWithFrame:host.bounds]; _gate.controls = self; }
        _gate.frame = host.bounds;
        [host insertSubview:_gate belowSubview:self];
    }
    _gamepad.keyboardVisible = self.keyboardVisible;
    _walkStick.keyboardVisible = self.keyboardVisible;
    [_gamepad refresh];
}

- (void)processTouches:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.trackpadEnabled) return;
    // Exactly the flow this file has always had: a cancelled touch cancels the gesture and the
    // update below still runs, with the platform suppressing the remainder of it. Returning
    // early would be a different rule wearing the same name.
    for (UITouch *touch in touches) if (touch.phase == UITouchPhaseCancelled) [self cancelTouches];
    unsigned count = 0;
    CGPoint center = CGPointZero;
    for (UITouch *touch in event.allTouches) {
        if (touch.type != UITouchTypeDirect || touch.view != self.superview ||
            touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) continue;
        CGPoint point = [touch locationInView:self.superview];
        center.x += point.x; center.y += point.y; count++;
    }
    if (count) { center.x /= count; center.y /= count; }
    AKTouchCameraUpdate(&_camera, count, center.x, center.y, event.timestamp,
                        self.superview.bounds.size, AKEmitTouch, (__bridge void *)self);
    [_holdTimer invalidate]; _holdTimer = nil;
    if (_camera.pad.fingers && !_camera.pad.blocked && !_camera.pad.lifting && !_camera.pad.dragging &&
        _camera.pad.travelled <= 8) {
        __weak AKTouchControls *weakSelf = self;
        unsigned generation = _camera.generation;
        _holdTimer = [NSTimer timerWithTimeInterval:MAX(0.01, _camera.pad.started + 0.46 - NSProcessInfo.processInfo.systemUptime)
                                          repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            AKTouchControls *controls = weakSelf;
            // The gesture this timer was started for may already have been taken away (the
            // background, a rotation, our own panel). A late fire must not press into a
            // gesture that no longer exists, and must never outlive it.
            if (controls && controls->_camera.generation == generation)
                AKTouchCameraHold(&controls->_camera, NSProcessInfo.processInfo.systemUptime, AKEmitTouch, (__bridge void *)controls);
        }];
        [NSRunLoop.mainRunLoop addTimer:_holdTimer forMode:NSRunLoopCommonModes];
    }
}
// The one way out of a camera gesture. `reason` is what the log will say it was.
- (void)cancelCameraGesture:(NSString *)reason {
    [_holdTimer invalidate]; _holdTimer = nil;
    AKTouchCameraReset(&_camera, reason, AKEmitTouch, (__bridge void *)self);
}
- (void)cancelTouches {
    [self cancelCameraGesture:@"cancelled"];
}
// The controller's touchpad, relayed by the app. Motion and scrolling go through the same
// delegate calls a finger on the screen uses; the click is the pointer's button.
- (void)controllerTouchpad:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    void *context = (__bridge void *)self;
    if ([info[@"reset"] boolValue]) { AKControllerPointerReset(&_controllerPointer, AKEmitTouch, context); return; }
    NSNumber *click = info[@"click"];
    if ([click isKindOfClass:NSNumber.class]) {
        AKControllerPointerClick(&_controllerPointer, click.boolValue, AKEmitTouch, context);
        return;
    }
    NSNumber *fingers = info[@"fingers"], *x = info[@"x"], *y = info[@"y"], *time = info[@"time"];
    if (![fingers isKindOfClass:NSNumber.class] || ![x isKindOfClass:NSNumber.class] ||
        ![y isKindOfClass:NSNumber.class] || ![time isKindOfClass:NSNumber.class]) return;
    AKControllerPointerUpdate(&_controllerPointer, fingers.unsignedIntValue, x.doubleValue, y.doubleValue,
                              time.doubleValue, AKEmitTouch, context);
}
// The controls of the guest that is running (iPad touch only; there is one per guest). AKTouchReleaseEverything
// reaches it from anywhere without the caller holding a reference.
static __weak AKTouchControls *gTouchPlayControls;
void AKTouchReleaseEverything(void) { [gTouchPlayControls releaseEverythingClosingKeyboard:YES]; }

// Task 8 (review focus 4): the app is leaving the screen with fingers and keys down. One entry point lets go of
// everything the TouchPlay layer can hold; each part lets go of its own and nothing is tapped, held or clicked on
// the way out:
//   - the buttons: every press key (Jump, Dive) up with its chord, a hold ring cancelled - its hold key never goes -
//     and an aimed spell stopped with Interact's stop key (AKTouchAreas cancelAll, rulings A19, A21); the fingers
//     stay the areas' until they lift, sending nothing;
//   - the walk stick: every walk key up, the vector zero, the ring hidden, auto-run off;
//   - the host's world gesture: the mouse button a drag holds comes up (patch 0070);
//   - the text keyboard: the password field is closed with nothing sent (the text bridge holds no key). The one
//     exception is a resign: iPadOS puts Face ID's and the Passwords sheet over the app while a password is being
//     filled, which resigns the app active in the middle of it - closing the field then would lose the fill. A
//     resign leaves the field to the system; the app really going to the background closes it.
// Not in iPad touch (no registered controls): nothing at all.
- (void)releaseEverythingClosingKeyboard:(BOOL)closeKeyboard {
    if (!_touchPlay) return;
    [[AKTouchAreas areasForView:self.superview] cancelAll];
    [_walkStick releaseWalking];
    AKTouchReleaseWorldGesture();
    if (closeKeyboard) [self dismissKeyboard];
}
// The line this app has always written when input is taken away. Kept in one place so the
// background path and the resign path cannot drift apart again.
- (void)logInputSuspended {
    // Dictation and system permission panels temporarily take focus. Closing
    // the first responder here cancels dictation before its UI can appear.
    AKLog(@"input suspended (draftFirstResponder=%d)", _keyboardInput.isFirstResponder);
}
- (void)suspendInput:(NSNotification *)notification {
    // Losing focus takes the camera gesture away: the touch that was steering is no longer
    // ours, and leaving it half-open is how the camera used to answer nothing afterwards.
    [self cancelCameraGesture:@"resign"];
    // The same for the controller's touchpad: a click held as focus goes is released, once.
    AKControllerPointerReset(&_controllerPointer, AKEmitTouch, (__bridge void *)self);
    // iPad touch: a call, Control Centre or the app switcher with keys down lets go of every one of them (Task 8).
    // The keyboard stays: Face ID's sheet resigns the app mid-way through a password fill.
    if ([notification.name isEqualToString:UIApplicationWillResignActiveNotification]) [self releaseEverythingClosingKeyboard:NO];
    [self logInputSuspended];
}
- (void)systemKeyboardShown:(NSNotification *)notification {
    NSValue *frame = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
    _systemKeyboardHeight = [frame CGRectValue].size.height;
    _systemKeyboardSeen = YES;
    // With the keys on screen the microphone is one tap away again. The card is redrawn from the
    // Composer's state rather than reset to its placeholder, because in review mode the line
    // above the draft is the state - "Ready to send", or why a send did not happen - and a
    // keyboard arriving is not a reason to lose it.
    if (_systemKeyboardHeight >= AKKeyboardKeysHeight) [self applyComposerState];
    AKLog(@"system keyboard shown draftFirstResponder=%d markedText=%d height=%.0f", _keyboardInput.isFirstResponder, _keyboardInput.markedTextRange != nil, _systemKeyboardHeight);
}
- (void)systemKeyboardHidden:(NSNotification *)notification {
    (void)notification;
    _systemKeyboardHeight = 0;
    AKLog(@"system keyboard hidden draftFirstResponder=%d", _keyboardInput.isFirstResponder);
}
// A game macro or key combination asked for the draft keyboard: open it so the
// iOS keyboard (and its microphone) is one tap away. Never closes an open one.
- (void)keyboardRequestedByGuest:(NSNotification *)notification {
    (void)notification;
    [self cancelTouches];
    AKLog(@"draft keyboard requested from the guest");
    if (self.keyboardVisible) return;
    // iPad touch, the game's password box focused: the keyboard is the Passwords field, as the toolbar's button gives it -
    // never the plain composer, whose Send would type the password as chat.
    if (_textBridge) [self openKeyboardForPlayer:@"the game's keyboard request"];
    else [self becomeFirstResponder];
}
- (void)backgroundInput:(NSNotification *)notification {
    [self cancelCameraGesture:@"background"];
    [self suspendInput:notification];
    // A session that was open when the app went away is cleaned up: capture stops, chat is closed
    // at most once, and the draft is kept for the return. It is never sent.
    [AKChatComposer.shared appDidBackground];
    [self applyComposerState];
    // iPad touch: really going away - everything is let go (the keyboard closes right after, as it always has).
    [self releaseEverythingClosingKeyboard:NO];
    [self dismissKeyboard];
}
- (void)windowResigned:(NSNotification *)notification {
    if (notification.object == self.window) [self suspendInput:notification];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self backgroundInput:nil];
}
- (void)dealloc {
    [_composer removeFromSuperview];
    [_gate removeFromSuperview];
    [_holdTimer invalidate];
    // Nothing to tell at teardown (the delegate may be gone), and nothing left behind either.
    AKTouchCameraReset(&_camera, @"teardown", NULL, NULL);
    AKControllerPointerReset(&_controllerPointer, NULL, NULL);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end
