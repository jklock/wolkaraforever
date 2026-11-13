// Original UIKit/AppKit fixture for manual touch/keyboard testing. No guest.
#import "AppKit.h"
#import "AKPerformanceOverlay.h"
#import "AKTouchEventPump.h"
#import "TouchControls.h"
#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "AKHostLocalization.h"
#include <assert.h>

// The keys the layer supplies when iPadOS has no software keyboard to give. The
// controls keep it private; the fixture asks for it the way the controls do.
@interface AKTouchControls (LayerKeyboardFixture)
- (void)showLayerKeyboard;
@end

@interface AKInputFixtureView : NSView
@property CATextLayer *heading, *instructions, *result;
@property NSMutableString *text;
@property NSString *lastAction;
@property NSRange selection;
@property NSUInteger replacements;
// The last key event this guest view was given, so a test can say whether the adapter posted
// one at all. Nil is the answer that matters for a key the user has taken.
@property (nonatomic, strong, nullable) NSEvent *lastKeyEvent;
// Every key this guest view was given, in order, so a test can read a whole sequence.
@property NSMutableArray<NSNumber *> *keyCodes;
@end
@implementation AKInputFixtureView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [UIColor colorWithRed:0.06 green:0.10 blue:0.16 alpha:1].CGColor;
        _text = [NSMutableString new];
        _lastAction = @"Ready";
        for (NSString *key in @[@"heading", @"instructions", @"result"]) {
            CATextLayer *label = [CATextLayer new];
            label.contentsScale = UIScreen.mainScreen.scale;
            label.foregroundColor = UIColor.whiteColor.CGColor;
            label.wrapped = YES;
            [self.layer addSublayer:label];
            [self setValue:label forKey:key];
        }
        _heading.fontSize = 24; _instructions.fontSize = 15; _result.fontSize = 18;
        _heading.string = @"Tolkara · Touch input fixture";
        _instructions.string = @"Slide: move • Tap: left click • Two fingers: scroll / right click\nThree-finger tap: middle click • Hold then slide: drag\nUse the keyboard button at the top center. This is an original test screen.";
        [self setFrame:frame];
    }
    return self;
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    CGFloat width = MAX(100, frame.size.width - 96);
    _heading.frame = CGRectMake(48, 32, width, 32);
    _instructions.frame = CGRectMake(48, 76, width, 78);
    _result.frame = CGRectMake(48, 170, width, 100);
    [self refresh];
}
- (void)refresh {
    self.result.string = [NSString stringWithFormat:@"%@\nText: %@", self.lastAction, self.text];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    self.lastKeyEvent = event;
    if (!self.keyCodes) self.keyCodes = [NSMutableArray new];
    [self.keyCodes addObject:@(event.keyCode)];
    if (event.keyCode == 0 && (event.modifierFlags & NSEventModifierFlagCommand)) {
        self.selection = NSMakeRange(0, self.text.length);
        self.replacements++;
        return;
    }
    NSRange range = self.selection;
    assert(NSMaxRange(range) <= self.text.length);
    if (event.keyCode == 51) {
        if (!range.length && range.location) range = [self.text rangeOfComposedCharacterSequenceAtIndex:range.location - 1];
        [self.text deleteCharactersInRange:range];
        self.selection = NSMakeRange(range.location, 0);
    } else if (event.keyCode == 53) {
        [self.text setString:@""]; self.selection = NSMakeRange(0, 0);
    } else if (event.characters.length) {
        [self.text replaceCharactersInRange:range withString:event.characters];
        self.selection = NSMakeRange(range.location + event.characters.length, 0);
    }
    self.lastAction = @"Keyboard input received";
    [self refresh];
}
- (void)mouseMoved:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Pointer %.0f, %.0f", event.locationInWindow.x, event.locationInWindow.y];
    [self refresh];
}
- (void)mouseDown:(NSEvent *)event { self.lastAction = event.clickCount == 2 ? @"Double click" : @"Left click / hold"; [self refresh]; }
- (void)rightMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Right click / hold"; [self refresh]; }
- (void)otherMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Middle click"; [self refresh]; }
- (void)mouseDragged:(NSEvent *)event { (void)event; self.lastAction = @"Left drag"; [self refresh]; }
- (void)rightMouseDragged:(NSEvent *)event { (void)event; self.lastAction = @"Right drag"; [self refresh]; }
- (void)scrollWheel:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Scroll %.0f, %.0f", event.deltaX, event.deltaY];
    [self refresh];
}
@end

static void AKDrainFixtureEvents(void) {
    // Let UIKit finish its asynchronous text transaction before observing the
    // translated events. The fixture is entered from a timer, like the guest.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
}

static UIView *AKFindInputView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqual:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = AKFindInputView(child, identifier);
        if (found) return found;
    }
    return nil;
}

#pragma mark - Faking a key press at the adapter's door

// UIKey and UIPress cannot be constructed, so they are subclassed and the accessors
// `postKeys:` reads are overridden: keyCode, characters, modifierFlags and timestamp. This
// is the only way to drive the one place the adapter posts guest key events, and a contract
// nothing exercises is a contract that is not tested - the Replace assertion above sat
// failing for a day for exactly that reason.
@interface AKFixtureKey : UIKey
@property (nonatomic) UIKeyboardHIDUsage usage;
@end
@implementation AKFixtureKey
- (UIKeyboardHIDUsage)keyCode { return self.usage; }
- (UIKeyModifierFlags)modifierFlags { return 0; }
// "a" for usage 0x04, "b" for 0x05, and so on: enough for the guest view to insert.
- (NSString *)characters { return [NSString stringWithFormat:@"%c", (char)('a' + (self.usage - 0x04))]; }
- (NSString *)charactersIgnoringModifiers { return self.characters; }
@end

@interface AKFixturePress : UIPress
@property (nonatomic, strong) AKFixtureKey *fakeKey;
@end
@implementation AKFixturePress
- (UIKey *)key { return self.fakeKey; }
- (NSTimeInterval)timestamp { return NSProcessInfo.processInfo.systemUptime; }
@end

static AKFixturePress *AKPressForUsage(unsigned short usage) {
    AKFixturePress *press = [AKFixturePress new];
    AKFixtureKey *key = [AKFixtureKey new];
    key.usage = usage;
    press.fakeKey = key;
    return press;
}

// Press a key the way UIKit would, then let the event queue deliver it, and answer with the
// event the guest's own view received - nil when the adapter posted nothing.
static NSEvent *AKFixturePressKey(UIView *host, AKInputFixtureView *guest, unsigned short usage) {
    guest.lastKeyEvent = nil;
    [host pressesBegan:[NSSet setWithObject:AKPressForUsage(usage)] withEvent:nil];
    AKDrainFixtureEvents();
    return guest.lastKeyEvent;
}

// The stand-in for the shell: publish which usages the user has taken, exactly as main.m
// does, and let the adapter's own observer decide. The notification is dispatched to the main
// queue, so it is drained before returning.
static void AKFixtureOwnsUsages(NSArray<NSNumber *> *usages) {
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchOwnedKeyUsagesDidChangeNotification
                                                     object:nil
                                                   userInfo:@{AKTouchOwnedKeyUsagesKey: [NSSet setWithArray:usages]}];
    AKDrainFixtureEvents();
}

static void AKFixtureInputSource(void *context) {
    (void)context;
    NSEvent *event = [NSEvent new]; event.type = NSEventTypeMouseMoved;
    [NSApp postEvent:event atStart:NO];
}

@interface AKInputFixtureScene : UIResponder <UIWindowSceneDelegate>
@property NSWindow *guest;
@property NSTimer *pump;
@end
@implementation AKInputFixtureScene
- (void)checkMouseTrackingProgress {
    id<AKTouchControlsDelegate> host=[self.guest valueForKey:@"_host"];
    for (unsigned button=0;button<3;button++) {
        for (unsigned traffic=0;traffic<3;traffic++) {
            for (unsigned cycle=0;cycle<2;cycle++) {
                [host touchButton:button pressed:YES];
                AKDrainFixtureEvents();
                __block BOOL trackingFired=NO, defaultFired=NO;
                NSTimer *tracking=[NSTimer timerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
                    (void)timer; trackingFired=YES;
                }];
                [NSRunLoop.mainRunLoop addTimer:tracking forMode:UITrackingRunLoopMode];
                NSTimer *ordinary=[NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
                    (void)timer; defaultFired=YES;
                }];
                NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+1;
                while (!(trackingFired && defaultFired) && NSProcessInfo.processInfo.systemUptime<deadline) {
                    if (traffic==1) AKFixtureInputSource(NULL);
                    NSDate *until=traffic==2 ? [NSDate dateWithTimeIntervalSinceNow:0.03] : NSDate.distantPast;
                    [NSApp nextEventMatchingMask:UINT64_MAX untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
                }
                [tracking invalidate]; [ordinary invalidate];
                NSLog(@"Mouse tracking: button=%u traffic=%u cycle=%u tracking=%d default=%d",
                      button,traffic,cycle,trackingFired,defaultFired);
                assert(trackingFired && defaultFired);
                [host touchButton:button pressed:NO];
                AKDrainFixtureEvents();
            }
        }
    }
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: repeated held-button drags service default and tracking events before release");
    exit(EXIT_SUCCESS);
}
- (void)checkTrackingUIProgress {    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKTouchGamepad *gamepad = [controls valueForKey:@"_gamepad"];
    assert(gamepad);
    assert(!gamepad.enabled);
    AKDrainFixtureEvents();
    for (NSUInteger surface = 0; surface < 2; surface++) {
        if (surface == 0) [controls toggleKeyboard]; else [gamepad toggleSettings];
        __block BOOL trackingFired = NO, defaultFired = NO;
        NSTimer *tracking = [NSTimer timerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
            (void)timer; trackingFired = YES;
        }];
        [NSRunLoop.mainRunLoop addTimer:tracking forMode:UITrackingRunLoopMode];
        NSTimer *ordinary = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
            (void)timer; defaultFired = YES;
        }];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 1;
        while (!(trackingFired && defaultFired) && NSProcessInfo.processInfo.systemUptime < deadline) {
            AKFixtureInputSource(NULL);
            [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
        }
        [tracking invalidate]; [ordinary invalidate];
        NSLog(@"Native tracking progress: surface=%lu tracking=%d default=%d", (unsigned long)surface, trackingFired, defaultFired);
        assert(trackingFired && defaultFired);
        if (surface == 0) [controls dismissKeyboard]; else [gamepad toggleSettings];
    }
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: UIKit tracking and default work progress while native editor/settings are open");
    exit(EXIT_SUCCESS);
}
- (void)checkNativeUIProgress {
    UIView *host = [self.guest valueForKey:@"_host"];
    CFRunLoopSourceContext context = {0}; context.perform = AKFixtureInputSource;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    // Empty nonblocking polls, source-driven blocking polls, a permanently
    // occupied queue, repeated peeks, and NSApplication's own run loop must
    // all let native UI make progress.
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    for (NSUInteger traffic = 0; traffic < 5; traffic++) {
        UIView *probe = [[UIView alloc] initWithFrame:CGRectMake(60, 260, 24, 24)];
        probe.backgroundColor = UIColor.systemGreenColor;
        [host addSubview:probe];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(60, 300, 220, 32)];
        [host addSubview:slider];
        // Mode 2 keeps the queue permanently ready, so it needs a surface for the pump to
        // service; see the loop below.
        if (traffic == 2) { [controls toggleKeyboard]; [host layoutIfNeeded]; }
        __block BOOL completed = NO, deferred = NO, timerFired = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ deferred = YES; });
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *fired) {
            (void)fired; slider.value = 0.75; timerFired = YES;
        }];
        // No explicit flush in the fixture: it previously hid presentation
        // problems by forcing a Core Animation commit after every key/motion.
        [UIView animateWithDuration:0.05 animations:^{
            probe.center = CGPointMake(200, 272);
        } completion:^(BOOL finished) { completed = finished; }];
        NSEvent *peeked = nil;
        if (traffic == 3) {
            AKFixtureInputSource(NULL);
            peeked = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
                inMode:NSDefaultRunLoopMode dequeue:NO];
            assert(peeked);
        }
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 2;
        if (traffic == 4) {
            [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *stop) {
                (void)stop; [NSApp stop:nil];
            }];
            [NSApp run];
        }
        while (traffic != 4 && !(completed && deferred && timerFired) && NSProcessInfo.processInfo.systemUptime < deadline) {
            @autoreleasepool {
                if (traffic == 2) {
                    // The guest's own loop calls the pump on every turn, and the pump is what
                    // keeps UIKit moving under a permanently ready queue - but only while a
                    // native surface is open or a button is held, because otherwise it does
                    // nothing on purpose. This mode is that state: the queue is always ready
                    // and the keyboard is open, so the pump has something to service.
                    AKFixtureInputSource(NULL);
                    AKPumpTouchEvents(YES);
                }
                if (traffic == 1) CFRunLoopSourceSignal(source);
                NSEvent *event = [NSApp nextEventMatchingMask:UINT64_MAX
                    untilDate:traffic == 1 ? [NSDate dateWithTimeIntervalSinceNow:0.01] : NSDate.distantPast
                    inMode:NSDefaultRunLoopMode dequeue:YES];
                // A peek that is never taken is not progress. The event is still there, and
                // one dequeue is what takes it - after that the loop runs normally.
                if (peeked) { assert(event == peeked); peeked = nil; }
            }
        }
        [timer invalidate];
        NSLog(@"Native UI progress: traffic=%lu animation=%d deferred=%d timer=%d",
            (unsigned long)traffic, completed, deferred, timerFired);
        assert(completed && deferred && timerFired && slider.value == 0.75);
        if (traffic == 2) [controls dismissKeyboard];
        assert(peeked == nil);
        [probe removeFromSuperview]; [slider removeFromSuperview];
    }
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(source);
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: native UI presentation, deferred work, slider updates and queue peeking inside guest loop");
    exit(EXIT_SUCCESS);
}

#pragma mark - Live QA

// Three states to look at, held long enough for a screenshot from outside the process: the card
// with nothing typed, the card with a message ready to send, and the card reporting a refused
// send. Runs only with `--composer-qa`; it ends by itself so a capture run cannot hang.
- (void)checkChatComposerQA {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKInputFixtureView *fixture = (AKInputFixtureView *)self.guest.contentView;
    AKChatComposer *composer = AKChatComposer.shared;
    // The capture seam the shell would otherwise fill: this run is about what the card looks
    // like, not about a recogniser.
    composer.testOnlyCapture = ^(BOOL start, NSUInteger generation) { (void)start; (void)generation; };
    [self.guest makeFirstResponder:fixture];
    [fixture.text setString:@""];
    [controls toggleKeyboard];
    [host layoutIfNeeded];
    NSLog(@"CHAT_COMPOSER_QA idle");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // A session with the result the recogniser would deliver: the state after dictation.
        [controls openChatComposerFromSource:AKChatComposerSourceController];
        [composer speechFinished:@"Meet me at the inn when the sun comes up."
                      generation:composer.generation];
        [host layoutIfNeeded];
        NSLog(@"CHAT_COMPOSER_QA ready");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            // A password field has the keyboard, so the chat cannot be opened: the card says so.
            // The session above is ended first, because that is what a player does: a Composer
            // already on screen is not re-opened by another press.
            [AKChatComposer.shared cancel];
            [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification"
                                                             object:nil userInfo:@{@"enabled": @YES}];
            [controls openChatComposerFromSource:AKChatComposerSourceController];
            [host layoutIfNeeded];
            NSLog(@"CHAT_COMPOSER_QA error");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification"
                                                                 object:nil userInfo:@{@"enabled": @NO}];
                [AKChatComposer.shared cancel];
                NSLog(@"CHAT_COMPOSER_QA done");
                exit(EXIT_SUCCESS);
            });
        });
    });
}

#pragma mark - The Composer card, with a real guest behind it

// The state machine has its own fixture (tests/test_chat_composer_app.m); what only this file can
// prove is that the card, driven through its real buttons, puts the right keys into the guest:
// the text once, Return once, Escape once - and nothing at all on Cancel.
- (void)checkChatComposerProgress {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKInputFixtureView *fixture = (AKInputFixtureView *)self.guest.contentView;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    // Review mode, the way a fresh installation gets it. The argument domain is what the controls
    // read first, so it is set there as well as in the database.
    {
        NSMutableDictionary *modes = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        modes[@"AKChatDeliveryMode"] = @"review";
        [defaults setVolatileDomain:modes forName:NSArgumentDomain];
    }
    [defaults setObject:@"review" forKey:@"AKChatDeliveryMode"];
    [defaults setBool:YES forKey:@"AKChatComposerEnabled"];
    AKChatDeliveryModeResetCacheForTesting();
    [controls dismissKeyboard];
    [host layoutIfNeeded];
    [self.guest makeFirstResponder:fixture];
    fixture.selection = NSMakeRange(0, 0);
    [fixture.text setString:@""];
    fixture.keyCodes = [NSMutableArray array];

    // The toolbar's keyboard button brings the card up; in review mode that card is the Composer.
    [controls toggleKeyboard];
    [host layoutIfNeeded];
    UITextView *input = (UITextView *)AKFindInputView(host, @"wolkaraforever.keyboard.draft");
    UIButton *send = (UIButton *)AKFindInputView(host, @"wolkaraforever.composer.send");
    UIButton *cancel = (UIButton *)AKFindInputView(host, @"wolkaraforever.composer.cancel");
    UIButton *listen = (UIButton *)AKFindInputView(host, @"wolkaraforever.composer.listen");
    UIButton *settings = (UIButton *)AKFindInputView(host, @"wolkaraforever.composer.settings");
    UIButton *replace = (UIButton *)AKFindInputView(host, @"wolkaraforever.keyboard.insert");
    UIView *card = [controls valueForKey:@"_composer"];
    if (!send || !cancel || !listen || !settings || !card || card.hidden || !input.isFirstResponder) {
        fprintf(stderr, "CHAT_COMPOSER_CARD_MISSING send=%d cancel=%d listen=%d settings=%d card=%d editor=%d\n",
                send != nil, cancel != nil, listen != nil, settings != nil, card != nil,
                (int)input.isFirstResponder);
        fflush(stderr);
    }
    assert(send && cancel && listen && settings && card && !card.hidden && input.isFirstResponder);
    // The classic row gives way to the Composer's, and neither is ever on screen twice.
    assert(replace.hidden);
    // Nothing typed, so there is nothing to send.
    assert(!send.enabled && cancel.enabled && listen.enabled);
    // The card stays above the keyboard, inside the host.
    assert(CGRectGetMaxY(card.frame) <= CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame) + 0.5);
    assert(CGRectGetMinY(card.frame) >= 0);
    // Dynamic Type, measured rather than assumed. At the default category the card is exactly the
    // 130 points it has always been and the action row is 44; at an accessibility category both
    // grow, the editor keeps its 48 points, and the card is still above the keyboard - which the
    // assertion above has just checked for whichever category this run was launched with. The
    // suite runs this fixture twice: once plain, once with an accessibility category.
    {
        UIView *row = [controls valueForKey:@"_composerRow"];
        UILabel *stateLabel = (UILabel *)AKFindInputView(host, @"wolkaraforever.composer.state");
        CGRect editorInHost = [input convertRect:input.bounds toView:host];
        CGFloat cardHeight = CGRectGetHeight(card.frame), rowHeight = CGRectGetHeight(row.frame);
        BOOL accessibilityText = [UIApplication.sharedApplication.preferredContentSizeCategory
            containsString:@"Accessibility"];
        if (accessibilityText) {
            if (!(cardHeight > 130.5 && rowHeight > 44.5)) {
                fprintf(stderr, "CHAT_COMPOSER_DYNAMIC_TYPE: category=%s card=%.1f row=%.1f\n",
                        UIApplication.sharedApplication.preferredContentSizeCategory.UTF8String,
                        cardHeight, rowHeight);
                fflush(stderr);
            }
            assert(cardHeight > 130.5 && rowHeight > 44.5);
        } else {
            if (fabs(cardHeight - 130) > 0.5 || fabs(rowHeight - 44) > 0.5) {
                fprintf(stderr, "CHAT_COMPOSER_DEFAULT_SIZE: category=%s card=%.1f row=%.1f\n",
                        UIApplication.sharedApplication.preferredContentSizeCategory.UTF8String,
                        cardHeight, rowHeight);
                fflush(stderr);
            }
            assert(fabs(cardHeight - 130) <= 0.5 && fabs(rowHeight - 44) <= 0.5);
        }
        // The editor is the part that must not absorb the difference, and the label is never given
        // less room than its own text needs.
        assert(fabs(CGRectGetHeight(editorInHost) - 48) <= 0.5);
        assert(stateLabel && CGRectGetHeight(stateLabel.frame) + 0.5 >= stateLabel.font.lineHeight);
        // Send is still on screen and inside the card at this size.
        assert(CGRectContainsRect(card.frame, [send convertRect:send.bounds toView:host]));
        NSLog(@"chat composer: Dynamic Type %s keeps the card above the keyboard (card=%.0f row=%.0f editor=%.0f)",
              UIApplication.sharedApplication.preferredContentSizeCategory.UTF8String,
              cardHeight, rowHeight, CGRectGetHeight(editorInHost));
    }
    NSLog(@"chat composer: the card is up, one row, above the keyboard, Replace withdrawn");

    // Typing makes it sendable; pressing Send reaches the guest exactly once.
    [input insertText:@"hi"];
    AKDrainFixtureEvents();
    assert(send.enabled);
    NSUInteger before = fixture.keyCodes.count;
    [send sendActionsForControlEvents:UIControlEventTouchUpInside];
    AKDrainFixtureEvents();
    NSArray<NSNumber *> *delta = [fixture.keyCodes subarrayWithRange:
        NSMakeRange(before, fixture.keyCodes.count - before)];
    // Open (36), the two characters, Return (36), Escape (53): five events, one of each kind.
    if (delta.count != 5 || delta[0].intValue != 36 || delta[3].intValue != 36 ||
        delta[4].intValue != 53 || delta[1].intValue == 36 || delta[2].intValue == 36) {
        fprintf(stderr, "CHAT_COMPOSER_SEND_MISMATCH keys=%s\n", delta.description.UTF8String);
        fflush(stderr);
    }
    assert(delta.count == 5 && delta[0].intValue == 36 && delta[3].intValue == 36 && delta[4].intValue == 53);
    assert(!input.text.length && !send.enabled);
    NSLog(@"chat composer: Send is one insertion, one Return, one Escape");

    // A repeated tap is not a second message.
    before = fixture.keyCodes.count;
    [send sendActionsForControlEvents:UIControlEventTouchUpInside];
    AKDrainFixtureEvents();
    assert(fixture.keyCodes.count == before);

    // Cancel sends no text at all: one Escape to close the chat the Composer opened.
    [controls openChatComposerFromSource:AKChatComposerSourceController];
    AKDrainFixtureEvents();
    [input insertText:@"never send this"];
    AKDrainFixtureEvents();
    before = fixture.keyCodes.count;
    [cancel sendActionsForControlEvents:UIControlEventTouchUpInside];
    AKDrainFixtureEvents();
    delta = [fixture.keyCodes subarrayWithRange:NSMakeRange(before, fixture.keyCodes.count - before)];
    if (delta.count != 1 || delta[0].intValue != 53) {
        fprintf(stderr, "CHAT_COMPOSER_CANCEL_MISMATCH keys=%s\n", delta.description.UTF8String);
        fflush(stderr);
    }
    assert(delta.count == 1 && delta[0].intValue == 53);
    assert(AKChatComposer.shared.state == AKChatComposerStateCancelled);
    NSLog(@"chat composer: Cancel posts one Escape and no text");

    // The failure the card has to be able to show: the guest has a password field, so a chat key
    // has no business there and nothing is posted. This is the Carbon adapter's real notification.
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification"
                                                     object:nil userInfo:@{@"enabled": @YES}];
    before = fixture.keyCodes.count;
    [controls openChatComposerFromSource:AKChatComposerSourceController];
    AKDrainFixtureEvents();
    assert(fixture.keyCodes.count == before);
    assert(AKChatComposer.shared.state == AKChatComposerStateFailed);
    UILabel *state = (UILabel *)AKFindInputView(host, @"wolkaraforever.composer.state");
    assert(state && [state.text isEqual:AKHostLocalized(@"chat.composer.problem.notSent")]);
    assert(!send.enabled && cancel.enabled);
    NSLog(@"chat composer: a refused open shows the localized error and posts nothing");
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification"
                                                     object:nil userInfo:@{@"enabled": @NO}];

    // Background and return: the draft is kept, and nothing is sent while the app is away.
    [controls openChatComposerFromSource:AKChatComposerSourceController];
    AKDrainFixtureEvents();
    [input insertText:@"unsent"];
    AKDrainFixtureEvents();
    before = fixture.keyCodes.count;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    AKDrainFixtureEvents();
    delta = [fixture.keyCodes subarrayWithRange:NSMakeRange(before, fixture.keyCodes.count - before)];
    // Only the Escape that closes the chat; no character of the draft reaches the guest.
    assert(delta.count == 1 && delta[0].intValue == 53);
    assert([AKChatComposer.shared.draft isEqual:@"unsent"]);
    NSLog(@"chat composer: background keeps the draft and sends nothing");

    // Back to the mode this installation had, so nothing here leaks into another launch.
    [AKChatComposer.shared cancel];
    [defaults removeObjectForKey:@"AKChatDeliveryMode"];
    [defaults removeObjectForKey:@"AKChatComposerEnabled"];
    AKChatDeliveryModeResetCacheForTesting();
    [controls dismissKeyboard];
    [host layoutIfNeeded];
    [fixture.text setString:@""];
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: the Composer card sends once, cancels without text, reports a refused open and keeps a backgrounded draft");
    exit(EXIT_SUCCESS);
}
#pragma mark - Live QA: the three states, held for a screenshot

// The three states the review record names - the card with nothing typed, the card with a line
// ready to send, and the card reporting a refused open - each held long enough for a capture taken
// from outside the process. It prints a marker before each and ends by itself, so a capture run
// cannot hang, and it never puts a character into the guest.
- (void)checkChatComposerVisual {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKInputFixtureView *fixture = (AKInputFixtureView *)self.guest.contentView;
    AKChatComposer *composer = AKChatComposer.shared;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@"review" forKey:@"AKChatDeliveryMode"];
    [defaults setBool:YES forKey:@"AKChatComposerEnabled"];
    AKChatDeliveryModeResetCacheForTesting();
    // The capture seam the shell fills in the app; this run is about what the card looks like.
    composer.testOnlyCapture = ^(BOOL start, NSUInteger generation) { (void)start; (void)generation; };
    [controls dismissKeyboard];
    [host layoutIfNeeded];
    [self.guest makeFirstResponder:fixture];
    [fixture.text setString:@""];
    [controls toggleKeyboard];
    [host layoutIfNeeded];
    NSLog(@"CHAT_COMPOSER_VISUAL idle");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // The state after dictation: a line on the card, Send enabled.
        [controls openChatComposerFromSource:AKChatComposerSourceToolbar];
        [composer speechFinished:@"Meet me at the inn when the sun comes up."
                      generation:composer.generation];
        [host layoutIfNeeded];
        NSLog(@"CHAT_COMPOSER_VISUAL ready");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            // The game has a password field, so the chat cannot be opened: the card says so.
            [composer cancel];
            [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification"
                                                             object:nil userInfo:@{@"enabled": @YES}];
            [controls openChatComposerFromSource:AKChatComposerSourceController];
            [host layoutIfNeeded];
            NSLog(@"CHAT_COMPOSER_VISUAL error");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification"
                                                                 object:nil userInfo:@{@"enabled": @NO}];
                [composer cancel];
                [defaults removeObjectForKey:@"AKChatDeliveryMode"];
                [defaults removeObjectForKey:@"AKChatComposerEnabled"];
                AKChatDeliveryModeResetCacheForTesting();
                NSLog(@"CHAT_COMPOSER_VISUAL done");
                exit(EXIT_SUCCESS);
            });
        });
    });
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    // The mobile interface is chosen the way the launcher chooses it: by the defaults key, here
    // in the argument domain, which is read before anything is written to disk. Standard is what
    // an absent key means, so the default run exercises that. It has to be set before the host
    // is made, because the controls read it once, when they are created.
    BOOL mobileInterface = [NSProcessInfo.processInfo.arguments containsObject:@"--mobile-interface"];
    BOOL composerTestArgument = [NSProcessInfo.processInfo.arguments containsObject:@"--composer-test"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--composer-qa"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--composer-visual"];
    // The delivery mode is read once, when the controls are made, so it is set here - in the
    // argument domain, which is read before anything is written to disk. The classic self-test
    // runs in classic direct, which is what every release through v1.0.10 has; the Composer's own
    // run asks for review, which is what a fresh installation gets.
    {
        NSMutableDictionary *modes = [[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        modes[@"AKChatDeliveryMode"] = composerTestArgument ? @"review" : @"classicDirect";
        if (mobileInterface) modes[@"WolkaraForeverInterfaceModeV1"] = @"ios";
        [NSUserDefaults.standardUserDefaults setVolatileDomain:modes forName:NSArgumentDomain];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--tracking-progress-test"]) {
        NSMutableDictionary *arguments=[[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        arguments[@"TKTouchGamepadEnabled"]=@NO;
        [NSUserDefaults.standardUserDefaults setVolatileDomain:arguments forName:NSArgumentDomain];
    }
    [NSApplication sharedApplication];
    self.guest = [[NSWindow alloc] initWithContentRect:((UIWindowScene *)scene).screen.bounds styleMask:0 backing:2 defer:NO];
    self.guest.contentView = [[AKInputFixtureView alloc] initWithFrame:self.guest.frame];
    self.guest.acceptsMouseMovedEvents = YES;
    [self.guest makeFirstResponder:self.guest.contentView];
    [self.guest makeKeyAndOrderFront:nil];
    self.pump = [NSTimer scheduledTimerWithTimeInterval:0.016 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
    }];
    BOOL selfTest = [NSProcessInfo.processInfo.arguments containsObject:@"--self-test"];
    BOOL composerTest = [NSProcessInfo.processInfo.arguments containsObject:@"--composer-test"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--composer-qa"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--composer-visual"];
    BOOL nativeReference = [NSProcessInfo.processInfo.arguments containsObject:@"--native-keyboard-reference"];
    if (selfTest || composerTest) {
        // A blocked main thread must fail instead of leaving simctl waiting.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                fprintf(stderr, "TOUCH_UI_SELF_TEST_TIMEOUT\n");
                _Exit(EXIT_FAILURE);
            });
    }
    // A plain launch is for looking at the fixture. Without --stay it closes itself
    // after a minute anyway, so a headless run cannot sit on it for ever.
    if (!selfTest && ![NSProcessInfo.processInfo.arguments containsObject:@"--stay"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                fprintf(stderr, "TOUCH_UI_LIFETIME_REACHED (pass --stay to keep it open)\n");
                _Exit(EXIT_SUCCESS);
            });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--tracking-progress-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self.pump invalidate]; self.pump = nil;
            [self checkTrackingUIProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--mouse-tracking-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self.pump invalidate]; self.pump=nil;
            [self checkMouseTrackingProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ui-progress-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate]; self.pump = nil;
            [self checkNativeUIProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--composer-qa"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate]; self.pump = nil;
            [self checkChatComposerQA];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--composer-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate]; self.pump = nil;
            [self checkChatComposerProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--composer-visual"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate]; self.pump = nil;
            [self checkChatComposerVisual];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--guest-poll-loop"]) {
        // Exercise UIKit inside the timer-entered desktop loop used by the
        // runtime, rather than only returning to UIApplicationMain each turn.
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate];
            self.pump = nil;
            while (YES) { @autoreleasepool {
                if ([NSProcessInfo.processInfo.arguments containsObject:@"--queued-traffic"]) AKFixtureInputSource(NULL);
                NSEvent *event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
                    inMode:NSDefaultRunLoopMode dequeue:YES];
                if (event.window) [NSApp sendEvent:event];
            } }
        }];
    }
    if (selfTest || nativeReference || [NSProcessInfo.processInfo.arguments containsObject:@"--show-keyboard"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            UIView *host = [self.guest valueForKey:@"_host"];
            AKTouchControls *controls = [host valueForKey:@"_touchControls"];
            CGSize originalSize = host.bounds.size;
            if (nativeReference) {
                UITextView *reference = [[UITextView alloc] initWithFrame:CGRectMake(48, 130, 360, 70)];
                reference.backgroundColor = UIColor.whiteColor;
                reference.accessibilityIdentifier = @"tolkara.reference-input";
                [host addSubview:reference];
                [reference becomeFirstResponder];
                return;
            }
            // Standard: the toolbar is where it has always been - just below the top, 252 by 44.
            // Mobile: the bottom centre, between the thumbs, folded into its handle.
            [host layoutIfNeeded];
            CGRect resting = controls.frame;
            if (selfTest) {
                assert(fabs(CGRectGetMidX(resting) - CGRectGetMidX(host.bounds)) < 1);
                if (mobileInterface) {
                    assert(fabs(CGRectGetMaxY(resting) - (CGRectGetMaxY(host.bounds) - host.safeAreaInsets.bottom - 8)) < 1);
                    assert(fabs(resting.size.width - 96) < 1 && fabs(resting.size.height - 34) < 1);
                    assert([controls valueForKey:@"_toolbarHandle"] != nil);
                } else {
                    assert(fabs(CGRectGetMinY(resting) - (host.safeAreaInsets.top + 8)) < 1);
                    assert(fabs(resting.size.width - 252) < 1 && fabs(resting.size.height - 44) < 1);
                    assert([controls valueForKey:@"_toolbarHandle"] == nil);
                }
            }
            [controls toggleKeyboard];
            if (!selfTest) return;
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                (void)timer;
                [host layoutIfNeeded];
                assert(controls.keyboardVisible && CGSizeEqualToSize(originalSize, host.bounds.size));
                assert(host.keyboardLayoutGuide.layoutFrame.size.height > 100);
                assert(CGRectGetMaxY(controls.frame) <= CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame));
                assert(CGRectGetMinY(controls.frame) >= 0);
                CGRect toolbarFrame = controls.frame;
                // Centred on the screen while typing too, as at rest: on an iPhone in landscape the
                // safe area is off-centre (a side inset for the camera), and TouchControls.m
                // centres on the host's bounds on purpose.
                assert(fabs(CGRectGetMidX(toolbarFrame) - CGRectGetMidX(host.bounds)) < 1);
                assert(fabs(CGRectGetMinY(toolbarFrame) - CGRectGetMinY(host.safeAreaLayoutGuide.layoutFrame) - 8) < 1);
                UITextView *input = (UITextView *)AKFindInputView(host, @"wolkaraforever.keyboard.draft");
                UIButton *insert = (UIButton *)AKFindInputView(host, @"wolkaraforever.keyboard.insert");
                UIButton *clear = (UIButton *)AKFindInputView(host, @"wolkaraforever.keyboard.clear");
                assert(input.isFirstResponder && [input conformsToProtocol:@protocol(UITextInput)]);
                assert(!input.superview.hidden && input.bounds.size.width > 100 && input.bounds.size.height >= 44);
                CGRect editor = [input convertRect:input.bounds toView:host];
                assert(CGRectGetMaxY(editor) < CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame));
                assert(CGRectGetMinY(editor) >= CGRectGetMaxY(controls.frame));
                AKInputFixtureView *fixture = (AKInputFixtureView *)self.guest.contentView;
                // Reopening with unknown existing text starts an empty draft;
                // an explicit empty replacement must clear the entire field.
                [fixture.text setString:@"Previous synthetic value"];
                fixture.selection = NSMakeRange(4, 0);
                assert(!input.text.length && insert.enabled);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                // Which of the three went wrong, said out loud. A bare assert in a fixture
                // whose only output is a console log tells the reader that something
                // moved and nothing about what, which is half a report.
                if (fixture.text.length || insert.enabled || fixture.replacements != 1) {
                    fprintf(stderr, "TOUCH_UI_INSERT_MISMATCH: guest text=%s insert.enabled=%d replacements=%lu\n",
                            fixture.text.UTF8String ?: "", (int)insert.enabled,
                            (unsigned long)fixture.replacements);
                    fflush(stderr);
                }
                assert(!fixture.text.length && !insert.enabled && fixture.replacements == 1);
                [fixture.text setString:@"A different old value"];
                fixture.selection = NSMakeRange(2, 3);
                [input insertText:@"Fixture @ñ🙂"];
                AKDrainFixtureEvents();
                assert([input.text isEqual:@"Fixture @ñ🙂"] && [fixture.text isEqual:@"A different old value"] && insert.enabled && clear.enabled);
                [input deleteBackward];
                assert([input.text isEqual:@"Fixture @ñ"]);
                // Editing an earlier range stays local; it must not append to
                // the game or emit backspaces until the user requests Insert.
                UITextPosition *end = [input positionFromPosition:input.beginningOfDocument offset:7];
                [input replaceRange:[input textRangeFromPosition:input.beginningOfDocument toPosition:end] withText:@"Draft"];
                assert([input.text isEqual:@"Draft @ñ"]);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"] && input.text.length == 0 && !insert.enabled && !clear.enabled);
                NSUInteger replacements = fixture.replacements;
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(0, 0) replacementText:@"\n"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"] && fixture.replacements == replacements);
                // Provisional text and unfinished dictation cannot be inserted.
                [input setMarkedText:@" provisional" selectedRange:NSMakeRange(12, 0)];
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"]);
                [input setMarkedText:@" ¡Hola equipo!" selectedRange:NSMakeRange(@" ¡Hola equipo!".length, 0)];
                [input unmarkText];
                id placeholder = [input insertDictationResultPlaceholder];
                assert(placeholder);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"]);
                [input removeDictationResultPlaceholder:placeholder willInsertResult:YES];
                [input insertText:@" Dictado."];
                assert([input.text isEqual:@" ¡Hola equipo! Dictado."]);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                NSMutableString *expected = [@" ¡Hola equipo! Dictado." mutableCopy];
                assert([fixture.text isEqual:expected]);
                // Many edits are now one normal document, not 64 resets of
                // UIKit's selection/undo context and 64 asynchronous forwards.
                for (NSUInteger i = 0; i < 64; i++) {
                    [input insertText:@"a"]; [input insertText:@"b"]; [input deleteBackward];
                    AKDrainFixtureEvents();
                    assert(input.text.length == i + 1 && [fixture.text isEqual:expected]);
                }
                NSString *draft = [input.text copy];
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [expected setString:draft];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length);
                [input insertText:@" discarded"];
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                assert(!input.text.length);
                [input insertText:@" failed recognition" ];
                [input setMarkedText:@" provisional" selectedRange:NSMakeRange(12, 0)];
                [input dictationRecognitionFailed];
                assert([input.text isEqual:@" failed recognition"]);
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                // Pasted controls are text, never implicit game commands.
                input.text = @"one\ntwo\tthree";
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [expected setString:@"one two three"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected]);
                UIStackView *accessory = (UIStackView *)controls.inputAccessoryView;
                [input insertText:@" done"];
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected]);
                // The system keyboard's key follows the interface. Standard: Done replaces the
                // selected field, exactly as every release through v1.0.7. Mobile: Send puts the
                // draft in the game's chat - F12 (the key the Interface mobile add-on binds to
                // its chat), the line, then Return - and the keyboard goes away. Replace stays
                // the button that fills the selected field without pressing Return.
                NSUInteger keysBefore = fixture.keyCodes.count, replacementsBefore = fixture.replacements;
                if (mobileInterface) {
                    [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                    AKDrainFixtureEvents();
                    NSArray<NSNumber *> *sent = [fixture.keyCodes subarrayWithRange:NSMakeRange(keysBefore, fixture.keyCodes.count - keysBefore)];
                    if (sent.count < 2 || sent.firstObject.unsignedShortValue != 111 || sent.lastObject.unsignedShortValue != 36 ||
                        ![fixture.text hasSuffix:@"done\r"] || fixture.replacements != replacementsBefore || input.text.length) {
                        fprintf(stderr, "TOUCH_UI_SEND_MISMATCH: keys=%s text=%s replacements=%lu->%lu draft=%s\n",
                                sent.description.UTF8String, fixture.text.UTF8String, (unsigned long)replacementsBefore,
                                (unsigned long)fixture.replacements, input.text.UTF8String);
                    }
                    assert(sent.count >= 2 && sent.firstObject.unsignedShortValue == 111 && sent.lastObject.unsignedShortValue == 36);
                    assert([fixture.text hasSuffix:@"done\r"] && fixture.replacements == replacementsBefore && !input.text.length);
                    // A repeated or queued Return after the line has gone sends nothing more.
                    keysBefore = fixture.keyCodes.count;
                    [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(0, 0) replacementText:@"\n"];
                    AKDrainFixtureEvents();
                    assert(fixture.keyCodes.count == keysBefore);
                    [expected setString:fixture.text];
                    // Open again to type more; the accessory's Return is still a plain Return.
                    [controls toggleKeyboard];
                } else {
                    assert(fixture.replacements == replacementsBefore);
                    [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                    AKDrainFixtureEvents();
                    [expected setString:@" done"];
                    assert(fixture.replacements == replacementsBefore + 1);
                    assert([fixture.text isEqual:expected] && !input.text.length);
                }
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                [expected appendString:@"\r"];
                assert([fixture.text isEqual:expected]);
                [input insertText:@" close without inserting"];
                [controls dismissKeyboard]; [controls toggleKeyboard];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length);
                [input setMarkedText:@" discard me" selectedRange:NSMakeRange(11, 0)];
                [controls dismissKeyboard];
                [input insertText:@" late result"];
                [input removeDictationResultPlaceholder:placeholder willInsertResult:NO];
                [input unmarkText];
                assert(!input.text.length);
                [controls toggleKeyboard];
                [input insertText:@" cancelled on background"];
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
                [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidResignKeyNotification object:input.window];
                assert(controls.keyboardVisible && input.text.length);
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
                assert(!controls.keyboardVisible && !input.text.length && input.superview.hidden);
                [input insertText:@" background result"];
                [host layoutIfNeeded];
                // Standard: the toolbar never left the top, so the frame is the one it had while
                // typing. Mobile: the keyboard gone, it is back at the bottom, wherever the
                // gamepad is.
                if (mobileInterface) {
                    assert(!CGRectEqualToRect(toolbarFrame, controls.frame));
                } else {
                    assert(CGRectEqualToRect(toolbarFrame, controls.frame));
                }
                CGRect down = controls.frame;
                if (mobileInterface) {
                    assert(fabs(CGRectGetMaxY(down) - (CGRectGetMaxY(host.bounds) - host.safeAreaInsets.bottom - 8)) < 1);
                } else {
                    assert(fabs(CGRectGetMinY(down) - (host.safeAreaInsets.top + 8)) < 1);
                }
                assert(fabs(CGRectGetMidX(down) - CGRectGetMidX(host.bounds)) < 1);
                [controls setGamepadVisible:NO]; [host layoutIfNeeded];
                assert(CGRectEqualToRect(down, controls.frame));

                // --- the optional performance HUD -----------------------------------
                AKPerformanceOverlay *overlay = [host valueForKey:@"_performanceOverlay"];
                AKGamepadLayout *prefs = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
                assert(overlay != nil);
                assert(overlay.hidden == !prefs.performanceOverlayEnabled);
                assert(overlay.isAccessibilityElement);
                [overlay updateMetrics];
                assert(overlay.accessibilityValue.length > 0);
                // No timer while it is hidden, even in a window.
                assert([overlay valueForKey:@"_pollTimer"] == nil);
                [overlay setExpanded:YES];
                assert(overlay.isExpanded);
                [overlay setExpanded:NO];
                assert(!overlay.isExpanded);
                overlay.hidden = NO; [host layoutIfNeeded];
                assert([overlay valueForKey:@"_pollTimer"] != nil);
                // A position pushed off screen comes back into the safe area on layout.
                overlay.center = CGPointMake(-500, -500);
                [overlay setNeedsLayout]; [overlay layoutIfNeeded];
                CGRect safe = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
                assert(CGRectContainsPoint(safe, overlay.center));
                overlay.hidden = YES;
                assert([overlay valueForKey:@"_pollTimer"] == nil);

                // --- a key the user took for dictation must not reach the game -------
                //
                // This drives the one place the adapter posts guest key events, because that
                // is where ownership is honoured. The shell cannot call in here - the adapter
                // is a dylib it does not link - so it publishes the usages it has taken and
                // this posts that same notification, which is the real path.
                [controls dismissKeyboard];
                [host layoutIfNeeded];
                assert([self.guest makeFirstResponder:fixture]);
                fixture.selection = NSMakeRange(0, 0);
                [fixture.text setString:@""];
                // --- what dictation types into -----------------------------------------
                //
                // The controls announce themselves as the game's text input, because they
                // are the layer's UIKeyInput and their delegate is what posts the guest's
                // keys. Dictation sends them touchInsertText: and
                // touchSpecialKey:characters: without asking whether they exist, so they
                // must answer both, and the words must reach the guest. The announced
                // object used to be the draft editor, which answers neither: the first
                // transcript aborted the app ("unrecognized selector", Dadpad,
                // 2026-10-21).
                assert([controls respondsToSelector:@selector(touchInsertText:)] &&
                       [controls respondsToSelector:@selector(touchSpecialKey:characters:)]);
                [controls touchInsertText:@"a"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"a"]);
                [controls touchSpecialKey:53 characters:@"\x1b"];
                AKDrainFixtureEvents();
                assert(!fixture.text.length);
                // --- the layer's own keys ------------------------------------
                //
                // iPadOS reports the software keyboard with no keys on screen when
                // it believes a hardware keyboard is attached (measured on Dadpad,
                // 2026-10-22: "system keyboard shown draftFirstResponder=1
                // height=0"). A custom input view is shown whatever the hardware
                // says, so it is the login field's only route to an @.
                [controls showLayerKeyboard];
                UIView *layer = [(UITextView *)AKFindInputView(host, @"wolkaraforever.keyboard.draft") inputView];
                assert(layer != nil && layer.bounds.size.height > 100);
                UIButton *atKey = (UIButton *)AKFindInputView(layer, @"wolkaraforever.layerkey.@");
                assert(atKey != nil && [atKey.titleLabel.text isEqual:@"@"]);
                assert(AKFindInputView(layer, @"wolkaraforever.layerkey.page") != nil);
                assert(AKFindInputView(layer, @"wolkaraforever.layerkey.delete") != nil);
                assert(AKFindInputView(layer, @"wolkaraforever.layerkey.system") != nil);
                // Dictation must not be hidden behind the system keyboard this replaces: the
                // microphone key asks the shell to toggle it, which is the only place that
                // links the voice module.
                __block NSUInteger dictationAsked = 0;
                id dictationObserver = [NSNotificationCenter.defaultCenter
                    addObserverForName:@"AKTouchDictationToggleNotification" object:nil
                                queue:NSOperationQueue.mainQueue
                           usingBlock:^(NSNotification *note) { (void)note; dictationAsked++; }];
                UIButton *micKey = (UIButton *)AKFindInputView(layer, @"wolkaraforever.layerkey.dictate");
                assert(micKey != nil);
                [micKey sendActionsForControlEvents:UIControlEventTouchUpInside];
                [NSNotificationCenter.defaultCenter removeObserver:dictationObserver];
                assert(dictationAsked == 1);
                [atKey sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"@"]);
                // The layer's keyboard types into the guest, so put the field back
                // where the key checks below expect it before going on.
                [controls dismissKeyboard];
                [host layoutIfNeeded];
                [fixture.text setString:@""];
                fixture.selection = NSMakeRange(0, 0);
                NSLog(@"native: the announced text target answers dictation and reaches the guest");
                // The one control that leaves a guest screen with no quit of its own. It asks
                // the guest's own application object to terminate, which is the game's
                // save-and-quit path; the tap itself runs in the adapter and is not exercised
                // here because it would end the fixture.
                UIButton *leave = (UIButton *)AKFindInputView(host, @"wolkaraforever.leaveGame");
                assert(leave && [leave.accessibilityLabel isEqual:@"Leave the game"]);
                NSLog(@"native: the toolbar carries Leave the game");
                NSEvent *arrived = AKFixturePressKey(host, fixture, 0x04 /* 'a' */);
                assert(arrived != nil && [fixture.text isEqual:@"a"]);
                AKFixtureOwnsUsages(@[@0x04]);
                [fixture.text setString:@""];
                fixture.selection = NSMakeRange(0, 0);
                arrived = AKFixturePressKey(host, fixture, 0x04);
                assert(arrived == nil && !fixture.text.length);
                NSLog(@"native: usage 0x04 is the user's; the guest's view never heard of it");
                // The release goes with it, or the game is left holding a key down.
                [host pressesEnded:[NSSet setWithObject:AKPressForUsage(0x04)] withEvent:nil];
                AKDrainFixtureEvents();
                assert(!fixture.text.length);
                // A key the user has not taken is untouched.
                fixture.selection = NSMakeRange(0, 0);
                arrived = AKFixturePressKey(host, fixture, 0x05 /* 'b' */);
                assert(arrived != nil && [fixture.text isEqual:@"b"]);
                // Taking it back gives the key straight back to the game.
                AKFixtureOwnsUsages(@[]);
                [fixture.text setString:@""];
                fixture.selection = NSMakeRange(0, 0);
                arrived = AKFixturePressKey(host, fixture, 0x04);
                assert(arrived != nil && [fixture.text isEqual:@"a"]);
                // And with nothing published at all - what a build that never fills this in
                // does - every key still goes through.
                AKTouchKeyIsTakenForVoice = NULL;
                [fixture.text setString:@""];
                fixture.selection = NSMakeRange(0, 0);
                arrived = AKFixturePressKey(host, fixture, 0x04);
                assert(arrived != nil && [fixture.text isEqual:@"a"]);
                [fixture.text setString:expected];

                [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                    (void)timer;
                    assert([fixture.text isEqual:expected]);
                    assert(!controls.keyboardVisible && host.isFirstResponder);
                    NSLog(@"TOUCH_UI_SELF_TEST_PASS: whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation, cancellation and fixed toolbar");
                    exit(EXIT_SUCCESS);
                }];
            }];
        }];
    }
}
@end

@interface AKInputFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKInputFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Input fixture" sessionRole:session.role];
    config.delegateClass = AKInputFixtureScene.class;
    return config;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AKInputFixtureApp.class)); } }
