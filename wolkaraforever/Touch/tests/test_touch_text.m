// The chat keyboard and the password typed by hand (the input path; no password is stored or logged): the bridge's field is a secure
// field iPadOS offers no saved password for, whatever lands in it goes to the game one character at a time
// and is gone from the field at once, and nothing of it is logged or stored. A recorder stands in for the
// host's text path. The game-box case gives the field a window to check that it takes the keyboard.
//
//   test_touch_text
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "InterfaceMode.h"
#import "TouchTextBridge.h"
#include <unistd.h>
#include <math.h>
#include <fcntl.h>
#include <objc/runtime.h>
#include <objc/message.h>

static int checks = 0, failures = 0;
#define CHECK(condition, ...) do { checks++; if (!(condition)) { failures++; \
    fprintf(gReport, "FAIL %s:%d  %s  -- %s\n", __FILE__, __LINE__, #condition, [[NSString alloc] initWithFormat:@__VA_ARGS__].UTF8String); } } while (0)
// Failures are written to a copy of stderr made at start, so the log capture below never swallows them.
static FILE *gReport;

static void SetMode(NSString *mode) {
    if (mode) [NSUserDefaults.standardUserDefaults setObject:mode forKey:AKInterfaceModeDefaultsKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:AKInterfaceModeDefaultsKey];
}

/// What the host's text path was given: "a" for a character, "#51" for a special key.
@interface Recorder : NSObject <AKTouchTextSink>
@property NSMutableArray<NSString *> *sent;
@end
@implementation Recorder
- (instancetype)init { if ((self = [super init])) _sent = [NSMutableArray array]; return self; }
- (void)touchInsertText:(NSString *)text { [self.sent addObject:text]; }
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters { (void)characters; [self.sent addObject:[NSString stringWithFormat:@"#%u", code]]; }
- (NSString *)all { return [self.sent componentsJoinedByString:@" "]; }
@end

static AKTouchTextBridge *NewBridge(Recorder *recorder) {
    AKTouchTextBridge *bridge = [AKTouchTextBridge new];
    bridge.sink = recorder;
    return bridge;
}
/// The fixture clock the secure-input tests move: the debounce is read from it, nothing waits.
static NSTimeInterval gNow;
static void UseClock(AKTouchTextBridge *bridge) { gNow = 100; bridge.clock = ^NSTimeInterval { return gNow; }; }
static void Advance(AKTouchTextBridge *bridge, NSTimeInterval seconds) { gNow += seconds; [bridge tick]; }
/// The game's password box takes focus and keeps it past the debounce.
static void BoxOn(AKTouchTextBridge *bridge) {
    [bridge secureInputChanged:YES appActive:YES];
    Advance(bridge, AKTouchPasswordDebounceSeconds + 0.05);
}
/// A key typed on the keyboard, as UIKit offers it to the field.
static BOOL Type(AKTouchTextBridge *bridge, NSString *text) {
    UITextField *field = bridge.field;
    return [field.delegate textField:field shouldChangeCharactersInRange:NSMakeRange(field.text.length, 0) replacementString:text];
}

/// A device check found: no AutoFill. A Face ID fill ended in "You have been disconnected" on the iPad; the password
/// is typed by hand. The field is still secure (no keyboard learning, nothing kept), but it is a one-time code's, never a
/// password's or a user name's, so iPadOS offers nothing from the Passwords app (a secure field with no content type is
/// still a password field to UIKit).
static void password_field_offers_no_autofill(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    [bridge beginForKind:AKTextKindPassword];
    UITextField *field = bridge.field;
    CHECK(bridge.kind == AKTextKindPassword, "password kind: %ld", (long)bridge.kind);
    CHECK([field.textContentType isEqualToString:UITextContentTypeOneTimeCode], "a one-time code, never a password, so no Passwords offer: %@", field.textContentType);
    CHECK(field.secureTextEntry, "secure entry");
    CHECK(field.autocorrectionType == UITextAutocorrectionTypeNo && field.spellCheckingType == UITextSpellCheckingTypeNo &&
          field.autocapitalizationType == UITextAutocapitalizationTypeNone, "no correction, spelling or capitals");
    CHECK([field.accessibilityLabel isEqualToString:@"Password"], "spoken as %@", field.accessibilityLabel);
    CHECK(!field.userInteractionEnabled, "the field never takes a touch");
    CHECK(field.delegate != nil, "the bridge hears each key");
    // The username kind: a plain field with e-mail keys, not a user name iPadOS would fill either.
    [bridge beginForKind:AKTextKindUsername];
    CHECK(bridge.kind == AKTextKindUsername, "username kind: %ld", (long)bridge.kind);
    CHECK([field.textContentType isEqualToString:UITextContentTypeOneTimeCode], "never a user name: %@", field.textContentType);
    CHECK(!field.secureTextEntry && field.keyboardType == UIKeyboardTypeEmailAddress, "plain, e-mail keys");
    [bridge end];
    CHECK(bridge.kind == AKTextKindNone && !bridge.active, "closed");
}

static NSDictionary *Defaults(void) { return NSUserDefaults.standardUserDefaults.dictionaryRepresentation; }

static void rule9_autofill_forwards_and_forgets(void) {
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    __block NSMutableArray<NSNumber *> *changes = [NSMutableArray array];
    bridge.activeChanged = ^(BOOL active) { [changes addObject:@(active)]; };
    [bridge beginForKind:AKTextKindPassword];
    NSDictionary *before = Defaults();
    // Autofill puts the whole password in the field at once.
    bridge.field.text = @"abc";
    CHECK([recorder.all isEqualToString:@"a b c"], "a, b, c to the game, one at a time, no Return: %@", recorder.all);
    CHECK(bridge.field.text.length == 0, "the field is empty again (%lu)", (unsigned long)bridge.field.text.length);
    CHECK(bridge.kind == AKTextKindNone, "a whole password at once closes the keyboard: kind %ld", (long)bridge.kind);
    CHECK([Defaults() isEqualToDictionary:before], "no defaults key written");
    CHECK(![[Defaults() description] containsString:@"abc"], "the defaults never hold it");
    // The same through UIKit's own insertion (a paste or a suggestion that types): the same outcome.
    [recorder.sent removeAllObjects];
    [bridge beginForKind:AKTextKindPassword];
    CHECK(!Type(bridge, @"xyz"), "UIKit's change is refused (the field keeps nothing)");
    CHECK([recorder.all isEqualToString:@"x y z"] && bridge.field.text.length == 0 && bridge.kind == AKTextKindNone,
          "x, y, z, empty, closed: %@ / kind %ld", recorder.all, (long)bridge.kind);
    // A closed field sends nothing, whatever lands in it.
    [recorder.sent removeAllObjects];
    bridge.field.text = @"late";
    CHECK(recorder.sent.count == 0 && bridge.field.text.length == 0, "closed: nothing sent, nothing kept: %@", recorder.all);
}

static void typed_keys_go_one_at_a_time(void) {
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    [bridge beginForKind:AKTextKindPassword];
    CHECK(!Type(bridge, @"Q"), "the field keeps nothing");
    CHECK(!Type(bridge, @"7"), "the field keeps nothing");
    CHECK([recorder.all isEqualToString:@"Q 7"] && bridge.field.text.length == 0, "each key as it is typed: %@", recorder.all);
    CHECK(bridge.kind == AKTextKindPassword, "typing by hand keeps the keyboard up");
    [bridge.field deleteBackward];
    CHECK([recorder.all isEqualToString:@"Q 7 #51"], "backspace reaches the game's box: %@", recorder.all);
    // The password's Return logs in, as Enter does (a device check: unchanged; the chat's reads Send, the account box's Next).
    CHECK(bridge.field.returnKeyType == UIReturnKeyGo, "the password's Return reads Go: %ld", (long)bridge.field.returnKeyType);
    CHECK(![bridge.field.delegate textFieldShouldReturn:bridge.field], "Return is the bridge's");
    CHECK([recorder.all isEqualToString:@"Q 7 #51 #36"], "the player's Return, once: %@", recorder.all);
    CHECK(bridge.kind == AKTextKindNone, "and the keyboard goes");
}

static void control_characters_never_typed(void) {
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    [bridge beginForKind:AKTextKindPassword];
    bridge.field.text = @"a\rb\n\tc\x7f";
    CHECK([recorder.all isEqualToString:@"a b c"], "no Return, Tab or delete from text: %@", recorder.all);
}

static void chat_kind_opens_the_chat_keyboard(void) {
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    __block int opened = 0;
    bridge.openChat = ^{ opened++; };
    [bridge beginForKind:AKTextKindPassword];
    [bridge beginForKind:AKTextKindChat];
    CHECK(opened == 1, "the controls' chat composer, once: %d", opened);
    CHECK(bridge.kind == AKTextKindNone && !bridge.active, "the password field is closed first");
    CHECK(recorder.sent.count == 0, "nothing sent: %@", recorder.all);
}

static void secure_input_opens_and_closes(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    BoxOn(bridge);
    CHECK(bridge.kind == AKTextKindPassword, "the game's password box: the password kind");
    // Face ID's sheet makes the app inactive, and the game turns secure input off: keep the field.
    [bridge secureInputChanged:NO appActive:NO];
    CHECK(bridge.kind == AKTextKindPassword, "off while inactive is the app resigning, not the box: kept");
    BoxOn(bridge);
    CHECK(bridge.kind == AKTextKindPassword, "on again: still the one field");
    [bridge secureInputChanged:NO appActive:YES];
    CHECK(bridge.kind == AKTextKindNone, "off while active: the box lost focus, closed");
}

///  the add-on's pulses - secure input on for a moment, off again - are never the password box: the
/// password keyboard never flashes, and nobody is told the box has focus.
static void pulse_never_opens_the_password_keyboard(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    __block int activeChanges = 0, confirmed = 0, chats = 0;
    bridge.activeChanged = ^(BOOL active) { (void)active; activeChanges++; };
    bridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) { (void)opening; confirmed++; open(); };
    bridge.openChat = ^{ chats++; };
    // Entering the world: one pulse, 0.15 s.
    [bridge secureInputChanged:YES appActive:YES];
    CHECK(bridge.kind == AKTextKindNone && !bridge.active, "on: nothing yet");
    Advance(bridge, 0.15);
    [bridge secureInputChanged:NO appActive:YES];
    Advance(bridge, 2);
    CHECK(bridge.kind == AKTextKindNone && !bridge.active && activeChanges == 0 && confirmed == 0, "a pulse: no field, no keyboard (%d changes, %d confirmed)", activeChanges, confirmed);
    // Leaving the world: two pulses.
    for (int i = 0; i < 2; i++) {
        [bridge secureInputChanged:YES appActive:YES];
        Advance(bridge, 0.15);
        [bridge secureInputChanged:NO appActive:YES];
        Advance(bridge, 0.15);
    }
    Advance(bridge, 2);
    CHECK(bridge.kind == AKTextKindNone && activeChanges == 0 && confirmed == 0 && chats == 0, "a double pulse: nothing either, and no chat");
    // Heard in the same instant (the main thread was busy): still a pulse.
    [bridge secureInputChanged:YES appActive:YES];
    [bridge secureInputChanged:NO appActive:YES];
    Advance(bridge, 2);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 0, "on and off in the same instant: a pulse");
}

///  a real password box - secure input that stays on - opens the field once the debounce has passed,
/// and not before.
static void long_secure_on_opens_after_the_debounce(void) {
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    UseClock(bridge);
    __block int confirmed = 0; __block BOOL openedFlag = NO;
    bridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) { confirmed++; openedFlag = opening; open(); };
    [bridge secureInputChanged:YES appActive:YES];
    Advance(bridge, 0.3);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 0, "0.3 s in: still waiting");
    Advance(bridge, 0.06);
    CHECK(bridge.kind == AKTextKindPassword && confirmed == 1 && openedFlag, "0.36 s in: the field opens, once (%d)", confirmed);
    Advance(bridge, 5);
    CHECK(confirmed == 1, "and is not told again");
    // The box lets go: closed.
    [bridge secureInputChanged:NO appActive:YES];
    CHECK(bridge.kind == AKTextKindNone, "off: closed");
    // A pulse after a real box is still a pulse.
    [bridge secureInputChanged:YES appActive:YES];
    [bridge secureInputChanged:NO appActive:YES];
    Advance(bridge, 1);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 1, "a pulse after a real box is still a pulse");
}

/// On the app side, a secure input that starts while the player is in the world opens the password field only
/// if it lasts more than 1.5 s - a loading screen can stretch the add-on's pulse well past the 0.35 s debounce. Out of
/// the world (the login screen) the field opens after the usual 0.35 s.
static void in_the_world_a_short_secure_on_never_opens_the_field(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    __block int confirmed = 0, activeChanges = 0;
    bridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) { (void)opening; confirmed++; open(); };
    bridge.activeChanged = ^(BOOL active) { (void)active; activeChanges++; };
    CHECK(!bridge.inWorld, "a new bridge is out of the world");
    bridge.inWorld = YES;
    for (NSNumber *length in @[@0.5, @1.0, @1.4]) {
        [bridge secureInputChanged:YES appActive:YES];
        Advance(bridge, length.doubleValue);
        CHECK(bridge.kind == AKTextKindNone && !bridge.active && confirmed == 0, "in the world, %.1f s in: no field (%d)", length.doubleValue, confirmed);
        [bridge secureInputChanged:NO appActive:YES];
        Advance(bridge, 2);
        CHECK(bridge.kind == AKTextKindNone && !bridge.active && confirmed == 0 && activeChanges == 0,
              "in the world, %.1f s on and off: never opened (%d confirmed, %d changes)", length.doubleValue, confirmed, activeChanges);
    }
    // More than 1.5 s: a real box.
    [bridge secureInputChanged:YES appActive:YES];
    Advance(bridge, 1.4);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 0, "1.4 s: still waiting");
    Advance(bridge, 0.2);
    CHECK(bridge.kind == AKTextKindPassword && confirmed == 1, "1.6 s: the field opens, once (%d)", confirmed);
    [bridge secureInputChanged:NO appActive:YES];
    CHECK(bridge.kind == AKTextKindNone, "its off closes it");
    // Out of the world: the usual debounce.
    bridge.inWorld = NO;
    [bridge secureInputChanged:YES appActive:YES];
    Advance(bridge, 0.5);
    CHECK(bridge.kind == AKTextKindPassword && confirmed == 2, "out of the world, 0.5 s in: the field is open");
    [bridge secureInputChanged:NO appActive:YES];
    // The world is read when the secure input starts: leaving it while one is waiting does not move its limit.
    bridge.inWorld = YES;
    [bridge secureInputChanged:YES appActive:YES];
    bridge.inWorld = NO;
    Advance(bridge, 0.5);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 2, "began in the world: its limit stays 1.5 s");
    Advance(bridge, 1.2);
    CHECK(bridge.kind == AKTextKindPassword && confirmed == 3, "and it opens past it");
}

/// The quiet time after a fill is decided when the box asks, and the box is still reported as focused.
static void quiet_time_still_reports_the_box(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    __block int confirmed = 0, notOpening = 0;
    bridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) { confirmed++; if (!opening) notOpening++; open(); };
    BoxOn(bridge);
    bridge.field.text = @"abc";                                   // a whole password: closed, quiet for 2 s
    [bridge secureInputChanged:NO appActive:NO];                  // Face ID's sheet
    Advance(bridge, 0.5);
    [bridge secureInputChanged:YES appActive:YES];                // back from it
    Advance(bridge, 0.5);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 2 && notOpening == 1, "reported but not opened: kind %ld, confirmed %d, not opening %d",
          (long)bridge.kind, confirmed, notOpening);
}

/// Everything the bridge writes to the log while a password is filled and typed: neither the password nor
/// any part of it is there, and the log is really captured (the bridge says what happened).
static void rule9_no_password_in_logs(void) {
    char path[] = "/tmp/touch-text-log-XXXXXX";
    int fd = mkstemp(path);
    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    dup2(fd, STDERR_FILENO);
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    UseClock(bridge);
    BoxOn(bridge);
    bridge.field.text = @"abc";
    [bridge beginForKind:AKTextKindPassword];
    for (NSString *key in @[@"S", @"w", @"0", @"r", @"d", @"f", @"i", @"s", @"h", @"!", @"7"]) Type(bridge, key);   // typed by hand
    [bridge.field deleteBackward];
    [bridge.field.delegate textFieldShouldReturn:bridge.field];
    [bridge beginForKind:AKTextKindUsername];
    bridge.field.text = @"you@example.com";
    fflush(stderr);
    dup2(saved, STDERR_FILENO);
    close(saved);
    NSString *log = [NSString stringWithContentsOfFile:@(path) encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    close(fd);
    unlink(path);
    CHECK(log.length > 0 && [log containsString:@"password field"], "the bridge's log was captured: %@", log);
    for (NSString *secret in @[@"abc", @"Sw0rd", @"w0rd", @"fish", @"you@example"])
        CHECK(![log containsString:secret], "the log has no %@", secret);
    CHECK([recorder.all isEqualToString:@"a b c S w 0 r d f i s h ! 7 #51 #36 y o u @ e x a m p l e . c o m"], "it all went to the game: %@", recorder.all);
}

static void ipados_unchanged(void) {
    for (NSString *mode in @[@"ipados", @"ios", @"iosduo"]) {
        SetMode(mode);
        CHECK(!AKTouchTextBridgeWanted(), "%@: no bridge, 1.0.10's keyboard", mode);
    }
    SetMode(nil);
    CHECK(!AKTouchTextBridgeWanted(), "no key: no bridge");
    SetMode(@"ipadtouch");
    CHECK(AKTouchTextBridgeWanted(), "iPad touch: the bridge");
}

/// a real field over the game's password box, never in the way of a touch. invisible (alpha 0,
/// not hidden), so UIKit leaves it out of any AutoFill group (it gathers only fields with alpha above 0).
static void field_sits_over_the_box(void) {
    UIView *game = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    [bridge attachToView:game];
    [bridge beginForKind:AKTextKindPassword];
    UITextField *field = bridge.field;
    CHECK(field.superview == game, "in the game's view");
    CHECK(CGSizeEqualToSize(field.bounds.size, CGSizeMake(320, 44)), "320 x 44: %@", NSStringFromCGRect(field.frame));
    CHECK(fabs(field.center.x - 683) < 1 && fabs(field.center.y - 0.621 * 1024) < 1, "centred on the box: %@", NSStringFromCGPoint(field.center));
    CHECK(!field.hidden && field.alpha == 0, "invisible, not hidden: alpha %.2f hidden %d", field.alpha, field.hidden);
    CHECK(CGColorGetAlpha(field.textColor.CGColor) == 0 && CGColorGetAlpha(field.tintColor.CGColor) == 0 &&
          (!field.backgroundColor || CGColorGetAlpha(field.backgroundColor.CGColor) == 0) && field.borderStyle == UITextBorderStyleNone,
          "nothing of it is drawn");
    CHECK([game hitTest:field.center withEvent:nil] == game, "a tap on the box is the game's, not the field's");
    // A new size (rotation, Stage Manager): placed again when it opens next.
    [bridge end];
    game.frame = CGRectMake(0, 0, 1024, 768);
    [bridge beginForKind:AKTextKindPassword];
    CHECK(fabs(field.center.x - 512) < 1 && fabs(field.center.y - 0.621 * 768) < 1, "follows the size: %@", NSStringFromCGPoint(field.center));
    CHECK(field.undoManager == nil, "no undo: nothing typed is kept for it");
}

///  text that reaches the field some other way (a UITextInput insertion that skips the setter
/// and the delegate) is sent and cleared when the field says it changed.
static void other_fill_paths_forward_and_clear(void) {
    void (*plainSetText)(id, SEL, NSString *) = (void (*)(id, SEL, NSString *))class_getMethodImplementation(UITextField.class, @selector(setText:));
    for (int path = 0; path < 2; path++) {
        Recorder *recorder = [Recorder new];
        AKTouchTextBridge *bridge = NewBridge(recorder);
        [bridge beginForKind:AKTextKindPassword];
        // UITextField's own storage, past the bridge's setter: what another insertion path leaves behind.
        plainSetText(bridge.field, @selector(setText:), @"abc");
        if (path == 0) {
            // A bare process has no UIApplication to route a control event; call what is registered for it (the host
            // fixture sends the real event).
            BOOL registered = NO;
            for (id target in bridge.field.allTargets)
                for (NSString *action in [bridge.field actionsForTarget:target forControlEvent:UIControlEventEditingChanged]) {
                    registered = YES;
                    ((void (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(action));
                }
            CHECK(registered, "something listens for editing changed");
        }
        else [NSNotificationCenter.defaultCenter postNotificationName:UITextFieldTextDidChangeNotification object:bridge.field];
        CHECK([recorder.all isEqualToString:@"a b c"], "%s: a, b, c, once: %@", path ? "text did change" : "editing changed", recorder.all);
        CHECK(bridge.field.text.length == 0 && bridge.kind == AKTextKindNone, "%s: empty and closed", path ? "text did change" : "editing changed");
    }
}

///  after a whole password, Face ID's return turns secure input on again; the box is filled, so
/// the field does not come back - for AKTouchFillQuietSeconds, or until the box loses focus (off while active).
static void no_reopen_after_a_fill(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    BoxOn(bridge);
    bridge.field.text = @"abc";
    CHECK(bridge.kind == AKTextKindNone, "filled and closed");
    [bridge secureInputChanged:NO appActive:NO];   // Face ID's sheet
    gNow += 0.6;
    BoxOn(bridge);                                 // back from it, 0.6 s after the fill
    CHECK(bridge.kind == AKTextKindNone, "within the quiet time: still closed");
    [bridge secureInputChanged:NO appActive:NO];
    gNow += 2;
    BoxOn(bridge);                                 // asks again past the quiet time
    CHECK(bridge.kind == AKTextKindPassword, "past the quiet time: the box asks again, the field opens");
    // Filled, then the box loses focus and gets it back (a wrong password, the game's own message): opens at once.
    bridge.field.text = @"abc";
    [bridge secureInputChanged:NO appActive:YES];
    gNow += 0.1;
    BoxOn(bridge);
    CHECK(bridge.kind == AKTextKindPassword, "off while active ends the quiet time");
    // The player's own ask is never quiet.
    bridge.field.text = @"abc";
    [bridge beginForKind:AKTextKindPassword];
    CHECK(bridge.kind == AKTextKindPassword, "Type password right after a fill still opens");
    // Typed by hand and Return: not a fill, no quiet time.
    [bridge end];
    [bridge beginForKind:AKTextKindPassword];
    Type(bridge, @"x");
    [bridge.field.delegate textFieldShouldReturn:bridge.field];
    BoxOn(bridge);
    CHECK(bridge.kind == AKTextKindPassword, "after typing by hand the box may ask again at once");
}

/// Device fix 2: an "off" never settles a waiting "on" by opening the field - the box had focus and has let go, so the
/// field would open only to close again. On the iPad that flash happened inside a resign (Face ID's sheet), and the
/// controls were left believing the box still had focus.
static void an_off_never_opens_a_waiting_on(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    __block int confirmed = 0, activeChanges = 0;
    bridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) { (void)opening; confirmed++; open(); };
    bridge.activeChanged = ^(BOOL active) { (void)active; activeChanges++; };
    for (NSNumber *active in @[@YES, @NO]) {
        [bridge secureInputChanged:YES appActive:YES];
        gNow += 1.7;                                   // the timer has not run (the main thread was busy)
        [bridge secureInputChanged:NO appActive:active.boolValue];
        Advance(bridge, 2);
        CHECK(bridge.kind == AKTextKindNone && confirmed == 0 && activeChanges == 0,
              "a waiting on, then off (app %s): nothing opened (%d confirmed)", active.boolValue ? "active" : "resigning", confirmed);
    }
    // The game asks again once the app is back: that ask opens the field.
    [bridge secureInputChanged:YES appActive:YES];
    Advance(bridge, AKTouchPasswordDebounceSeconds + 0.05);
    CHECK(bridge.kind == AKTextKindPassword && confirmed == 1, "the next on opens it (%d)", confirmed);
}

/// Device fix 2: while the app is away (Face ID's sheet, Control Centre) a waiting "on" stays waiting; the field opens
/// once the app is active and the controls tick.
static void the_field_waits_for_the_app(void) {
    AKTouchTextBridge *bridge = NewBridge([Recorder new]);
    UseClock(bridge);
    __block BOOL appActive = NO;
    __block int confirmed = 0;
    bridge.appIsActive = ^BOOL { return appActive; };
    bridge.secureFocusConfirmed = ^(BOOL opening, void (^open)(void)) { (void)opening; confirmed++; open(); };
    [bridge secureInputChanged:YES appActive:NO];
    Advance(bridge, 2);
    CHECK(bridge.kind == AKTextKindNone && confirmed == 0, "app away: still waiting (%d)", confirmed);
    appActive = YES;
    [bridge tick];
    CHECK(bridge.kind == AKTextKindPassword && confirmed == 1, "app back: the field opens (%d)", confirmed);
    // An off while the app is away keeps the open field: it is the resign, not the box.
    appActive = NO;
    [bridge secureInputChanged:NO appActive:NO];
    CHECK(bridge.kind == AKTextKindPassword, "resign: kept");
    appActive = YES;
    [bridge secureInputChanged:NO appActive:YES];
    CHECK(bridge.kind == AKTextKindNone, "off while active: closed");
}

static void game_box_types_live_and_stays_up(void) {
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    UIViewController *controller = [UIViewController new];
    window.rootViewController = controller;
    [window makeKeyAndVisible];
    [bridge attachToView:controller.view];
    [bridge beginForKind:AKTextKindGameBox];
    UITextField *field = bridge.field;
    CHECK(bridge.kind == AKTextKindGameBox && bridge.active, "K1 live game box takes the keyboard");
    CHECK(!field.secureTextEntry && field.keyboardType == UIKeyboardTypeDefault && field.returnKeyType == UIReturnKeyDone,
          "K1 plain default keyboard with Done");
    CHECK(field.autocorrectionType == UITextAutocorrectionTypeNo && field.spellCheckingType == UITextSpellCheckingTypeNo &&
          field.autocapitalizationType == UITextAutocapitalizationTypeNone && field.textContentType == nil,
          "K1 no correction, spelling, capitals or content type");
    CHECK(field.smartQuotesType == UITextSmartQuotesTypeNo && field.smartDashesType == UITextSmartDashesTypeNo &&
          field.smartInsertDeleteType == UITextSmartInsertDeleteTypeNo, "K1 smart substitutions off");
    CHECK(([@[@"Game text box", @"Champ de texte du jeu", @"Spieltextfeld"] containsObject:field.accessibilityLabel]),
          "K1 localized spoken game-box label: %@", field.accessibilityLabel);
    for (NSString *letter in @[@"o", @"r", @"g"]) {
        CHECK(!Type(bridge, letter), "K2 each change is consumed");
        CHECK(field.text.length == 0 && bridge.kind == AKTextKindGameBox, "K2 empty field stays live");
    }
    CHECK([recorder.all isEqualToString:@"o r g"], "K2 ordered keys, no F12 or Return: %@", recorder.all);
    CHECK(!Type(bridge, @"abc") && [recorder.all isEqualToString:@"o r g a b c"] &&
          bridge.kind == AKTextKindGameBox && field.text.length == 0, "K3 multi-character input stays live: %@", recorder.all);
    [field deleteBackward];
    CHECK([recorder.all isEqualToString:@"o r g a b c #51"], "K4 delete is key 51: %@", recorder.all);
    CHECK(![field.delegate textFieldShouldReturn:field], "K5 Done handled by bridge");
    CHECK([recorder.all isEqualToString:@"o r g a b c #51 #36"] && bridge.kind == AKTextKindNone && !bridge.active,
          "K5 Return once then closed: %@", recorder.all);
}

static void game_box_log_never_names_input(void) {
    char path[] = "/tmp/touch-gamebox-log-XXXXXX";
    int fd = mkstemp(path);
    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    dup2(fd, STDERR_FILENO);
    Recorder *recorder = [Recorder new];
    AKTouchTextBridge *bridge = NewBridge(recorder);
    [bridge beginForKind:AKTextKindGameBox];
    Type(bridge, @"orgSecret987");
    [bridge end];
    fflush(stderr);
    dup2(saved, STDERR_FILENO); close(saved);
    NSString *log = [NSString stringWithContentsOfFile:@(path) encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    close(fd); unlink(path);
    CHECK([log containsString:@"game box field up"] && [log containsString:@"closed"], "K15 state-only log: %@", log);
    CHECK(![log containsString:@"orgSecret987"] && ![log containsString:@"12"], "K15 neither text nor its length: %@", log);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        gReport = fdopen(dup(STDERR_FILENO), "w");
        setvbuf(gReport, NULL, _IONBF, 0);
        id savedMode = [NSUserDefaults.standardUserDefaults objectForKey:AKInterfaceModeDefaultsKey];
        SetMode(@"ipadtouch");
        void (*tests[])(void) = {password_field_offers_no_autofill, rule9_autofill_forwards_and_forgets, typed_keys_go_one_at_a_time,
            control_characters_never_typed, chat_kind_opens_the_chat_keyboard, secure_input_opens_and_closes, rule9_no_password_in_logs,
            ipados_unchanged, field_sits_over_the_box, other_fill_paths_forward_and_clear, no_reopen_after_a_fill,
            pulse_never_opens_the_password_keyboard, long_secure_on_opens_after_the_debounce, quiet_time_still_reports_the_box,
            in_the_world_a_short_secure_on_never_opens_the_field, an_off_never_opens_a_waiting_on, the_field_waits_for_the_app, game_box_types_live_and_stays_up, game_box_log_never_names_input};
        const char *names[] = {"password_field_offers_no_autofill", "rule9_autofill_forwards_and_forgets", "typed_keys_go_one_at_a_time",
            "control_characters_never_typed", "chat_kind_opens_the_chat_keyboard", "secure_input_opens_and_closes", "rule9_no_password_in_logs",
            "ipados_unchanged", "field_sits_over_the_box", "other_fill_paths_forward_and_clear", "no_reopen_after_a_fill",
            "pulse_never_opens_the_password_keyboard", "long_secure_on_opens_after_the_debounce", "quiet_time_still_reports_the_box",
            "in_the_world_a_short_secure_on_never_opens_the_field", "an_off_never_opens_a_waiting_on", "the_field_waits_for_the_app", "game_box_types_live_and_stays_up", "game_box_log_never_names_input"};
        for (size_t i = 0; i < sizeof tests / sizeof *tests; i++) {
            int before = failures;
            SetMode(@"ipadtouch");
            tests[i]();
            printf("%s %s\n", failures == before ? "PASS" : "FAIL", names[i]);
        }
        if (savedMode) [NSUserDefaults.standardUserDefaults setObject:savedMode forKey:AKInterfaceModeDefaultsKey];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:AKInterfaceModeDefaultsKey];
        printf("TOUCH_TEXT_%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
        return failures ? 1 : 0;
    }
}
