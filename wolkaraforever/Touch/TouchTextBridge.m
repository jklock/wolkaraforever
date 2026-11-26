#import "TouchTextBridge.h"
#import "AKSupport.h"
#import "AKHostLocalization.h"
#import "InterfaceMode.h"

BOOL AKTouchTextBridgeWanted(void) { return AKInterfaceModeIsTouchPlay(); }

const CGPoint AKTouchPasswordBoxCentre = {0.5, 0.621};
const CGSize AKTouchPasswordFieldSize = {320, 44};
const CGFloat AKTouchPasswordSlideFraction = 0.139;
const NSTimeInterval AKTouchFillQuietSeconds = 2;
const NSTimeInterval AKTouchPasswordDebounceSeconds = 0.35;
const NSTimeInterval AKTouchPasswordInWorldDebounceSeconds = 1.5;

@class AKTouchTextBridge;

/// The field that takes the keyboard. It never keeps text: whatever UIKit puts in it is handed to the
/// bridge and the field is emptied in the same call.
@interface AKTouchSecretField : UITextField
@property (nonatomic, weak) AKTouchTextBridge *bridge;
- (NSString *)takeText;
@end

@interface AKTouchTextBridge () <UITextFieldDelegate>
- (void)arrived:(NSString *)text whole:(BOOL)whole;
- (void)fieldChanged;
- (void)backspace;
@end

@implementation AKTouchSecretField
// Autofill (and any other setter) puts the whole text in at once: send it and forget it.
- (void)setText:(NSString *)text {
    [super setText:@""];
    if (text.length) [self.bridge arrived:text whole:YES];
}
- (void)setAttributedText:(NSAttributedString *)text {
    [super setAttributedText:[NSAttributedString new]];
    if (text.length) [self.bridge arrived:text.string whole:YES];
}
// The field is always empty, so a backspace is the game's: its box holds the text.
- (void)deleteBackward { [self.bridge backspace]; }
// It never takes a touch (user interaction is off), yet it takes the keyboard when the bridge asks: UITextField
// refuses focus without user interaction unless it is told it can.
- (BOOL)canBecomeFirstResponder { return self.bridge.kind != AKTextKindNone; }
// What another insertion path left in the field, taken out of it (the field is empty afterwards).
- (NSString *)takeText {
    NSString *text = super.text;
    if (text.length) [super setText:@""];
    return text;
}
// No undo: nothing typed is kept for it.
- (NSUndoManager *)undoManager { return nil; }
// Nothing to copy, cut or look up: the text is never here.
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender { (void)action; (void)sender; return NO; }
@end

@implementation AKTouchTextBridge {
    AKTouchSecretField *_field;
    AKTextKind _kind;
    BOOL _wasActive;
    // After a whole password: until then, the game's "secure input on" does not open the field (I4).
    NSTimeInterval _quietUntil;
    // The game's "secure input on" is waiting out the debounce: a pulse of the add-on's goes off first.
    BOOL _pendingOn;
    BOOL _pendingQuiet;
    NSTimeInterval _pendingSince;
    NSTimeInterval _pendingWait;    // this "on" began in the world: it waits longer
}

- (instancetype)init {
    if ((self = [super init])) {
        self.clock = nil;
        AKTouchSecretField *field = [[AKTouchSecretField alloc] initWithFrame:(CGRect){CGPointZero, AKTouchPasswordFieldSize}];
        field.bridge = self;
        field.delegate = self;
        // A field where the game's box is, of which nothing is drawn (clear text, caret and background; the
        // game draws the box and the dots).  (no AutoFill; the password is typed by hand): invisible, because
        // UIKit gathers only fields with alpha above 0 into an AutoFill group, but not hidden, because a hidden view
        // cannot take the keyboard.
        field.alpha = 0;
        field.borderStyle = UITextBorderStyleNone;
        field.textColor = UIColor.clearColor;
        field.tintColor = UIColor.clearColor;
        field.backgroundColor = UIColor.clearColor;
        field.userInteractionEnabled = NO;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
        field.smartQuotesType = UITextSmartQuotesTypeNo;
        field.smartDashesType = UITextSmartDashesTypeNo;
        field.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
        field.accessibilityIdentifier = @"wolkaraforever.keyboard.secret";
        _field = field;
        // Any other way text reaches the field (a UITextInput insertion past the setter and the delegate) says so
        // with one of these: send it and empty the field then too (I3).
        [field addTarget:self action:@selector(fieldChanged) forControlEvents:UIControlEventEditingChanged];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldChanged)
                                                   name:UITextFieldTextDidChangeNotification object:field];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(responderChanged:)
                                                   name:UITextFieldTextDidBeginEditingNotification object:field];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(responderChanged:)
                                                   name:UITextFieldTextDidEndEditingNotification object:field];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

@synthesize clock = _clock, inWorld = _inWorld;
- (void)setClock:(NSTimeInterval (^)(void))clock {
    _clock = clock ?: ^NSTimeInterval { return NSProcessInfo.processInfo.systemUptime; };
}
- (UITextField *)field { return _field; }
- (AKTextKind)kind { return _kind; }
- (BOOL)active { return _field.isFirstResponder; }

- (void)attachToView:(UIView *)view {
    if (_field.superview != view) {
        [_field removeFromSuperview];
        [view addSubview:_field];
    }
    [self placeField];
}
/// Centred on the login password box at the view's current size.
- (void)placeField {
    UIView *view = _field.superview;
    if (!view) return;
    CGSize size = view.bounds.size;
    _field.bounds = (CGRect){CGPointZero, AKTouchPasswordFieldSize};
    _field.center = CGPointMake(round(size.width * AKTouchPasswordBoxCentre.x), round(size.height * AKTouchPasswordBoxCentre.y));
}

/// The field gave up or took the keyboard on its own (another view took it): say so once per change.
- (void)responderChanged:(NSNotification *)note {
    (void)note;
    [self reportActive];
}
/// Only `end` closes the field. When the field loses the keyboard on its own it keeps its kind (device fix 2): iPadOS's
/// Passwords sheet and Face ID take the keyboard in the middle of an AutoFill, and when the player has picked the
/// password UIKit hands it to the autofill group's password field, asking that field to take the keyboard back first
/// (-[_UIKeyboardStateManager processPayloadInfo:]). A field that had dropped its kind refused (`canBecomeFirstResponder`)
/// and dropped the text (`arrived:whole:`), so the fill went nowhere.
- (void)reportActive {
    BOOL active = self.active;
    if (active == _wasActive) return;
    _wasActive = active;
    if (!active && _kind != AKTextKindNone) {
        if (_kind == AKTextKindGameBox) AKLog(@"keyboard: the game box field lost the keyboard on its own");
        else AKLog(@"keyboard: the %@ field lost the keyboard on its own; it stays ready for AutoFill", _kind == AKTextKindPassword ? @"password" : @"user name");
    }
    if (self.activeChanged) self.activeChanged(active);
}

- (void)setUpFor:(AKTextKind)kind {
    BOOL password = kind == AKTextKindPassword;
    // With no AutoFill and manual typing, a one-time code's field, never a password's or a user name's. A secure field
    // with no content type is still a password field to UIKit (in the simulator its own credential completion typed into
    // it); a one-time code's takes no saved password. Secure entry stays: the keyboard learns nothing typed here.
    _field.textContentType = kind == AKTextKindGameBox ? nil : UITextContentTypeOneTimeCode;
    _field.secureTextEntry = password;
    _field.keyboardType = password || kind == AKTextKindGameBox ? UIKeyboardTypeDefault : UIKeyboardTypeEmailAddress;
    _field.returnKeyType = kind == AKTextKindGameBox ? UIReturnKeyDone : UIReturnKeyGo;
    _field.accessibilityLabel = AKHostLocalized(password ? @"touch.keyboard.password" : kind == AKTextKindGameBox ? @"touch.keyboard.gamebox" : @"touch.keyboard.username");
}

- (void)beginForKind:(AKTextKind)kind {
    switch (kind) {
        case AKTextKindNone:
            [self end];
            return;
        case AKTextKindChat:
            // The composer takes the keyboard from the field directly (the field gives it up), so it never drops.
            if (self.openChat) self.openChat();
            if (_kind != AKTextKindNone || self.active) [self end];
            return;
        case AKTextKindUsername:
        case AKTextKindPassword:
        case AKTextKindGameBox:
            break;
    }
    // The player's own ask is never quiet.
    _quietUntil = 0;
    [self openKind:kind];
}
- (void)openKind:(AKTextKind)kind {
    if (_kind == kind && self.active) return;
    // A field that has the keyboard does not take new traits until it gives it up and takes it again.
    if (self.active) [_field resignFirstResponder];
    [self setUpFor:kind];
    [self placeField];
    _kind = kind;
    BOOL took = [_field becomeFirstResponder];
    AKLog(@"keyboard: %@ field up (%@)", kind == AKTextKindPassword ? @"password" : kind == AKTextKindGameBox ? @"game box" : @"user name",
          took ? @"it has the keyboard" : @"not in a window yet");
    [self reportActive];
}

- (void)end {
    if (_kind == AKTextKindNone && !self.active) return;
    AKTextKind was = _kind;
    _kind = AKTextKindNone;
    [_field resignFirstResponder];
    if (was != AKTextKindNone) AKLog(@"keyboard: %@ field closed", was == AKTextKindPassword ? @"password" : was == AKTextKindGameBox ? @"game box" : @"user name");
    [self reportActive];
}

- (void)secureInputChanged:(BOOL)enabled appActive:(BOOL)appActive {
    if (enabled) {
        [self tick];    // an "on" that has waited long enough is settled before anything new is heard
        if (_kind == AKTextKindPassword || _pendingOn) return;
        // Wait out the debounce: the add-on's pulses are on and off again before it ends, and are not the box. Just
        // filled: this is the game coming back from Face ID's sheet and the box already holds the password - noted
        // now, so the wait cannot move it out of the quiet time.
        _pendingOn = YES;
        _pendingQuiet = self.clock() < _quietUntil;
        _pendingSince = self.clock();
        // Read when the secure input starts, as the world signal reads it.
        _pendingWait = _inWorld ? AKTouchPasswordInWorldDebounceSeconds : AKTouchPasswordDebounceSeconds;
        __weak AKTouchTextBridge *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((_pendingWait + 0.02) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf tick]; });
        return;
    }
    // An "on" still waiting is forgotten, never settled here: off before the debounce ended is a pulse, never the box;
    // after it, the box had focus and has let go (opening the field now would only close it again). Off while the app
    // is resigning forgets it too: the game turns secure input off on every resign and on again on return, and that
    // "on" is the ask to answer, with the app active (device fix 2: a field opened during the resign, then closed).
    _pendingOn = NO;
    // Off while the app is not active is the app resigning (Face ID's sheet does it mid-autofill), not the box.
    if (!appActive) return;
    // The box really lost focus: the next time it asks, it is a new ask.
    _quietUntil = 0;
    if (_kind != AKTextKindNone) [self end];
}

- (void)tick {
    if (!_pendingOn || self.clock() - _pendingSince < _pendingWait) return;
    // Not while the app is away (Face ID's sheet, Control Centre): the field is opened once it is back, when the controls
    // tick again (device fix 2).
    if (self.appIsActive && !self.appIsActive()) return;
    _pendingOn = NO;
    BOOL opening = !_pendingQuiet;
    if (!opening) AKLog(@"keyboard: the password box asked again just after a fill; not reopening");
    void (^open)(void) = ^{ if (opening) [self openKind:AKTextKindPassword]; };
    if (self.secureFocusConfirmed) self.secureFocusConfirmed(opening, open);
    else open();
}

#pragma mark What lands in the field

/// `text` landed in the field: each character to the game, in order, through the host's text path. Control
/// characters (Return, Tab, delete) are not text: only the Return key sends Return. `whole`: it came all at
/// once (autofill, paste), so the box is filled and the keyboard goes (mockup 28: the player taps Log In).
/// Nothing about the text is logged.
- (void)arrived:(NSString *)text whole:(BOOL)whole {
    if (_kind != AKTextKindUsername && _kind != AKTextKindPassword && _kind != AKTextKindGameBox) return;
    id<AKTouchTextSink> sink = self.sink;
    NSCharacterSet *control = NSCharacterSet.controlCharacterSet;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
        (void)range; (void)enclosing; (void)stop;
        if ([character rangeOfCharacterFromSet:control].location != NSNotFound) return;
        [sink touchInsertText:character];
    }];
    if (whole && _kind != AKTextKindGameBox) {
        _quietUntil = self.clock() + AKTouchFillQuietSeconds;
        AKLog(@"keyboard: the %@ went to the game at once; closing", _kind == AKTextKindPassword ? @"password" : @"user name");
        [self end];
    }
}
- (void)fieldChanged {
    NSString *text = [_field takeText];
    if (!text.length) return;
    __block NSUInteger characters = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *c, NSRange r, NSRange e, BOOL *stop) { (void)c; (void)r; (void)e; (void)stop; characters++; }];
    [self arrived:text whole:characters > 1];
}
- (void)backspace {
    if (_kind != AKTextKindUsername && _kind != AKTextKindPassword && _kind != AKTextKindGameBox) return;
    [self.sink touchSpecialKey:51 characters:@"\x7f"];
}

#pragma mark UITextFieldDelegate

// Every key UIKit types: sent, and refused, so the field stays empty. More than one character at once is a
// suggestion or a paste: the whole text, as autofill.
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    (void)textField; (void)range;
    if (string.length) {
        __block NSUInteger characters = 0;
        [string enumerateSubstringsInRange:NSMakeRange(0, string.length) options:NSStringEnumerationByComposedCharacterSequences
                                usingBlock:^(NSString *s, NSRange r, NSRange e, BOOL *stop) { (void)s; (void)r; (void)e; (void)stop; characters++; }];
        [self arrived:string whole:characters > 1];
    }
    return NO;
}
// The player's own Return: sent once, and the keyboard goes.
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    (void)textField;
    if (_kind != AKTextKindUsername && _kind != AKTextKindPassword && _kind != AKTextKindGameBox) return NO;
    [self.sink touchSpecialKey:36 characters:@"\r"];
    [self end];
    return NO;
}
@end
