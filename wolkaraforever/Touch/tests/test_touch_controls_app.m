// Original UIKit/AppKit fixture for manual touch/keyboard testing. No guest.
#import "AppKit.h"
#import "AKPerformanceOverlay.h"
#import "AKTouchEventPump.h"
#import "TouchControls.h"
#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "AKHostLocalization.h"
#import "TouchContract.h"
#import "TouchAreas.h"
#import "TouchTextBridge.h"
#import "TouchWorldSignal.h"
#include <assert.h>
#include <math.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Wait for the state an assertion needs, pumping the main run loop, instead of sleeping a fixed
// time and hoping. Sleeping a second measured whatever this machine had managed by then: on a
// busy simulator the Composer's card was read between the passes that size it and its action
// row, and the same code passed a minute earlier (measured 2026-11-16: two of three runs failed
// with card=130, row=0 where the assertions want row=44). The assertions themselves are
// unchanged - only the moment they run is, and the timeout is a budget for a slow machine rather
// than a claim about how long the product takes.
static BOOL AKTouchFixtureWaitFor(NSTimeInterval timeout, BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!ready()) {
        if ([deadline timeIntervalSinceNow] <= 0) return NO;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    }
    return YES;
}

// The keys the layer supplies when iPadOS has no software keyboard to give. The
// controls keep it private; the fixture asks for it the way the controls do.
@interface AKTouchControls (LayerKeyboardFixture)
- (void)showLayerKeyboard;
// The composer's language control asks through this; the fixture drives the same method the
// menu action calls, so what it exercises is the production path rather than a copy of it.
- (void)chooseSpeechLanguage:(NSString *)stored;
- (void)showControlSettings;
- (void)toggleToolbar;   // the handle's action
- (void)toggleTrackpad;  // the trackpad button's action
@end

// The composer's language button, by the identifier a person's assistive technology sees.
static UIButton *FixtureLanguageButton(UIView *root) {
    if ([root isKindOfClass:UIButton.class] &&
        [root.accessibilityIdentifier isEqual:@"wolkaraforever.keyboard.language"])
        return (UIButton *)root;
    for (UIView *child in root.subviews) {
        UIButton *found = FixtureLanguageButton(child);
        if (found) return found;
    }
    return nil;
}

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
// When set, every key down, key up and modifier change, as "down 99 COS" / "flags 59 C" (C control,
// O option, S shift, "-" none): what a TouchPlay key looks like to the game.
@property (nullable) NSMutableArray<NSString *> *keyEvents;
// When set, every mouse event, as "LeftDown 500,400" / "Moved 700,300" / "RightDrag 640,330", at the
// event's window location (bottom-left origin, as AppKit gives it).
@property (nullable) NSMutableArray<NSString *> *mouseEvents;
// The game's own reading of its input, as the iPad showed it (IPAD RUN 2, 16 Nov): it follows the modifiers as
// their flags-changed events come, but acts on a key or a button press in its frame - once it has drained the
// whole queue - with the modifiers it holds then. A chord whose modifiers came up in the same batch as its key
// reached it bare. When set, each key and button press as the frame acted on it: "down 99 COS", "LeftDown -";
// `endFrame` is the frame (AKFixtureFrame).
@property (nullable) NSMutableArray<NSString *> *frameActions;
@property NSEventModifierFlags frameModifiers;
@property NSMutableArray<NSString *> *framePending;
// Each button press's own modifier flags, as the event carried them ("-" for none).
@property (nullable) NSMutableArray<NSString *> *clickModifiers;
- (void)endFrame;
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
static NSString *AKFixtureModifiers(NSEventModifierFlags flags) {
    NSMutableString *text = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [text appendString:@"C"];
    if (flags & NSEventModifierFlagOption) [text appendString:@"O"];
    if (flags & NSEventModifierFlagShift) [text appendString:@"S"];
    return text.length ? text : @"-";
}
// The game's frame: what it was given since the last one, acted on with the modifiers it holds now.
- (void)framePend:(NSString *)action {
    if (!self.frameActions) return;
    if (!self.framePending) self.framePending = [NSMutableArray array];
    [self.framePending addObject:action];
}
- (void)endFrame {
    for (NSString *action in self.framePending)
        [self.frameActions addObject:[NSString stringWithFormat:@"%@ %@", action, AKFixtureModifiers(self.frameModifiers)]];
    [self.framePending removeAllObjects];
}
- (void)keyUp:(NSEvent *)event {
    [self.keyEvents addObject:[NSString stringWithFormat:@"up %u %@", event.keyCode, AKFixtureModifiers(event.modifierFlags)]];
    [self framePend:[NSString stringWithFormat:@"up %u", event.keyCode]];
}
- (void)flagsChanged:(NSEvent *)event {
    [self.keyEvents addObject:[NSString stringWithFormat:@"flags %u %@", event.keyCode, AKFixtureModifiers(event.modifierFlags)]];
    self.frameModifiers = event.modifierFlags;
}
- (void)keyDown:(NSEvent *)event {
    [self.keyEvents addObject:[NSString stringWithFormat:@"down %u %@", event.keyCode, AKFixtureModifiers(event.modifierFlags)]];
    [self framePend:[NSString stringWithFormat:@"down %u", event.keyCode]];
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
- (void)recordMouse:(NSString *)kind event:(NSEvent *)event {
    [self.mouseEvents addObject:[NSString stringWithFormat:@"%@ %.0f,%.0f", kind, event.locationInWindow.x, event.locationInWindow.y]];
}
- (void)mouseUp:(NSEvent *)event { [self recordMouse:@"LeftUp" event:event]; }
- (void)rightMouseUp:(NSEvent *)event { [self recordMouse:@"RightUp" event:event]; }
- (void)mouseMoved:(NSEvent *)event {
    [self recordMouse:@"Moved" event:event];
    self.lastAction = [NSString stringWithFormat:@"Pointer %.0f, %.0f", event.locationInWindow.x, event.locationInWindow.y];
    [self refresh];
}
- (void)recordPress:(NSString *)kind event:(NSEvent *)event {
    [self framePend:kind];
    [self.clickModifiers addObject:AKFixtureModifiers(event.modifierFlags)];
}
- (void)mouseDown:(NSEvent *)event { [self recordMouse:@"LeftDown" event:event]; [self recordPress:@"LeftDown" event:event]; self.lastAction = event.clickCount == 2 ? @"Double click" : @"Left click / hold"; [self refresh]; }
- (void)rightMouseDown:(NSEvent *)event { [self recordMouse:@"RightDown" event:event]; [self recordPress:@"RightDown" event:event]; self.lastAction = @"Right click / hold"; [self refresh]; }
- (void)otherMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Middle click"; [self refresh]; }
- (void)mouseDragged:(NSEvent *)event { [self recordMouse:@"LeftDrag" event:event]; self.lastAction = @"Left drag"; [self refresh]; }
- (void)rightMouseDragged:(NSEvent *)event { [self recordMouse:@"RightDrag" event:event]; self.lastAction = @"Right drag"; [self refresh]; }
- (void)scrollWheel:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Scroll %.0f, %.0f", event.deltaX, event.deltaY];
    [self refresh];
}
@end

// One frame of the game: everything queued, drained until the queue is empty, then acted on (endFrame).
static void AKFixtureFrame(void) {
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
    id guest = NSApp.keyWindow.contentView;
    if ([guest respondsToSelector:@selector(endFrame)]) [guest endFrame];
}
// Whether the host still holds a TouchPlay chord's modifiers for the game's frames (patch 0071); NO for a host that
// has no such thing.
static BOOL AKFixtureChordHeld(void) {
    UIView *host = [NSApp.keyWindow valueForKey:@"_host"];
    if (!host || !class_getInstanceVariable(host.class, "_chordCount")) return NO;
    return [[host valueForKey:@"_chordCount"] unsignedLongValue] != 0;
}
static void AKDrainFixtureEvents(void) {
    // Let UIKit finish its asynchronous text transaction before observing the
    // translated events. The fixture is entered from a timer, like the guest.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
    AKFixtureFrame();
    // A TouchPlay chord keeps its modifiers down for the game's next frames: let those frames go by, as the game's
    // own loop would, so a check sees the chord whole (and what waited for it).
    for (unsigned frames = 0; AKFixtureChordHeld() && frames < 400; frames++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, false);
        AKFixtureFrame();
    }
    assert(!AKFixtureChordHeld());
}

// Folds or opens the toolbar the way its own handle does, for a fixture that checks both states.
static void AKFixtureSetToolbarCollapsed(AKTouchControls *controls, BOOL collapsed) {
    SEL selector = NSSelectorFromString(@"setToolbarCollapsed:");
    NSMethodSignature *signature = [controls methodSignatureForSelector:selector];
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
    call.target = controls; call.selector = selector;
    [call setArgument:&collapsed atIndex:2];
    [call invoke];
}

static UIView *AKFindInputView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqual:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = AKFindInputView(child, identifier);
        if (found) return found;
    }
    return nil;
}
// The walk stick's auto-run lock (ruling A34): the plate's centre in the host's coordinates, above the ring as drawn now.
static CGPoint AKFixtureWalkLock(UIView *host) {
    UIView *plate = AKFindInputView(host, @"wolkaraforever.touch.walkStick.lockPlate");
    assert(plate);
    return [plate.superview convertPoint:plate.center toView:host];
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

#pragma mark - Fingers at the host's door (TouchPlay's buttons, Task 4)

// UITouch cannot be placed, so, as with the keys above, the two accessors the host reads are
// overridden: where the finger is, and that it is a finger.
@interface AKFixtureTouch : UITouch
@property CGPoint fixturePoint;
// What the host's "is any finger of this gesture still down" check reads from the event's touches.
@property (weak) UIView *fixtureView;
@property UITouchPhase fixturePhase;
@end
@implementation AKFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.fixturePoint; }
- (UITouchType)type { return UITouchTypeDirect; }
- (UIView *)view { return self.fixtureView; }
- (UITouchPhase)phase { return self.fixturePhase; }
@end
// An event whose touches are the fixture's fingers.
@interface AKFixtureEvent : UIEvent
@property NSSet<UITouch *> *fixtureTouches;
@end
@implementation AKFixtureEvent
- (NSSet<UITouch *> *)allTouches { return self.fixtureTouches; }
@end
static AKFixtureTouch *AKFixtureFinger(CGPoint point) { AKFixtureTouch *t = [AKFixtureTouch new]; t.fixturePoint = point; return t; }
static CGPoint AKFixtureCentre(AKTouchContract *contract, NSString *name, CGSize size) {
    CGRect rect = AKTouchAreaRect([contract areaNamed:name], size);
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}
// One TouchPlay key as the game sees it: control, option and shift pressed before the key, and released, in
// reverse, a few frames after it (patch 0071: the game reads them in its frame).
static NSArray<NSString *> *AKFixtureChordKey(unsigned code, BOOL down) {
    NSString *key = [NSString stringWithFormat:@"%@ %u COS", down ? @"down" : @"up", code];
    return @[@"flags 59 C", @"flags 58 CO", @"flags 56 COS", key, @"flags 56 CO", @"flags 58 C", @"flags 59 -"];
}
// Taps in one frame or a few: their downs and ups share one press of the modifiers.
static NSArray<NSString *> *AKFixtureChordTaps(NSArray<NSNumber *> *codes) {
    NSMutableArray<NSString *> *events = [@[@"flags 59 C", @"flags 58 CO", @"flags 56 COS"] mutableCopy];
    for (NSNumber *code in codes) {
        [events addObject:[NSString stringWithFormat:@"down %u COS", code.unsignedIntValue]];
        [events addObject:[NSString stringWithFormat:@"up %u COS", code.unsignedIntValue]];
    }
    [events addObjectsFromArray:@[@"flags 56 CO", @"flags 58 C", @"flags 59 -"]];
    return events;
}
// A tap: its down and up share one press of the modifiers.
static NSArray<NSString *> *AKFixtureChordTap(unsigned code) { return AKFixtureChordTaps(@[@(code)]); }

// iPad touch: the host offers every finger to TouchPlay's areas first. A finger on a button is the
// button's (lit, its key at the lift) and never reaches the 1.0.8 gestures; a finger in the world is a
// click as before; two at once each do their own thing. The contract is the iPad's own file.
static void AKFixtureCheckTouchAreas(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    if (!touchPlay) { assert(areas == nil); return; }
    assert(areas != nil);
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    assert(contract.areas.count == 26);
    areas.contract = contract;
    CGSize size = host.bounds.size;
    AKDrainFixtureEvents();
    guest.keyEvents = [NSMutableArray array];

    // A tap on spell2: lit at once, nothing sent until the lift, then F3 with the chord, down and up.
    AKFixtureTouch *spell = AKFixtureFinger(AKFixtureCentre(contract, @"spell2", size));
    guest.lastAction = @"Ready";
    [host touchesBegan:[NSSet setWithObject:spell] withEvent:nil];
    assert([areas pressViewForTouch:spell].superview == host);
    assert([host valueForKey:@"_directTouch"] == nil);
    AKDrainFixtureEvents();
    assert(guest.keyEvents.count == 0);
    [host touchesEnded:[NSSet setWithObject:spell] withEvent:nil];
    AKDrainFixtureEvents();
    if (![guest.keyEvents isEqualToArray:AKFixtureChordTap(99)])
        fprintf(stderr, "TOUCH_AREAS_HOST_MISMATCH: %s\n", [guest.keyEvents componentsJoinedByString:@", "].UTF8String);
    assert([guest.keyEvents isEqualToArray:AKFixtureChordTap(99)]);
    assert(![guest.lastAction containsString:@"click"]);
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0);
    assert(areas.activeFingerCount == 0);

    // Jump: R down when the finger lands, up when it lifts.
    [guest.keyEvents removeAllObjects];
    AKFixtureTouch *jump = AKFixtureFinger(AKFixtureCentre(contract, @"jump", size));
    [host touchesBegan:[NSSet setWithObject:jump] withEvent:nil];
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:AKFixtureChordKey(15, YES)]);
    [host touchesCancelled:[NSSet setWithObject:jump] withEvent:nil];
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:[AKFixtureChordKey(15, YES) arrayByAddingObjectsFromArray:AKFixtureChordKey(15, NO)]]);

    // The pinch never takes a finger that is on a button; a finger in the world it may.
    UIPinchGestureRecognizer *pinch = [host valueForKey:@"_pinch"];
    CGPoint worldPoint = CGPointMake(size.width / 2, size.height / 2);
    assert(![areas claimsPoint:worldPoint]);
    assert(pinch.delegate == (id)host);
    assert(![pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:AKFixtureFinger(AKFixtureCentre(contract, @"spell1", size))]);
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:AKFixtureFinger(worldPoint)]);

    // A button and the world at once: the button's key, and the world's click - not a pinch.
    [guest.keyEvents removeAllObjects];
    guest.lastAction = @"Ready";
    AKFixtureTouch *button = AKFixtureFinger(AKFixtureCentre(contract, @"spell1", size));
    AKFixtureTouch *world = AKFixtureFinger(worldPoint);
    NSSet *both = [NSSet setWithObjects:button, world, nil];
    [host touchesBegan:both withEvent:nil];
    assert([host valueForKey:@"_directTouch"] == world && ![[host valueForKey:@"_directMulti"] boolValue]);
    [host touchesEnded:both withEvent:nil];
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:AKFixtureChordTap(120)]);
    assert([guest.lastAction containsString:@"click"]);
    assert([host valueForKey:@"_directTouch"] == nil && ![[host valueForKey:@"_directMulti"] boolValue]);

    // A Jump finger held while two world fingers come down together (the pinch's gesture) and lift:
    // the world gesture is over when they are up - the held button finger does not keep it open - and
    // R stays down until the Jump finger lifts.
    [guest.keyEvents removeAllObjects];
    CGPoint jumpPoint = AKFixtureCentre(contract, @"jump", size);
    AKFixtureTouch *held = AKFixtureFinger(jumpPoint);
    AKFixtureTouch *w1 = AKFixtureFinger(worldPoint), *w2 = AKFixtureFinger(CGPointMake(worldPoint.x + 80, worldPoint.y));
    for (AKFixtureTouch *finger in @[held, w1, w2]) { finger.fixtureView = host; finger.fixturePhase = UITouchPhaseBegan; }
    AKFixtureEvent *event = [AKFixtureEvent new];
    event.fixtureTouches = [NSSet setWithObjects:held, w1, w2, nil];
    [host touchesBegan:[NSSet setWithObject:held] withEvent:event];
    [host touchesBegan:[NSSet setWithObjects:w1, w2, nil] withEvent:event];
    assert([[host valueForKey:@"_directMulti"] boolValue]);
    held.fixturePhase = UITouchPhaseStationary; w1.fixturePhase = w2.fixturePhase = UITouchPhaseEnded;
    [host touchesEnded:[NSSet setWithObjects:w1, w2, nil] withEvent:event];
    assert(![[host valueForKey:@"_directMulti"] boolValue] && [host valueForKey:@"_directTouch"] == nil);
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:AKFixtureChordKey(15, YES)]);
    held.fixturePhase = UITouchPhaseEnded;
    [host touchesEnded:[NSSet setWithObject:held] withEvent:event];
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:[AKFixtureChordKey(15, YES) arrayByAddingObjectsFromArray:AKFixtureChordKey(15, NO)]]);

    // A reload while Jump is held lets go of R; that finger's later moves and lift are still the
    // button's, never a left drag with no button pressed.
    [guest.keyEvents removeAllObjects];
    AKFixtureTouch *reloaded = AKFixtureFinger(jumpPoint);
    [host touchesBegan:[NSSet setWithObject:reloaded] withEvent:nil];
    areas.contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:AKFixtureChordTap(15)]);
    guest.lastAction = @"Ready";   // R's key down said "Keyboard input received"
    // The host's pointer stays where it was: no drag (the guest view would not even see a drag with no
    // button down, so the host's own pointer is what tells).
    CGPoint pointerBefore = [[host valueForKey:@"_last"] CGPointValue];
    reloaded.fixturePoint = CGPointMake(worldPoint.x + 37, worldPoint.y + 23);
    [host touchesMoved:[NSSet setWithObject:reloaded] withEvent:nil];
    assert(CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], pointerBefore));
    [host touchesEnded:[NSSet setWithObject:reloaded] withEvent:nil];
    AKDrainFixtureEvents();
    assert(CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], pointerBefore));
    assert([guest.lastAction isEqual:@"Ready"]);
    assert([guest.keyEvents isEqualToArray:AKFixtureChordTap(15)]);   // only R's press and release, from the reload

    // The game view changes size (rotation, Stage Manager) while Jump is held: R is let go.
    [guest.keyEvents removeAllObjects];
    AKFixtureTouch *resized = AKFixtureFinger(AKFixtureCentre(areas.contract, @"jump", size));
    [host touchesBegan:[NSSet setWithObject:resized] withEvent:nil];
    CGRect frame = host.frame;
    host.frame = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width - 120, frame.size.height);
    [host layoutIfNeeded];
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:AKFixtureChordTap(15)]);
    assert(areas.activeFingerCount == 0);
    [host touchesEnded:[NSSet setWithObject:resized] withEvent:nil];
    host.frame = frame;
    [host layoutIfNeeded];
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:AKFixtureChordTap(15)]);   // the lift added nothing

    // Without a contract the same finger is a plain click again (1.0.8 touch).
    areas.contract = nil;
    [guest.keyEvents removeAllObjects];
    guest.lastAction = @"Ready";
    AKFixtureTouch *plain = AKFixtureFinger(AKFixtureCentre(contract, @"spell2", size));
    [host touchesBegan:[NSSet setWithObject:plain] withEvent:nil];
    [host touchesEnded:[NSSet setWithObject:plain] withEvent:nil];
    AKDrainFixtureEvents();
    assert(guest.keyEvents.count == 0 && [guest.lastAction containsString:@"click"]);
    guest.keyEvents = nil;
}

// iPad touch: the walk stick (Task 6) is the controls' own view over the game, below the toolbar. A
// thumb in the walk area is its, never the host's; its movement keys go through the host's key path
// (bare W/S/A/D, no modifiers); a walking thumb and a later finger are never a pinch, two fingers at once are (patch 0073). Every other mode has none.
static void AKFixtureCheckWalkStick(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    if (!touchPlay) { assert([controls valueForKey:@"_walkStick"] == nil && overlay == nil); return; }
    assert([controls valueForKey:@"_walkStick"] != nil && overlay.superview == host);
    assert([host.subviews indexOfObject:overlay] < [host.subviews indexOfObject:controls]);
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    // The add-on's current keys (ruling A22: none on W, A, S or D) and the older file's (TouchPlay-v1.lua).
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    NSString *olderPath = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1" ofType:@"lua"];
    AKTouchContract *current = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    AKTouchContract *older = AKTouchContractParse([NSString stringWithContentsOfFile:olderPath encoding:NSUTF8StringEncoding error:NULL]);
    assert(current.areas.count == 26 && older.areas.count == 26);
    areas.contract = current;
    [host layoutIfNeeded];
    CGSize size = host.bounds.size;
    CGPoint p = CGPointMake(size.width * 0.25, size.height * 0.62);
    assert([host hitTest:p withEvent:nil] == overlay);
    // The toolbar, which reaches into the walk half, stays above the stick.
    CGRect bar = controls.frame;
    CGPoint barPoint = CGPointMake(CGRectGetMinX(bar) + 10, CGRectGetMidY(bar));
    assert(barPoint.x < size.width / 2);
    assert([[host hitTest:barPoint withEvent:nil] isDescendantOfView:controls]);
    // A walk through the host's key path: W down with no modifiers, W up at the lift.
    AKDrainFixtureEvents();
    guest.keyEvents = [NSMutableArray array];
    // The stick's clock, so a second finger can come "later" (patch 0073: soon after the thumb is a pinch).
    __block NSTimeInterval stickSkew = 0;
    [overlay setValue:^NSTimeInterval { return NSProcessInfo.processInfo.systemUptime + stickSkew; } forKey:@"clock"];
    AKFixtureTouch *thumb = AKFixtureFinger(p);
    thumb.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    thumb.fixturePoint = CGPointMake(p.x, p.y - 50);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    if (![guest.keyEvents isEqualToArray:@[@"down 13 -"]])
        fprintf(stderr, "TOUCH_WALK_HOST_MISMATCH: %s\n", [guest.keyEvents componentsJoinedByString:@", "].UTF8String);
    assert([guest.keyEvents isEqualToArray:@[@"down 13 -"]]);
    // The pinch and the stick (patch 0073): the stick's thumb may be one of a pinch's fingers, but a walking thumb and a
    // finger that comes later are a walk and a look - the pinch never begins, W stays down.
    UIPinchGestureRecognizer *pinch = [host valueForKey:@"_pinch"];
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:thumb]);
    stickSkew = 0.5;
    AKFixtureTouch *world = AKFixtureFinger(CGPointMake(size.width * 0.55, size.height * 0.5));
    world.fixtureView = host;
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:world]);
    assert(![pinch.delegate gestureRecognizerShouldBegin:pinch]);
    AKDrainFixtureEvents();
    assert([guest.keyEvents isEqualToArray:@[@"down 13 -"]]);
    // Walking, a tap on spell1 (the host's own finger path): its chord tap goes out between, W stays down
    // through it, and W comes up last, at the stick's lift.
    CGPoint spellPoint = AKFixtureCentre(current, @"spell1", size);
    AKFixtureTouch *spell = AKFixtureFinger(spellPoint);
    spell.fixtureView = host;
    [host touchesBegan:[NSSet setWithObject:spell] withEvent:nil];
    [host touchesEnded:[NSSet setWithObject:spell] withEvent:nil];
    [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    NSMutableArray *expected = [NSMutableArray arrayWithObject:@"down 13 -"];
    [expected addObjectsFromArray:AKFixtureChordTap(120)];
    [expected addObject:@"up 13 -"];
    if (![guest.keyEvents isEqualToArray:expected])
        fprintf(stderr, "TOUCH_WALK_HOST_MISMATCH (W + spell1): %s\n", [guest.keyEvents componentsJoinedByString:@", "].UTF8String);
    assert([guest.keyEvents isEqualToArray:expected]);
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0 && [host valueForKey:@"_directTouch"] == nil);
    // Two fingers at once, one on the stick and one on the game (17 Nov 2026: a pinch grabbed the stick): a pinch.
    // The pinch begins, the stick lets go and sends nothing - not even after, while its finger moves and lifts.
    [guest.keyEvents removeAllObjects];
    AKFixtureTouch *pinchThumb = AKFixtureFinger(p);
    pinchThumb.fixtureView = overlay;
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:pinchThumb]);
    [overlay touchesBegan:[NSSet setWithObject:pinchThumb] withEvent:nil];
    AKFixtureTouch *pinchOther = AKFixtureFinger(CGPointMake(size.width * 0.5, size.height * 0.5));
    pinchOther.fixtureView = host;
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:pinchOther]);
    assert([pinch.delegate gestureRecognizerShouldBegin:pinch]);
    pinchThumb.fixturePoint = CGPointMake(p.x - 60, p.y + 60);
    [overlay touchesMoved:[NSSet setWithObject:pinchThumb] withEvent:nil];
    [overlay touchesEnded:[NSSet setWithObject:pinchThumb] withEvent:nil];
    AKDrainFixtureEvents();
    if (guest.keyEvents.count) fprintf(stderr, "TOUCH_WALK_PINCH_MISMATCH: %s\n", [guest.keyEvents componentsJoinedByString:@", "].UTF8String);
    assert(guest.keyEvents.count == 0);
    // The older add-on's file holds spell1 on CTRL-ALT-SHIFT-D, the stick's D (ruling A22): walking right,
    // a held spell1 sends no chord on D (no hold key now: F2 at the lift) and D stays down until the stick lets go
    // (a chord on D's code is no key, so nothing ever releases it, and nothing has to press it again).
    areas.contract = older;
    __block NSTimeInterval now = 100;
    areas.clock = ^NSTimeInterval { return now; };
    [guest.keyEvents removeAllObjects];
    AKFixtureTouch *right = AKFixtureFinger(p);
    right.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:right] withEvent:nil];
    right.fixturePoint = CGPointMake(p.x + 50, p.y);
    [overlay touchesMoved:[NSSet setWithObject:right] withEvent:nil];
    AKFixtureTouch *held = AKFixtureFinger(spellPoint);
    held.fixtureView = host;
    [host touchesBegan:[NSSet setWithObject:held] withEvent:nil];
    now += 1.0; [areas tick];
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    [overlay touchesEnded:[NSSet setWithObject:right] withEvent:nil];
    AKDrainFixtureEvents();
    expected = [NSMutableArray arrayWithObject:@"down 2 -"];
    [expected addObjectsFromArray:AKFixtureChordTap(120)];
    [expected addObject:@"up 2 -"];
    if (![guest.keyEvents isEqualToArray:expected])
        fprintf(stderr, "TOUCH_WALK_HOST_MISMATCH (D + older spell1): %s\n", [guest.keyEvents componentsJoinedByString:@", "].UTF8String);
    assert([guest.keyEvents isEqualToArray:expected]);
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0);
    areas.clock = nil;
    areas.contract = current;
    // No contract: no stick, the thumb is the host's (1.0.8's plain taps).
    areas.contract = nil;
    assert([host hitTest:p withEvent:nil] == host);
    guest.keyEvents = nil;
}

#pragma mark - The world by touch (Task 5, rules 2 and 10)

// "LeftDown 500,400" as the guest records it: the host's point at the window's bottom-left origin.
static NSString *AKFixtureMouse(NSString *kind, CGPoint p, UIView *host) {
    return [NSString stringWithFormat:@"%@ %.0f,%.0f", kind, p.x, host.bounds.size.height - p.y];
}
// The guest's mouse events without the pointer moves: the clicks and drags.
static NSString *AKFixtureClicks(AKInputFixtureView *guest) {
    NSMutableArray *clicks = [NSMutableArray array];
    for (NSString *event in guest.mouseEvents) if (![event hasPrefix:@"Moved"]) [clicks addObject:event];
    return [clicks componentsJoinedByString:@" | "];
}
static NSString *AKFixtureJoin(NSArray<NSString *> *events) { return [events componentsJoinedByString:@" | "]; }
static void AKFixtureExpect(NSString *what, NSString *got, NSString *expected) {
    if ([got isEqualToString:expected]) return;
    fprintf(stderr, "TOUCH_WORLD_MISMATCH %s:\n  got      %s\n  expected %s\n", what.UTF8String, got.UTF8String, expected.UTF8String);
    assert(0);
}
// One finger, down and up at once (a tap), or down, moved through `path`, and up at its last point.
static void AKFixtureGesture(UIView *host, CGPoint start, NSArray<NSValue *> *path) {
    AKFixtureTouch *finger = AKFixtureFinger(start);
    [host touchesBegan:[NSSet setWithObject:finger] withEvent:nil];
    for (NSValue *point in path) {
        finger.fixturePoint = point.CGPointValue;
        [host touchesMoved:[NSSet setWithObject:finger] withEvent:nil];
    }
    [host touchesEnded:[NSSet setWithObject:finger] withEvent:nil];
    AKDrainFixtureEvents();
}
static void AKFixtureTap(UIView *host, CGPoint p) { AKFixtureGesture(host, p, @[]); }
static void AKFixtureResetInput(AKInputFixtureView *guest) {
    AKDrainFixtureEvents();
    guest.keyEvents = [NSMutableArray array];
    guest.mouseEvents = [NSMutableArray array];
}
#pragma mark - A chord in the game's frame (IPAD RUN 2, 16 Nov)

// On the iPad every TouchPlay chord reached the game without its modifiers: spell holds opened the game's own H/J/K/M
// panels, Jump (V) toggled the nameplates, the F2..F8 taps did nothing. The game follows the modifiers as their
// flags-changed events come but acts on a key in its frame, after it has drained the queue - when the host had already
// let them go in the same batch. This fixture's guest acts the same way (frameActions). The chord's modifiers stay
// down for that frame and come up a few frames later; whatever else comes meanwhile - a world click, a walk key -
// waits for them, so it never carries the chord.
static void AKFixtureCheckChordFrames(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    if (!touchPlay) return;
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    // The current add-on's file: its keys in the game's own order (ALT-CTRL-SHIFT-), ruling A29.
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-altorder" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    AKFixtureExpect(@"chord_frames: the current add-on's world key, in the game's order", contract.worldKey ?: @"(no contract)", @"ALT-CTRL-SHIFT-F1");
    AKTouchContract *contractBefore = areas.contract;
    BOOL liveBefore = areas.live;
    areas.contract = contract;
    areas.live = YES;
    [host layoutIfNeeded];
    CGSize size = host.bounds.size;
    AKDrainFixtureEvents();
    guest.keyEvents = [NSMutableArray array];
    guest.mouseEvents = [NSMutableArray array];
    guest.frameActions = [NSMutableArray array];
    guest.clickModifiers = [NSMutableArray array];

    // chord_in_its_frame: a tap on spell2 (F3). The frame that takes it acts on it with control, option and shift down.
    AKFixtureTouch *spell = AKFixtureFinger(AKFixtureCentre(contract, @"spell2", size));
    [host touchesBegan:[NSSet setWithObject:spell] withEvent:nil];
    [host touchesEnded:[NSSet setWithObject:spell] withEvent:nil];
    AKFixtureFrame();
    AKFixtureExpect(@"chord_in_its_frame: the frame acts on F3 with its chord", AKFixtureJoin(guest.frameActions), @"down 99 COS | up 99 COS");
    // ...and they are still down two frames later, a moment after (a frame or more after the key's, however often the
    // guest polls in one)...
    AKFixtureFrame(); AKFixtureFrame();
    AKFixtureExpect(@"chord_in_its_frame: still down two frames on", AKFixtureJoin(guest.keyEvents),
                    @"flags 59 C | flags 58 CO | flags 56 COS | down 99 COS | up 99 COS");
    // ...and come up, in reverse, once those frames and 50 ms have gone by; nothing more is acted on.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.06, false);
    AKFixtureFrame();
    AKFixtureExpect(@"chord_in_its_frame: up after its frames", AKFixtureJoin(guest.keyEvents),
                    @"flags 59 C | flags 58 CO | flags 56 COS | down 99 COS | up 99 COS | flags 56 CO | flags 58 C | flags 59 -");
    AKFixtureExpect(@"chord_in_its_frame: nothing else acted on", AKFixtureJoin(guest.frameActions), @"down 99 COS | up 99 COS");
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0);

    // jump_then_world_tap: Jump (V) held, and a world tap in the same frame. The game acts on V with the chord; the
    // world tap's click waits for the chord to come up and is a plain click, in a later frame. A tap while Jump is
    // still held, after that, is plain as well, and V stays down until its finger lifts.
    [guest.keyEvents removeAllObjects]; [guest.mouseEvents removeAllObjects]; [guest.frameActions removeAllObjects];
    AKFixtureTouch *jump = AKFixtureFinger(AKFixtureCentre(contract, @"jump", size));
    CGPoint world = CGPointMake(size.width * 0.5, size.height * 0.35), later = CGPointMake(size.width * 0.62, size.height * 0.2);
    assert(![areas claimsPoint:world] && ![areas claimsPoint:later]);
    [host touchesBegan:[NSSet setWithObject:jump] withEvent:nil];
    AKFixtureTouch *tap = AKFixtureFinger(world);
    [host touchesBegan:[NSSet setWithObject:tap] withEvent:nil];
    [host touchesEnded:[NSSet setWithObject:tap] withEvent:nil];
    AKFixtureFrame();
    AKFixtureExpect(@"jump_then_world_tap: the frame acts on V with its chord, no click yet", AKFixtureJoin(guest.frameActions), @"down 9 COS");
    AKDrainFixtureEvents();
    AKFixtureExpect(@"jump_then_world_tap: the click is plain, after the chord", AKFixtureJoin(guest.frameActions), @"down 9 COS | LeftDown -");
    AKFixtureExpect(@"jump_then_world_tap: the click carries no modifier", AKFixtureJoin(guest.clickModifiers), @"-");
    AKFixtureExpect(@"jump_then_world_tap: the click is where the finger was", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", world, host), AKFixtureMouse(@"LeftUp", world, host)]));
    AKFixtureExpect(@"jump_then_world_tap: V held, the chord up", AKFixtureJoin(guest.keyEvents),
                    @"flags 59 C | flags 58 CO | flags 56 COS | down 9 COS | flags 56 CO | flags 58 C | flags 59 -");
    AKFixtureTap(host, later);
    AKFixtureExpect(@"jump_then_world_tap: a tap later in the hold is plain", AKFixtureJoin(guest.frameActions), @"down 9 COS | LeftDown - | LeftDown -");
    AKFixtureExpect(@"jump_then_world_tap: its click carries no modifier", AKFixtureJoin(guest.clickModifiers), @"- | -");
    [host touchesEnded:[NSSet setWithObject:jump] withEvent:nil];
    AKFixtureFrame();
    AKFixtureExpect(@"jump_then_world_tap: V comes up with its chord", AKFixtureJoin(guest.frameActions), @"down 9 COS | LeftDown - | LeftDown - | up 9 COS");
    AKDrainFixtureEvents();
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0 && areas.activeFingerCount == 0);

    // walk_in_the_chord_window: a spell tap, and the thumb starts walking in the same frame. W waits for the chord and
    // is bare; the spell's frame has the chord.
    [guest.keyEvents removeAllObjects]; [guest.mouseEvents removeAllObjects]; [guest.frameActions removeAllObjects];
    CGPoint p = CGPointMake(size.width * 0.25, size.height * 0.62);
    assert([host hitTest:p withEvent:nil] == overlay);
    AKFixtureTouch *spell1 = AKFixtureFinger(AKFixtureCentre(contract, @"spell1", size));
    [host touchesBegan:[NSSet setWithObject:spell1] withEvent:nil];
    [host touchesEnded:[NSSet setWithObject:spell1] withEvent:nil];
    AKFixtureTouch *thumb = AKFixtureFinger(p);
    thumb.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    thumb.fixturePoint = CGPointMake(p.x, p.y - 50);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    AKFixtureFrame();
    AKFixtureExpect(@"walk_in_the_chord_window: the frame acts on F2 with its chord, W not yet", AKFixtureJoin(guest.frameActions), @"down 120 COS | up 120 COS");
    AKDrainFixtureEvents();
    AKFixtureExpect(@"walk_in_the_chord_window: W bare, after the chord", AKFixtureJoin(guest.frameActions), @"down 120 COS | up 120 COS | down 13 -");
    AKFixtureExpect(@"walk_in_the_chord_window: the order", AKFixtureJoin(guest.keyEvents),
                    @"flags 59 C | flags 58 CO | flags 56 COS | down 120 COS | up 120 COS | flags 56 CO | flags 58 C | flags 59 - | down 13 -");
    [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpect(@"walk_in_the_chord_window: W up at the lift", AKFixtureJoin(guest.frameActions), @"down 120 COS | up 120 COS | down 13 - | up 13 -");
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0);

    guest.frameActions = nil; guest.clickModifiers = nil; guest.keyEvents = nil; guest.mouseEvents = nil;
    areas.live = liveBefore;
    areas.contract = contractBefore;
    [host layoutIfNeeded];
    AKDrainFixtureEvents();
}

// IPAD RUN 2 (16 Nov): on the character screen a tap clicked at the cursor, not at the finger - the cursor had to be
// slid onto a button first. The trackpad was on (the device log has no "cursor visibility hidden=1" at the start,
// which every run with it off prints): the toolbar's switch is one setting for every interface, and one left on in
// another interface carried into iPad touch, whose plain touches (0055) are a click where the finger is. iPad touch
// has its own switch now, off until it is turned on in iPad touch; this run started with the shared one on (its
// argument domain). Turned on here, the next game in iPad touch starts with it on, and the shared one is untouched.
static void AKFixtureCheckTrackpadSwitch(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    if (!touchPlay) return;
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    assert([[defaults objectForKey:@"TKTouchTrackpadEnabled"] isEqual:@YES]);   // as another interface left it
    NSDictionary *persistent = [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    id sharedBefore = persistent[@"TKTouchTrackpadEnabled"];
    assert(!controls.trackpadEnabled);
    // A tap clicks where the finger is (the areas not live: the character screen).
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    BOOL liveBefore = areas.live;
    areas.live = NO;
    CGPoint finger = CGPointMake(host.bounds.size.width * 0.3, host.bounds.size.height * 0.4);
    assert(!CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], finger));
    AKFixtureResetInput(guest);
    AKFixtureTap(host, finger);
    AKFixtureExpect(@"trackpad_switch: a tap on the character screen clicks at the finger", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", finger, host), AKFixtureMouse(@"LeftUp", finger, host)]));
    // The toolbar's button turns iPad touch's own switch, and only that one.
    [controls toggleTrackpad];
    assert(controls.trackpadEnabled);
    assert([[defaults objectForKey:@"WolkaraForeverIPadTouchTrackpadEnabled"] isEqual:@YES]);
    assert((sharedBefore == nil && [defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier][@"TKTouchTrackpadEnabled"] == nil) ||
           [[defaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier][@"TKTouchTrackpadEnabled"] isEqual:sharedBefore]);
    @autoreleasepool {
        AKTouchControls *next = [[AKTouchControls alloc] initWithFrame:CGRectZero];   // the next game in iPad touch
        assert(next.trackpadEnabled);
    }
    [controls toggleTrackpad];
    assert(!controls.trackpadEnabled && [[defaults objectForKey:@"WolkaraForeverIPadTouchTrackpadEnabled"] isEqual:@NO]);
    [defaults removeObjectForKey:@"WolkaraForeverIPadTouchTrackpadEnabled"];
    areas.live = liveBefore;
    AKDrainFixtureEvents();
    guest.keyEvents = nil; guest.mouseEvents = nil;
}

// A finger kept still for `seconds` of real time (the host's own hold timer), then lifted.
static void AKFixtureHoldStill(UIView *host, AKInputFixtureView *guest, CGPoint p, NSTimeInterval seconds, AKFixtureTouch **out) {
    AKFixtureTouch *finger = AKFixtureFinger(p);
    [host touchesBegan:[NSSet setWithObject:finger] withEvent:nil];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
    AKDrainFixtureEvents();
    *out = finger;
}
// The same, without the wall-clock wait: the host's hold timer is looked at (it is set for `seconds`, the hold time that
// applies) and fired. The real wait stays in the first hold of each kind (AKFixtureHoldStill), so the timer itself is
// still seen to run; this saves a second or so per repeat out of the self-test's 30 s.
static void AKFixtureHoldFired(UIView *host, CGPoint p, NSTimeInterval seconds, AKFixtureTouch **out) {
    AKFixtureTouch *finger = AKFixtureFinger(p);
    [host touchesBegan:[NSSet setWithObject:finger] withEvent:nil];
    NSTimer *hold = [host valueForKey:@"_directHold"];
    assert(hold.isValid && hold.fireDate.timeIntervalSinceNow > seconds - 0.2 && hold.fireDate.timeIntervalSinceNow <= seconds);
    [hold fire];
    AKDrainFixtureEvents();
    *out = finger;
}

// 1.0.8's direct touch, unchanged: what every mobile mode has, and iPad touch with no button list.
// A hold is a right click; two taps are two left clicks; a finger at the very edge is a click too.
static void AKFixtureCheckWorld108(UIView *host, AKInputFixtureView *guest) {
    AKFixtureResetInput(guest);
    AKFixtureTouch *held = nil;
    CGPoint still = CGPointMake(700, 300);
    AKFixtureHoldStill(host, guest, still, 0.6, &held);
    AKFixtureExpect(@"no_contract_is_1_0_8: hold", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"RightDown", still, host), AKFixtureMouse(@"RightUp", still, host)]));
    assert(guest.keyEvents.count == 0);
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    AKFixtureResetInput(guest);
    CGPoint a = CGPointMake(500, 400), b = CGPointMake(520, 410);
    AKFixtureTap(host, a);
    AKFixtureTap(host, b);
    AKFixtureExpect(@"no_contract_is_1_0_8: two taps", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host),
                                    AKFixtureMouse(@"LeftDown", b, host), AKFixtureMouse(@"LeftUp", b, host)]));
    AKFixtureResetInput(guest);
    CGPoint edge = CGPointMake(10, 500);
    AKFixtureTap(host, edge);
    AKFixtureExpect(@"no_contract_is_1_0_8: edge", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", edge, host), AKFixtureMouse(@"LeftUp", edge, host)]));
    // A drag before any hold is a left drag (the camera), whatever TouchPlay's turn setting would say.
    AKFixtureResetInput(guest);
    CGPoint from = CGPointMake(600, 300), to = CGPointMake(640, 330);
    AKFixtureGesture(host, from, @[[NSValue valueWithCGPoint:to]]);
    AKFixtureExpect(@"no_contract_is_1_0_8: drag", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", from, host), AKFixtureMouse(@"LeftDrag", to, host), AKFixtureMouse(@"LeftUp", to, host)]));
    guest.keyEvents = nil; guest.mouseEvents = nil;
}

// iPad touch with TouchPlay's button list: a world touch (one no button takes) is a left click on a
// tap, a right click on a second tap close by, the contract's world key on a hold (TouchPlay's card),
// a look drag (a right drag when the character turns with the view), and nothing at the very edge.
// A finger dragged off a spell aims it: the cursor follows, the lift clicks or (on Interact) cancels.
static void AKFixtureCheckWorldTouch(UIView *host, AKInputFixtureView *guest, BOOL touchPlay, BOOL directGestures) {
    if (!directGestures) return;   // Standard and iOS on Duo have no direct gestures at all
    if (!touchPlay) { AKFixtureCheckWorld108(host, guest); return; }
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1" ofType:@"lua"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    AKTouchContract *contract = AKTouchContractParse(text);
    assert(contract.turnWithView && [contract.worldKey isEqual:@"CTRL-ALT-SHIFT-F1"]);
    areas.contract = contract;
    // The fixture's clock for the second tap's 1.5 s; the hold below runs on the real timer.
    __block NSTimeInterval now = 1000;
    areas.clock = ^NSTimeInterval { return now; };
    CGSize size = host.bounds.size;
    CGPoint a = CGPointMake(500, 400), b = CGPointMake(520, 410);
    for (NSValue *point in @[[NSValue valueWithCGPoint:a], [NSValue valueWithCGPoint:b], [NSValue valueWithCGPoint:CGPointMake(700, 300)],
                             [NSValue valueWithCGPoint:CGPointMake(640, 560)], [NSValue valueWithCGPoint:CGPointMake(600, 300)]])
        assert(![areas claimsPoint:point.CGPointValue]);   // the world, at this size

    // rule2_tap_twice_right_clicks: a tap, then another within 40 pt and 1.5 s, is a right click there,
    // and the record is gone: a third tap is a left click again.
    AKFixtureResetInput(guest);
    AKFixtureTap(host, a);
    now += 0.4;
    AKFixtureTap(host, b);
    AKFixtureExpect(@"rule2_tap_twice_right_clicks", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host),
                                    AKFixtureMouse(@"RightDown", b, host), AKFixtureMouse(@"RightUp", b, host)]));
    assert(guest.keyEvents.count == 0);
    AKFixtureResetInput(guest);
    now += 0.2;
    AKFixtureTap(host, b);
    AKFixtureExpect(@"rule2: the right click cleared the record", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", b, host), AKFixtureMouse(@"LeftUp", b, host)]));

    // rule2_far_or_slow_second_tap_selects: 100 pt away, or 2.0 s later, is a second left click.
    now += 10;
    AKFixtureResetInput(guest);
    CGPoint far = CGPointMake(600, 400);
    AKFixtureTap(host, a);
    now += 0.4;
    AKFixtureTap(host, far);
    AKFixtureExpect(@"rule2_far_second_tap_selects", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host),
                                    AKFixtureMouse(@"LeftDown", far, host), AKFixtureMouse(@"LeftUp", far, host)]));
    now += 10;
    AKFixtureResetInput(guest);
    AKFixtureTap(host, a);
    now += 2.0;
    AKFixtureTap(host, b);
    AKFixtureExpect(@"rule2_slow_second_tap_selects", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host),
                                    AKFixtureMouse(@"LeftDown", b, host), AKFixtureMouse(@"LeftUp", b, host)]));

    // A drag in between clears the record: the tap after it selects.
    now += 10;
    AKFixtureTap(host, a);
    now += 0.2;
    AKFixtureGesture(host, a, @[[NSValue valueWithCGPoint:CGPointMake(560, 440)]]);
    now += 0.2;
    AKFixtureResetInput(guest);
    AKFixtureTap(host, b);
    AKFixtureExpect(@"rule2: a drag clears the record", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", b, host), AKFixtureMouse(@"LeftUp", b, host)]));

    // second_tap_on_area_is_not_world: a world tap just above spell1, then a tap on spell1 within
    // 40 pt and 1.5 s: spell1's key, and no right click.
    now += 10;
    CGRect spell1 = AKTouchAreaRect([contract areaNamed:@"spell1"], size);
    CGPoint above = CGPointMake(CGRectGetMidX(spell1), CGRectGetMinY(spell1) - 6), on = CGPointMake(CGRectGetMidX(spell1), CGRectGetMinY(spell1) + 6);
    assert(![areas claimsPoint:above] && [areas claimsPoint:on]);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, above);
    now += 0.3;
    AKFixtureTap(host, on);
    AKFixtureExpect(@"second_tap_on_area_is_not_world: clicks", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", above, host), AKFixtureMouse(@"LeftUp", above, host)]));
    AKFixtureExpect(@"second_tap_on_area_is_not_world: keys", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(120)));

    // rule2_hold_world_sends_world_key: still for the contract's 0.45 s (the real timer): the cursor is
    // already at the finger, then ctrl+opt+shift F1 down and up; no right click, and the lift adds nothing.
    now += 10;
    AKFixtureResetInput(guest);
    CGPoint still = CGPointMake(700, 300);
    AKFixtureTouch *held = nil;
    AKFixtureHoldStill(host, guest, still, 0.6, &held);
    assert(CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], still));
    AKFixtureExpect(@"rule2_hold_world_sends_world_key: cursor", AKFixtureJoin(guest.mouseEvents), AKFixtureMouse(@"Moved", still, host));
    AKFixtureExpect(@"rule2_hold_world_sends_world_key: keys", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(122)));
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpect(@"rule2_hold_world_sends_world_key: lift", AKFixtureClicks(guest), @"");
    AKFixtureExpect(@"rule2_hold_world_sends_world_key: the lift adds no key", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(122)));
    // ...and a hold is not a first tap: a tap right after it selects.
    AKFixtureResetInput(guest);
    AKFixtureTap(host, still);
    AKFixtureExpect(@"rule2: a hold leaves no tap record", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", still, host), AKFixtureMouse(@"LeftUp", still, host)]));
    // The hold time is the contract's: with hold=0.9, nothing at 0.55 s, the key by 1.1 s.
    areas.contract = AKTouchContractParse([text stringByReplacingOccurrencesOfString:@"hold=0.45" withString:@"hold=0.9"]);
    now += 10;
    AKFixtureResetInput(guest);
    held = AKFixtureFinger(still);
    [host touchesBegan:[NSSet setWithObject:held] withEvent:nil];
    AKDrainFixtureEvents();
    assert(guest.keyEvents.count == 0 && [AKFixtureClicks(guest) isEqualToString:@""]);
    NSTimer *holdTimer = [host valueForKey:@"_directHold"];
    assert(holdTimer.isValid && holdTimer.fireDate.timeIntervalSinceNow > 0.7 && holdTimer.fireDate.timeIntervalSinceNow <= 0.9);
    [holdTimer fire];
    AKDrainFixtureEvents();
    AKFixtureExpect(@"hold time from the contract", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(122)));
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    areas.contract = contract;

    // drag_after_hold: after the world key, sliding is still a look drag, per the turn setting (turn=1:
    // a right drag; turn=0: a left drag), from where the finger came down.
    for (NSString *turn in @[@"turn=1", @"turn=0"]) {
        areas.contract = AKTouchContractParse([text stringByReplacingOccurrencesOfString:@";turn=1;" withString:[NSString stringWithFormat:@";%@;", turn]]);
        BOOL right = [turn isEqual:@"turn=1"];
        now += 10;
        AKFixtureResetInput(guest);
        CGPoint slid = CGPointMake(760, 340);
        AKFixtureHoldFired(host, still, 0.45, &held);
        held.fixturePoint = slid;
        [host touchesMoved:[NSSet setWithObject:held] withEvent:nil];
        [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
        AKDrainFixtureEvents();
        AKFixtureExpect([@"drag_after_hold: keys " stringByAppendingString:turn], AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(122)));
        AKFixtureExpect([@"drag_after_hold: drag " stringByAppendingString:turn], AKFixtureClicks(guest),
                        AKFixtureJoin(@[AKFixtureMouse(right ? @"RightDown" : @"LeftDown", still, host), AKFixtureMouse(right ? @"RightDrag" : @"LeftDrag", slid, host),
                                        AKFixtureMouse(right ? @"RightUp" : @"LeftUp", slid, host)]));
    }
    areas.contract = contract;

    // hold_then_second_tap: a tap, then a hold close by within 1.5 s: the hold is the world key, not a
    // right click; and it leaves no record, so the next tap close by selects.
    now += 10;
    AKFixtureResetInput(guest);
    AKFixtureTap(host, a);
    now += 0.3;
    AKFixtureHoldFired(host, b, 0.45, &held);
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    now += 0.2;
    AKFixtureTap(host, b);
    AKFixtureExpect(@"hold_then_second_tap: clicks", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host),
                                    AKFixtureMouse(@"LeftDown", b, host), AKFixtureMouse(@"LeftUp", b, host)]));
    AKFixtureExpect(@"hold_then_second_tap: keys", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(122)));

    // M4: a world key the reader does not know is no key: the hold is 0055's right click again.
    areas.contract = AKTouchContractParse([text stringByReplacingOccurrencesOfString:@"world=CTRL-ALT-SHIFT-F1" withString:@"world=CTRL-ALT-SHIFT-F20"]);
    assert(areas.contract != nil);
    now += 10;
    AKFixtureResetInput(guest);
    AKFixtureHoldFired(host, still, 0.45, &held);
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpect(@"unknown world key: right click", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"RightDown", still, host), AKFixtureMouse(@"RightUp", still, host)]));
    assert(guest.keyEvents.count == 0);
    areas.contract = contract;

    // rule10_turn_with_view_right_drag (turn=1): a drag is a right drag, the character turns with the view.
    now += 10;
    AKFixtureResetInput(guest);
    CGPoint from = CGPointMake(600, 300), to = CGPointMake(640, 330);
    AKFixtureGesture(host, from, @[[NSValue valueWithCGPoint:to]]);
    AKFixtureExpect(@"rule10_turn_with_view_right_drag", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"RightDown", from, host), AKFixtureMouse(@"RightDrag", to, host), AKFixtureMouse(@"RightUp", to, host)]));
    // turn_off_left_drag (turn=0): a left drag, the camera only.
    areas.contract = AKTouchContractParse([text stringByReplacingOccurrencesOfString:@";turn=1;" withString:@";turn=0;"]);
    assert(!areas.contract.turnWithView);
    now += 10;
    AKFixtureResetInput(guest);
    AKFixtureGesture(host, from, @[[NSValue valueWithCGPoint:to]]);
    AKFixtureExpect(@"turn_off_left_drag", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", from, host), AKFixtureMouse(@"LeftDrag", to, host), AKFixtureMouse(@"LeftUp", to, host)]));
    areas.contract = contract;

    // drag_to_world_clicks_there: begun on spell7 and dragged to (640,560): spell7's F8 once, when it
    // left; the cursor follows the finger; the lift is a left click at (640,560).
    now += 10;
    AKFixtureResetInput(guest);
    CGPoint spell7 = AKFixtureCentre(contract, @"spell7", size), ground = CGPointMake(640, 560);
    AKFixtureTouch *aiming = AKFixtureFinger(spell7);
    [host touchesBegan:[NSSet setWithObject:aiming] withEvent:nil];
    aiming.fixturePoint = CGPointMake(spell7.x - 120, spell7.y - 40);
    [host touchesMoved:[NSSet setWithObject:aiming] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpect(@"drag_to_world_clicks_there: key on leaving", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(100)));
    AKFixtureExpect(@"drag_to_world_clicks_there: no click yet", AKFixtureClicks(guest), @"");
    aiming.fixturePoint = ground;
    [host touchesMoved:[NSSet setWithObject:aiming] withEvent:nil];
    AKDrainFixtureEvents();
    assert(CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], ground));
    AKFixtureExpect(@"drag_to_world_clicks_there: the cursor follows", AKFixtureJoin(guest.mouseEvents),
                    AKFixtureJoin(@[AKFixtureMouse(@"Moved", CGPointMake(spell7.x - 120, spell7.y - 40), host), AKFixtureMouse(@"Moved", ground, host)]));
    [host touchesEnded:[NSSet setWithObject:aiming] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpect(@"drag_to_world_clicks_there: click", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", ground, host), AKFixtureMouse(@"LeftUp", ground, host)]));
    AKFixtureExpect(@"drag_to_world_clicks_there: no other key", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(100)));
    assert([host valueForKey:@"_directTouch"] == nil && areas.activeFingerCount == 0);
    assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0);

    // drag_to_interact_cancels (A19): lifted inside Interact, the aim is stopped with Interact's hold key
    // (the add-on's hidden "stop" button), never Escape; no click. The iPad's current file has no hold key
    // on Interact: then nothing at all. Lifted over any other button (A21): the same stop, no click.
    NSString *stopText = [NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"TouchPlay-v1-stopkey" ofType:@"lua"]
                                                   encoding:NSUTF8StringEncoding error:NULL];
    AKTouchContract *stopContract = AKTouchContractParse(stopText);
    assert([[stopContract areaNamed:@"interact"].holdKey isEqual:@"CTRL-ALT-SHIFT-R"]);
    // The stop key follows the spell's tap key in the same few frames, so the two share one press of the modifiers.
    NSArray<NSArray *> *cancels = @[@[contract, @"interact", @[]], @[stopContract, @"interact", @[@15]],
                                    @[stopContract, @"bags", @[@15]], @[stopContract, @"spell3", @[@15]]];
    for (NSArray *cancel in cancels) {
        areas.contract = cancel[0];
        now += 10;
        AKFixtureResetInput(guest);
        aiming = AKFixtureFinger(spell7);
        [host touchesBegan:[NSSet setWithObject:aiming] withEvent:nil];
        aiming.fixturePoint = ground;
        [host touchesMoved:[NSSet setWithObject:aiming] withEvent:nil];
        aiming.fixturePoint = AKFixtureCentre(cancel[0], cancel[1], size);
        [host touchesMoved:[NSSet setWithObject:aiming] withEvent:nil];
        [host touchesEnded:[NSSet setWithObject:aiming] withEvent:nil];
        AKDrainFixtureEvents();
        NSString *what = [NSString stringWithFormat:@"drag_to_%@_cancels (%@)", cancel[1], cancel[0] == contract ? @"no stop key" : @"stop key"];
        AKFixtureExpect([what stringByAppendingString:@": keys"], AKFixtureJoin(guest.keyEvents),
                        AKFixtureJoin(AKFixtureChordTaps([@[@100] arrayByAddingObjectsFromArray:cancel[2]])));
        AKFixtureExpect([what stringByAppendingString:@": no click"], AKFixtureClicks(guest), @"");
        assert([[host valueForKey:@"_mods"] unsignedLongValue] == 0);
    }
    areas.contract = contract;

    // aim_while_dragging (I1): another finger is dragging the view (turn=0: left button down; turn=1:
    // right button down) when a spell is aimed. The aim ends that drag first, as a pinch would (its
    // button comes up, its later moves and lift post nothing), so the click is a plain left click,
    // never a click with the drag's button still down (left+right is WoW's run).
    for (NSString *turn in @[@"turn=0", @"turn=1"]) {
        areas.contract = AKTouchContractParse([text stringByReplacingOccurrencesOfString:@";turn=1;" withString:[NSString stringWithFormat:@";%@;", turn]]);
        BOOL right = [turn isEqual:@"turn=1"];
        now += 10;
        AKFixtureResetInput(guest);
        CGPoint from = CGPointMake(600, 300), to = CGPointMake(640, 330);
        AKFixtureTouch *look = AKFixtureFinger(from);
        [host touchesBegan:[NSSet setWithObject:look] withEvent:nil];
        look.fixturePoint = to;
        [host touchesMoved:[NSSet setWithObject:look] withEvent:nil];
        aiming = AKFixtureFinger(spell7);
        [host touchesBegan:[NSSet setWithObject:aiming] withEvent:nil];
        aiming.fixturePoint = ground;
        [host touchesMoved:[NSSet setWithObject:aiming] withEvent:nil];
        [host touchesEnded:[NSSet setWithObject:aiming] withEvent:nil];
        look.fixturePoint = CGPointMake(700, 350);
        [host touchesMoved:[NSSet setWithObject:look] withEvent:nil];
        [host touchesEnded:[NSSet setWithObject:look] withEvent:nil];
        AKDrainFixtureEvents();
        AKFixtureExpect([@"aim_while_dragging " stringByAppendingString:turn], AKFixtureClicks(guest),
                        AKFixtureJoin(@[AKFixtureMouse(right ? @"RightDown" : @"LeftDown", from, host), AKFixtureMouse(right ? @"RightDrag" : @"LeftDrag", to, host),
                                        AKFixtureMouse(right ? @"RightUp" : @"LeftUp", to, host),
                                        AKFixtureMouse(@"LeftDown", ground, host), AKFixtureMouse(@"LeftUp", ground, host)]));
        AKFixtureExpect([@"aim_while_dragging keys " stringByAppendingString:turn], AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(100)));
        assert(![[host valueForKey:@"_pressedLeft"] boolValue] && ![[host valueForKey:@"_pressedRight"] boolValue]);
        assert([host valueForKey:@"_directTouch"] == nil && ![[host valueForKey:@"_directMulti"] boolValue]);
    }
    areas.contract = contract;

    // M3: a world finger held while another aims and places a spell: the aim moved the shared pointer, so
    // when the hold fires the cursor goes back under the held finger before the world key.
    now += 10;
    AKFixtureResetInput(guest);
    AKFixtureTouch *waiting = AKFixtureFinger(still);
    [host touchesBegan:[NSSet setWithObject:waiting] withEvent:nil];
    aiming = AKFixtureFinger(spell7);
    [host touchesBegan:[NSSet setWithObject:aiming] withEvent:nil];
    aiming.fixturePoint = ground;
    [host touchesMoved:[NSSet setWithObject:aiming] withEvent:nil];
    [host touchesEnded:[NSSet setWithObject:aiming] withEvent:nil];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.6, false);
    AKDrainFixtureEvents();
    assert(CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], still));
    AKFixtureExpect(@"hold after an aim: the cursor back first", guest.mouseEvents.lastObject, AKFixtureMouse(@"Moved", still, host));
    AKFixtureExpect(@"hold after an aim: keys", AKFixtureJoin(guest.keyEvents),
                    AKFixtureJoin([AKFixtureChordTap(100) arrayByAddingObjectsFromArray:AKFixtureChordTap(122)]));
    [host touchesEnded:[NSSet setWithObject:waiting] withEvent:nil];
    AKDrainFixtureEvents();

    // edge_touches_ignored: fingers that land in the 20 pt edge zone (x 10, x W-5, y H-8, y 8) post
    // nothing, not even the pointer, whatever they do; the pinch never takes one; and a world tap while
    // one is down is still a tap, not a pinch.
    now += 10;
    AKFixtureResetInput(guest);
    CGPoint lastBefore = [[host valueForKey:@"_last"] CGPointValue];
    UIPinchGestureRecognizer *pinch = [host valueForKey:@"_pinch"];
    for (NSValue *point in @[[NSValue valueWithCGPoint:CGPointMake(10, 500)], [NSValue valueWithCGPoint:CGPointMake(size.width - 5, 500)],
                             [NSValue valueWithCGPoint:CGPointMake(600, size.height - 8)], [NSValue valueWithCGPoint:CGPointMake(1100, 8)]]) {
        assert(![areas claimsPoint:point.CGPointValue]);
        assert(![pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:AKFixtureFinger(point.CGPointValue)]);
        AKFixtureGesture(host, point.CGPointValue, @[[NSValue valueWithCGPoint:CGPointMake(500, 500)]]);
        AKFixtureTouch *still2 = nil;
        AKFixtureHoldStill(host, guest, point.CGPointValue, 0.05, &still2);
        [host touchesEnded:[NSSet setWithObject:still2] withEvent:nil];
    }
    AKDrainFixtureEvents();
    AKFixtureExpect(@"edge_touches_ignored", AKFixtureJoin(guest.mouseEvents), @"");
    assert(guest.keyEvents.count == 0 && [host valueForKey:@"_directTouch"] == nil);
    assert(CGPointEqualToPoint([[host valueForKey:@"_last"] CGPointValue], lastBefore));
    assert(![areas ownsTouch:AKFixtureFinger(CGPointMake(10, 500))]);
    AKFixtureTouch *edgeFinger = AKFixtureFinger(CGPointMake(10, 500));
    [host touchesBegan:[NSSet setWithObject:edgeFinger] withEvent:nil];
    AKFixtureTap(host, a);
    assert(![[host valueForKey:@"_directMulti"] boolValue]);
    AKFixtureExpect(@"edge finger held, world tap", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host)]));
    [host touchesEnded:[NSSet setWithObject:edgeFinger] withEvent:nil];
    assert(![areas ownsTouch:edgeFinger]);

    // no_contract_is_1_0_8: the same host with the button list gone is 1.0.8's direct touch again.
    areas.contract = nil;
    areas.clock = nil;
    AKFixtureCheckWorld108(host, guest);
}

#pragma mark - The chat keyboard and the password from Apple's Passwords app (Task 7, rule 9)

// Every regular file in the app's container, as "size mtime", by path inside it.
static NSDictionary<NSString *, NSString *> *AKFixtureContainerFiles(void) {
    NSString *home = NSHomeDirectory();
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLFileSizeKey, NSURLContentModificationDateKey];
    for (NSURL *url in [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:home] includingPropertiesForKeys:keys options:0 errorHandler:nil]) {
        NSDictionary *values = [url resourceValuesForKeys:keys error:NULL];
        if (![values[NSURLIsRegularFileKey] boolValue]) continue;
        files[[url.path substringFromIndex:MIN(url.path.length, home.length)]] =
            [NSString stringWithFormat:@"%@ %f", values[NSURLFileSizeKey], [values[NSURLContentModificationDateKey] timeIntervalSince1970]];
    }
    return files;
}
// Whether any file in the container holds `secret`, as UTF-8 or UTF-16.
static BOOL AKFixtureContainerHolds(NSString *secret) {
    NSArray<NSData *> *forms = @[[secret dataUsingEncoding:NSUTF8StringEncoding], [secret dataUsingEncoding:NSUTF16LittleEndianStringEncoding],
                                 [secret dataUsingEncoding:NSUTF16BigEndianStringEncoding]];
    for (NSString *path in AKFixtureContainerFiles()) {
        NSData *data = [NSData dataWithContentsOfFile:[NSHomeDirectory() stringByAppendingString:path] options:NSDataReadingMappedIfSafe error:NULL];
        for (NSData *form in forms) if (data.length && [data rangeOfData:form options:0 range:NSMakeRange(0, data.length)].location != NSNotFound) {
            fprintf(stderr, "TOUCH_TEXT_HOST: the password is in %s\n", path.UTF8String);
            return YES;
        }
    }
    return NO;
}
// The game's secure event input, as patch 0058 announces it, and the fixture clock the world signal and the password
// bridge read (ruling A24): nothing here waits for a real timer. `AKFixtureAdvance` moves the clock and settles both.
static NSTimeInterval gFixtureNow = 5000;
static AKTouchControls *gFixtureControls;
static void AKFixturePostSecure(BOOL enabled) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKSecureEventInputDidChangeNotification" object:nil userInfo:@{@"enabled": @(enabled)}];
}
static void AKFixtureUseClocks(AKTouchControls *controls) {
    if (gFixtureControls == controls) return;
    gFixtureControls = controls;
    NSTimeInterval (^clock)(void) = ^NSTimeInterval { return gFixtureNow; };
    [(AKTouchWorldSignal *)[controls valueForKey:@"_worldSignal"] setClock:clock];
    [(AKTouchTextBridge *)[controls valueForKey:@"_textBridge"] setClock:clock];
}
static void AKFixtureAdvance(NSTimeInterval seconds) {
    gFixtureNow += seconds;
    [(AKTouchWorldSignal *)[gFixtureControls valueForKey:@"_worldSignal"] tick];
    [(AKTouchTextBridge *)[gFixtureControls valueForKey:@"_textBridge"] tick];
}
// The game's password box taking (YES) or losing (NO) the keyboard. An "on" is held for good, as a real box is - past
// the bridge's debounce and the world signal's limits, in the world too (ruling A27: 1.5 s) - so a box also means
// "not in the world".
static void AKFixtureSecureInput(BOOL enabled) {
    AKFixturePostSecure(enabled);
    if (enabled && gFixtureControls) AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
}
// The app is not active (Control Centre, a notification, Face ID's sheet) for the length of `block`: what the controls
// read when the game turns secure input off.
static void AKFixtureWhileInactive(void (^block)(void)) {
    Method method = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^UIApplicationState(id receiver) { (void)receiver; return UIApplicationStateInactive; }));
    block();
    method_setImplementation(method, original);
}
// What the add-on sends: one short pulse entering the world, two leaving it.
static void AKFixturePulse(void) { AKFixturePostSecure(YES); AKFixtureAdvance(0.15); AKFixturePostSecure(NO); }
static void AKFixtureEnterWorldPulse(void) { AKFixturePulse(); AKFixtureAdvance(1.0); }
static void AKFixtureLeaveWorldPulses(void) { AKFixturePulse(); AKFixtureAdvance(0.15); AKFixturePulse(); AKFixtureAdvance(1.0); }
// Ruling A32: a window or panel open while still in the world is three pulses.
static void AKFixtureWindowPulses(void) {
    AKFixturePulse(); AKFixtureAdvance(0.15); AKFixturePulse(); AKFixtureAdvance(0.15); AKFixturePulse(); AKFixtureAdvance(1.0);
}
// iPad touch: the player is in the world (the buttons are live). Idempotent.
static void AKFixtureEnterWorld(UIView *host) {
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKFixtureUseClocks(controls);
    // The signal too, not only the areas: a check may have switched the areas on by hand.
    if ([[host valueForKey:@"_touchAreas"] isLive] && [(AKTouchWorldSignal *)[controls valueForKey:@"_worldSignal"] inWorld]) return;
    AKFixtureEnterWorldPulse();
    assert([[host valueForKey:@"_touchAreas"] isLive]);
}
static void AKFixtureExpectKeys(NSString *what, AKInputFixtureView *guest, NSArray<NSString *> *expected) {
    if ([guest.keyEvents isEqualToArray:expected]) return;
    fprintf(stderr, "TOUCH_TEXT_HOST_MISMATCH %s:\n  got      %s\n  expected %s\n", what.UTF8String,
            [guest.keyEvents componentsJoinedByString:@", "].UTF8String, [expected componentsJoinedByString:@", "].UTF8String);
    assert(0);
}

#pragma mark - Leaving the app (Task 8, review focus 4)

// The app going away: a call, Control Centre, the app switcher (will resign active), then Home (did enter background).
// The application comes back after, so the rest of the fixture runs as before.
static void AKFixtureLeaveApp(NSNotificationName name) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
    AKDrainFixtureEvents();
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
}
// The key downs and ups the game heard, without the modifier events around them.
static NSString *AKFixtureKeyPresses(AKInputFixtureView *guest) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *event in guest.keyEvents) if (![event hasPrefix:@"flags"]) [keys addObject:event];
    return [keys componentsJoinedByString:@", "];
}
static void AKFixtureInterruptionExpect(NSString *what, NSString *got, NSString *expected) {
    if ([got isEqualToString:expected]) return;
    fprintf(stderr, "TOUCH_INTERRUPTION_MISMATCH %s:\n  got      %s\n  expected %s\n", what.UTF8String, got.UTF8String, expected.UTF8String);
    assert(0);
}

// Task 8: the app leaves the screen with fingers and keys down. Every key comes up, the stick is centred and
// hidden, auto-run is off, no hold ring completes, an aimed spell is stopped, a world drag lets go of its mouse
// button - and the fingers that were down, lifting later, send nothing more. Outside iPad touch none of it runs.
static void AKFixtureCheckInterruptions(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    CGSize size = host.bounds.size;
    CGPoint worldPoint = CGPointMake(size.width * 0.55, size.height * 0.5);
    NSArray<NSNotificationName> *leaves = @[UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification];
    if (!touchPlay) {
        // ipados_unchanged: the other modes keep 1.0.10's behaviour - the entry point has nothing to release, and a
        // finger's drag goes on holding its mouse button through a resign (its own lift, or a cancel, ends it).
        for (NSNotificationName leave in leaves) {
            AKFixtureResetInput(guest);
            AKTouchReleaseEverything();
            AKFixtureTouch *drag = AKFixtureFinger(worldPoint);
            [host touchesBegan:[NSSet setWithObject:drag] withEvent:nil];
            drag.fixturePoint = CGPointMake(worldPoint.x + 40, worldPoint.y);
            [host touchesMoved:[NSSet setWithObject:drag] withEvent:nil];
            AKDrainFixtureEvents();
            NSString *before = AKFixtureClicks(guest);
            AKFixtureLeaveApp(leave);
            AKFixtureInterruptionExpect([@"ipados_unchanged: " stringByAppendingString:leave], AKFixtureClicks(guest), before);
            assert(![AKFixtureClicks(guest) containsString:@"LeftUp"] && [[host valueForKey:@"_pressedLeft"] boolValue]);
            [host touchesEnded:[NSSet setWithObject:drag] withEvent:nil];
            AKDrainFixtureEvents();
            assert(![[host valueForKey:@"_pressedLeft"] boolValue] && ![[host valueForKey:@"_pressedRight"] boolValue]);
        }
        AKFixtureResetInput(guest);
        return;
    }
    AKFixtureEnterWorld(host);
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    AKTouchGamepad *stick = [controls valueForKey:@"_walkStick"];
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    assert(contract.areas.count == 26 && stick && overlay);
    areas.contract = contract;
    [host layoutIfNeeded];
    __block NSTimeInterval now = 700;
    areas.clock = ^NSTimeInterval { return now; };
    CGPoint walkPoint = CGPointMake(size.width * 0.25, size.height * 0.62);
    CGPoint jumpPoint = AKFixtureCentre(contract, @"jump", size);
    CGPoint spell1Point = AKFixtureCentre(contract, @"spell1", size);
    CGPoint spell2Point = AKFixtureCentre(contract, @"spell2", size);
    assert(![areas claimsPoint:worldPoint] && [areas claimsPoint:jumpPoint] && [areas claimsPoint:spell1Point]);

    for (NSNotificationName leave in leaves) {
        // background_releases_everything: Jump held, the stick auto-running, a hold ring half full, and a world
        // right-drag (turn=1) all at once; then the app leaves.
        AKFixtureResetInput(guest);
        // The stick's auto-run hold (ruling A28) on the same fixture clock.
        [overlay setValue:^NSTimeInterval { return now; } forKey:@"clock"];
        AKFixtureTouch *thumb = AKFixtureFinger(walkPoint); thumb.fixtureView = overlay;
        [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
        thumb.fixturePoint = CGPointMake(walkPoint.x, walkPoint.y - 60);
        [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
        thumb.fixturePoint = AKFixtureWalkLock(host);      // up onto the lock above the ring (ruling A34)
        [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
        now += 0.25; [overlay performSelector:@selector(tick)];   // held there until the lock is full
        [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];     // let go on it: auto-run
        AKFixtureTouch *jump = AKFixtureFinger(jumpPoint); jump.fixtureView = host;
        [host touchesBegan:[NSSet setWithObject:jump] withEvent:nil];
        AKFixtureTouch *hold = AKFixtureFinger(spell1Point); hold.fixtureView = host;
        [host touchesBegan:[NSSet setWithObject:hold] withEvent:nil];
        now += 0.30; [areas tick];
        AKFixtureTouch *drag = AKFixtureFinger(worldPoint); drag.fixtureView = host;
        [host touchesBegan:[NSSet setWithObject:drag] withEvent:nil];
        drag.fixturePoint = CGPointMake(worldPoint.x + 60, worldPoint.y);
        [host touchesMoved:[NSSet setWithObject:drag] withEvent:nil];
        AKDrainFixtureEvents();
        assert(stick.autoRunning && stick.leftStickVector.y > 0.9);
        assert([[host valueForKey:@"_pressedRight"] boolValue]);
        AKTouchHoldRing *ring = [areas holdRingForTouch:hold];
        assert(ring && ring.state == AKTouchHoldRingFilling && ring.progress > 0.2 && ring.progress < 0.9);
        assert(areas.activeFingerCount == 2);
        // Held so far: W (the stick) and Jump's V (code 9), no hold key, the right button down.
        AKFixtureInterruptionExpect(@"before leaving: keys", AKFixtureKeyPresses(guest), @"down 13 -, down 9 COS");
        assert([AKFixtureClicks(guest) hasPrefix:AKFixtureMouse(@"RightDown", worldPoint, host)]);
        [guest.keyEvents removeAllObjects];
        [guest.mouseEvents removeAllObjects];

        AKFixtureLeaveApp(leave);

        // Jump up (with its chord), the walk key up, the vector zero, auto-run off, the stick hidden...
        // (Jump's and the walk key's ups: the order between the stick's own observer and the controls' is not the point.)
        NSArray *ups = [[AKFixtureKeyPresses(guest) componentsSeparatedByString:@", "] sortedArrayUsingSelector:@selector(compare:)];
        AKFixtureInterruptionExpect([@"background_releases_everything keys: " stringByAppendingString:leave], AKFixtureJoin(ups),
                                    @"up 13 - | up 9 COS");
        assert(stick.leftStickVector.x == 0 && stick.leftStickVector.y == 0 && !stick.autoRunning && !stick.leftStickVisible);
        // ...the hold ring never completed, so no hold key (F, code 3) and no tap key (F2, code 120) went at all...
        assert(![AKFixtureKeyPresses(guest) containsString:@"down 3"] && ![AKFixtureKeyPresses(guest) containsString:@"120"]);
        assert([areas holdRingForTouch:hold] == nil && areas.activeFingerCount == 0);
        // ...the right button came up where the drag was, and nothing else was clicked.
        assert(![[host valueForKey:@"_pressedRight"] boolValue] && ![[host valueForKey:@"_pressedLeft"] boolValue]);
        assert([AKFixtureClicks(guest) hasPrefix:@"RightUp "] && ![AKFixtureClicks(guest) containsString:@"Left"]);
        // The fingers that were down lift later: nothing more is sent, no click, no key.
        [guest.keyEvents removeAllObjects];
        [guest.mouseEvents removeAllObjects];
        now += 2.0; [areas tick];
        [host touchesEnded:[NSSet setWithObject:hold] withEvent:nil];
        [host touchesEnded:[NSSet setWithObject:jump] withEvent:nil];
        [host touchesEnded:[NSSet setWithObject:drag] withEvent:nil];
        AKDrainFixtureEvents();
        AKFixtureInterruptionExpect(@"after the lifts: keys", AKFixtureKeyPresses(guest), @"");
        AKFixtureInterruptionExpect(@"after the lifts: clicks", AKFixtureClicks(guest), @"");
        assert([host valueForKey:@"_directTouch"] == nil);
        assert(![[host valueForKey:@"_directMulti"] boolValue]);

        // hold_cancelled_on_resign: a ring filling when the app leaves is gone, the hold key never goes, even if the
        // finger stays down and the clock runs on; the lift taps nothing.
        AKFixtureResetInput(guest);
        AKFixtureTouch *filling = AKFixtureFinger(spell1Point); filling.fixtureView = host;
        [host touchesBegan:[NSSet setWithObject:filling] withEvent:nil];
        now += 0.25; [areas tick];
        ring = [areas holdRingForTouch:filling];
        assert(ring && ring.state == AKTouchHoldRingFilling && ring.progress > 0 && ring.progress < 1);
        AKFixtureLeaveApp(leave);
        assert([areas holdRingForTouch:filling] == nil && ring.state == AKTouchHoldRingCancelled);
        now += 1.0; [areas tick];
        [host touchesEnded:[NSSet setWithObject:filling] withEvent:nil];
        AKDrainFixtureEvents();
        AKFixtureInterruptionExpect([@"hold_cancelled_on_resign: " stringByAppendingString:leave], AKFixtureKeyPresses(guest), @"");

        // aiming_stopped_on_resign: a spell dragged off its button is aimed (its key went at the slide); leaving stops
        // the aim with Interact's stop key (U, code 32) and the lift afterwards clicks nothing.
        AKFixtureResetInput(guest);
        AKFixtureTouch *aim = AKFixtureFinger(spell2Point); aim.fixtureView = host;
        [host touchesBegan:[NSSet setWithObject:aim] withEvent:nil];
        aim.fixturePoint = CGPointMake(spell2Point.x - 120, spell2Point.y - 120);
        [host touchesMoved:[NSSet setWithObject:aim] withEvent:nil];
        AKDrainFixtureEvents();
        AKFixtureInterruptionExpect(@"aiming: the spell's key at the slide", AKFixtureKeyPresses(guest), @"down 99 COS, up 99 COS");
        [guest.keyEvents removeAllObjects];
        [guest.mouseEvents removeAllObjects];
        AKFixtureLeaveApp(leave);
        AKFixtureInterruptionExpect([@"aiming_stopped_on_resign: " stringByAppendingString:leave], AKFixtureKeyPresses(guest), @"down 32 COS, up 32 COS");
        [host touchesEnded:[NSSet setWithObject:aim] withEvent:nil];
        AKDrainFixtureEvents();
        AKFixtureInterruptionExpect(@"aiming lift sends nothing more", AKFixtureKeyPresses(guest), @"down 32 COS, up 32 COS");
        assert(![AKFixtureClicks(guest) containsString:@"Left"]);
        assert(areas.activeFingerCount == 0);
    }

    // A pending tap (a finger down, not yet moved) waiting when the app leaves is not clicked when it lifts.
    AKFixtureResetInput(guest);
    AKFixtureTouch *pending = AKFixtureFinger(worldPoint); pending.fixtureView = host;
    [host touchesBegan:[NSSet setWithObject:pending] withEvent:nil];
    AKFixtureLeaveApp(UIApplicationWillResignActiveNotification);
    [host touchesEnded:[NSSet setWithObject:pending] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureInterruptionExpect(@"a waiting tap is not clicked after leaving", AKFixtureClicks(guest), @"");
    // ...and the next finger is an ordinary tap again.
    AKFixtureTap(host, worldPoint);
    AKFixtureInterruptionExpect(@"the next tap clicks", AKFixtureClicks(guest),
                                AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", worldPoint, host), AKFixtureMouse(@"LeftUp", worldPoint, host)]));

    // A pinch whose fingers the system never lifts (the app went away mid-pinch) leaves the host in its multi-finger
    // state with no finger down; leaving the app clears it outright, so the first tap on return is one click, not
    // swallowed.
    for (NSNotificationName leave in leaves) {
        AKFixtureResetInput(guest);
        CGPoint second = CGPointMake(worldPoint.x + 80, worldPoint.y + 30);
        AKFixtureTouch *one = AKFixtureFinger(worldPoint), *two = AKFixtureFinger(second);
        [host touchesBegan:[NSSet setWithObjects:one, two, nil] withEvent:nil];
        assert([[host valueForKey:@"_directMulti"] boolValue] && [host valueForKey:@"_directTouch"] == nil);
        AKFixtureLeaveApp(leave);
        assert(![[host valueForKey:@"_directMulti"] boolValue] && [host valueForKey:@"_directTouch"] == nil);
        AKFixtureResetInput(guest);
        AKFixtureTap(host, worldPoint);
        AKFixtureInterruptionExpect([@"the first tap after a pinch left behind: " stringByAppendingString:leave], AKFixtureClicks(guest),
                                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", worldPoint, host), AKFixtureMouse(@"LeftUp", worldPoint, host)]));
    }

    // Nothing is left held for the checks that follow.
    areas.clock = nil;
    areas.contract = nil;
    AKFixtureResetInput(guest);
    guest.keyEvents = nil; guest.mouseEvents = nil;
}

#pragma mark - The toolbar stays in the top-centre band (Task 9, run 5)

// Whether the toolbar's frame is in the top band: 8 pt below the safe area's top, its middle within a fifth of the width
// of the centre.
static BOOL AKFixtureToolbarInTopBand(UIView *host, AKTouchControls *controls) {
    CGRect frame = controls.frame;
    return fabs(CGRectGetMinY(frame) - (host.safeAreaInsets.top + 8)) < 1 && fabs(CGRectGetMidX(frame) - host.bounds.size.width / 2) <= host.bounds.size.width * 0.2 + 1;
}
static void AKFixtureExpectTopBand(UIView *host, AKTouchControls *controls, NSString *what) {
    [host layoutIfNeeded]; [controls setNeedsLayout]; [controls layoutIfNeeded];
    if (AKFixtureToolbarInTopBand(host, controls)) return;
    fprintf(stderr, "TOUCH_DOCK_MISMATCH %s: the toolbar at %s is not in the top-centre band of %s\n", what.UTF8String,
            NSStringFromCGRect(controls.frame).UTF8String, NSStringFromCGSize(host.bounds.size).UTF8String);
    assert(0);
}
// Run 5 (16 Nov, IMG_0010): with TouchPlay's info card open the add-on sent "left" (A30), the toolbar dropped to 1.0.10's
// bottom centre, opened, and its keyboard button sat over the card's "Change spell" - the tap opened the keyboard. In iPad
// touch the toolbar is always in the top-centre band: folded and open, no button list, either hand, in the world, out of
// it, with a window open (ruling A32), the keyboard up, and after a reload changes the buttons. It covers no button, a tap
// on it lands on it (never the walk stick below), a tap in the gap between its buttons or just under it reaches the game,
// and it still folds itself after 6 s.
static void AKFixtureCheckToolbarDock(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    (void)guest;
    if (!touchPlay) return;
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKFixtureEnterWorld(host);
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    AKTouchWorldSignal *signal = [controls valueForKey:@"_worldSignal"];
    UIButton *handle = [controls valueForKey:@"_toolbarHandle"];
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    assert(handle && overlay);
    NSString *text = [NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"]
                                               encoding:NSUTF8StringEncoding error:NULL];
    NSString *leftText = [text stringByReplacingOccurrencesOfString:@"hand=R" withString:@"hand=L"];
    NSDictionary *flip = @{@"BR": @"BL", @"BL": @"BR", @"TR": @"TL", @"TL": @"TR"};
    for (NSString *name in @[@"spell1", @"spell2", @"spell3", @"spell4", @"spell5", @"spell6", @"spell7", @"page1", @"page2", @"page3", @"page4",
                             @"nexttarget", @"item1", @"item2", @"item3", @"item4", @"interact", @"jump", @"dive", @"chat"])
        for (NSString *corner in flip) {
            NSString *from = [NSString stringWithFormat:@"%@,%@,", name, corner];
            if (![leftText containsString:from]) continue;
            leftText = [leftText stringByReplacingOccurrencesOfString:from withString:[NSString stringWithFormat:@"%@,%@,", name, flip[corner]]];
            break;
        }
    NSDictionary<NSString *, AKTouchContract *> *contracts = @{@"right-handed": AKTouchContractParse(text), @"left-handed": AKTouchContractParse(leftText)};
    assert(contracts.count == 2 && [contracts[@"left-handed"] leftHanded] && ![contracts[@"right-handed"] leftHanded]);
    // The fixture's window is a portrait iPad; TouchPlay's layout is for landscape, so the host is made the iPad Pro's
    // landscape size for this check (the layout units are height / 1024: here one point each) and put back after.
    CGRect savedFrame = host.frame;
    host.frame = CGRectMake(0, 0, 1366, 1024);
    [host layoutIfNeeded];
    CGSize size = host.bounds.size;
    BOOL foldedAtStart = [[controls valueForKey:@"_toolbarCollapsed"] boolValue];
    // No button list: the top centre, folded and open.
    areas.contract = nil;
    for (NSNumber *fold in @[@YES, @NO]) {
        AKFixtureSetToolbarCollapsed(controls, fold.boolValue);
        AKFixtureExpectTopBand(host, controls, fold.boolValue ? @"no button list, folded" : @"no button list, open");
        assert(fabs(CGRectGetMidX(controls.frame) - size.width / 2) < 1);
    }
    for (NSString *hand in @[@"right-handed", @"left-handed"]) {
        AKTouchContract *contract = contracts[hand];
        areas.contract = contract;
        assert(areas.liveContract == contract);
        CGFloat foldedMidX = 0;
        for (NSNumber *fold in @[@YES, @NO]) {
            AKFixtureSetToolbarCollapsed(controls, fold.boolValue);
            NSString *what = [NSString stringWithFormat:@"handle_avoids_areas (%@, %@)", hand, fold.boolValue ? @"folded" : @"open"];
            AKFixtureExpectTopBand(host, controls, what);
            CGRect frame = controls.frame;
            assert(fabs(frame.size.width - (fold.boolValue ? 96 : 208)) < 1 && fabs(frame.size.height - (fold.boolValue ? 34 : 44)) < 1);
            // Folded and open share one dock: the handle does not jump away when it opens (same centre, within rounding).
            if (fold.boolValue) foldedMidX = CGRectGetMidX(frame); else assert(fabs(CGRectGetMidX(frame) - foldedMidX) < 1.5);
            if (!CGRectContainsRect(host.bounds, frame)) { fprintf(stderr, "TOUCH_DOCK_MISMATCH off screen: %s\n", what.UTF8String); assert(0); }
            for (AKTouchArea *area in contract.areas)
                if (CGRectIntersectsRect(CGRectInset(AKTouchAreaRect(area, size), -7, -7), frame)) {
                    fprintf(stderr, "TOUCH_DOCK_MISMATCH %s overlaps %s\n", what.UTF8String, area.name.UTF8String);
                    assert(0);
                }
            // Every toolbar button takes a tap above the walk stick's layer, and none of them sits on a button.
            for (UIView *button in @[handle, [controls valueForKey:@"_keyboardButton"]]) {
                CGPoint centre = [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:host];
                UIView *hit = [host hitTest:centre withEvent:nil];
                if (hit == overlay || ![hit isDescendantOfView:controls] || [areas claimsPoint:centre]) {
                    fprintf(stderr, "TOUCH_DOCK_MISMATCH %s: a tap at %s is not the toolbar's (hit %s)\n", what.UTF8String,
                            NSStringFromCGPoint(centre).UTF8String, NSStringFromClass(hit.class).UTF8String);
                    assert(0);
                }
            }
            // A tap in the 8 pt gap after the keyboard button (before the next button), or 2 pt under the toolbar, is not
            // the toolbar's.
            UIView *keyboardButton = [controls valueForKey:@"_keyboardButton"];
            CGRect a = [controls convertRect:keyboardButton.frame toView:host];
            CGPoint gap = CGPointMake(CGRectGetMaxX(a) + 4, CGRectGetMidY(a));
            for (NSValue *value in @[[NSValue valueWithCGPoint:gap], [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(frame), CGRectGetMaxY(frame) + 2)]]) {
                UIView *hit = [host hitTest:value.CGPointValue withEvent:nil];
                if ([hit isDescendantOfView:controls]) {
                    fprintf(stderr, "TOUCH_DOCK_MISMATCH %s: a tap at %s outside its buttons is the toolbar's\n", what.UTF8String,
                            NSStringFromCGPoint(value.CGPointValue).UTF8String);
                    assert(0);
                }
            }
        }
        // The handle opens the toolbar and the toolbar folds itself again after 6 s, there.
        AKFixtureSetToolbarCollapsed(controls, YES);
        [controls toggleToolbar];
        assert(![[controls valueForKey:@"_toolbarCollapsed"] boolValue]);
        if ([hand isEqual:@"right-handed"]) {
            // The fold is the controls' own 6 s timer: it is looked at (set for 6 s, running) and fired,
            // not waited for - 6.4 s of the self-test's 30.
            NSTimer *fold = [controls valueForKey:@"_toolbarCollapseTimer"];
            assert(fold.isValid && fold.fireDate.timeIntervalSinceNow > 5.8 && fold.fireDate.timeIntervalSinceNow <= 6.0);
            [fold fire];
            assert([[controls valueForKey:@"_toolbarCollapsed"] boolValue]);
        } else {
            AKFixtureSetToolbarCollapsed(controls, YES);
        }
    }
    // Whatever the game shows, folded and open: in the world, a window open (three pulses, ruling A32), out of the world
    // (two), back in (one); and a reload that takes the chat strip away (the contract's notification, a turn later).
    areas.contract = contracts[@"right-handed"];
    NSString *noChat = [text stringByReplacingOccurrencesOfString:@"|chat,BL,296,24,568,52,CTRL-ALT-SHIFT-C,," withString:@""];
    assert(![noChat isEqualToString:text]);
    for (NSNumber *fold in @[@YES, @NO]) {
        AKFixtureSetToolbarCollapsed(controls, fold.boolValue);
        NSString *how = fold.boolValue ? @"folded" : @"open";
        AKFixtureExpectTopBand(host, controls, [@"in the world, " stringByAppendingString:how]);
        CGRect inWorld = controls.frame;
        AKFixtureWindowPulses();
        assert(signal.state == AKTouchWorldWindow && !areas.live && areas.windowOpen);
        AKFixtureExpectTopBand(host, controls, [@"a window open, " stringByAppendingString:how]);
        assert(CGRectEqualToRect(inWorld, controls.frame));     // the window does not move it at all
        AKFixtureLeaveWorldPulses();
        assert(signal.state == AKTouchWorldOut && !areas.live);
        AKFixtureExpectTopBand(host, controls, [@"out of the world, " stringByAppendingString:how]);
        assert(CGRectEqualToRect(inWorld, controls.frame));
        AKFixtureEnterWorldPulse();
        assert(areas.live);
        AKFixtureExpectTopBand(host, controls, [@"back in the world, " stringByAppendingString:how]);
        [NSNotificationCenter.defaultCenter postNotificationName:AKTouchContractDidChangeNotification object:AKTouchContractParse(noChat)];
        AKDrainFixtureEvents();
        assert(areas.contract.areas.count == 25);
        AKFixtureExpectTopBand(host, controls, [@"after a reload without the chat strip, " stringByAppendingString:how]);
        AKFixtureWindowPulses();
        AKFixtureExpectTopBand(host, controls, [@"a window open after the reload, " stringByAppendingString:how]);
        AKFixtureEnterWorldPulse();
        areas.contract = contracts[@"right-handed"];
    }
    // The keyboard up: still the top band.
    AKFixtureSetToolbarCollapsed(controls, YES);
    [controls toggleKeyboard];
    assert(controls.keyboardVisible);
    AKFixtureExpectTopBand(host, controls, @"the keyboard up");
    [controls dismissKeyboard];
    AKDrainFixtureEvents();
    areas.contract = nil;
    host.frame = savedFrame;
    AKFixtureSetToolbarCollapsed(controls, foldedAtStart);
    [host layoutIfNeeded]; [controls layoutIfNeeded];
    // The fold is a saved setting: its writes are flushed here, so the next check's "nothing written" snapshot does not
    // see this check's preferences file land late.
    [NSUserDefaults.standardUserDefaults synchronize];
    guest.keyEvents = nil; guest.mouseEvents = nil;
}

// iPad touch: a tap on TouchPlay's chat strip opens the chat keyboard (ruling A7) and sends no chord; the
// toolbar's keyboard does the same. The game's password box (secure event input, patch 0058) brings up a
// secure field iPadOS offers nothing for (ruling A41: typed by hand); what lands there is the game's key events, the field is
// empty at once, and nothing of it is in the defaults or any file. Every other mode: none of this.
static void AKFixtureCheckTextKeyboard(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    if (!touchPlay) {
        // ipados_unchanged: no bridge; the game's password box opens nothing by itself, as in 1.0.10.
        assert([controls valueForKey:@"_textBridge"] == nil);
        AKFixtureSecureInput(YES);
        assert(!controls.keyboardVisible && controls.textKind == AKTextKindNone);
        AKFixtureSecureInput(NO);
        AKDrainFixtureEvents();
        return;
    }
    AKFixtureEnterWorld(host);
    AKTouchTextBridge *bridge = [controls valueForKey:@"_textBridge"];
    assert(bridge != nil && bridge.field.superview == host && !bridge.field.userInteractionEnabled);
    UIView *composer = [controls valueForKey:@"_composer"];
    UITextView *input = [controls valueForKey:@"_keyboardInput"];
    UIButton *keyboardButton = [controls valueForKey:@"_keyboardButton"];
    AKTouchGamepad *stick = [controls valueForKey:@"_walkStick"];
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    areas.contract = contract;
    [host layoutIfNeeded];
    CGSize size = host.bounds.size;
    CGPoint chat = AKFixtureCentre(contract, @"chat", size);

    // chat_area_tap_opens_keyboard: the chat kind, no chord, no click.
    AKFixtureResetInput(guest);
    AKFixtureTap(host, chat);
    assert(controls.keyboardVisible && controls.textKind == AKTextKindChat && input.isFirstResponder && !composer.hidden);
    AKFixtureExpectKeys(@"chat strip tap", guest, @[]);
    assert(guest.mouseEvents.count == 0);
    [controls dismissKeyboard];
    assert(!controls.keyboardVisible && controls.textKind == AKTextKindNone && host.isFirstResponder);
    // toolbar_keyboard_opens_chat
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat && input.isFirstResponder);
    [controls dismissKeyboard];

    // Walking, then the chat strip: the stick lets W go as the keyboard comes up, so a typed "w" is a plain
    // w and the walk does not come back.
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    CGPoint walk = CGPointMake(size.width * 0.25, size.height * 0.62);
    AKFixtureResetInput(guest);
    AKFixtureTouch *thumb = AKFixtureFinger(walk);
    thumb.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    thumb.fixturePoint = CGPointMake(walk.x, walk.y - 50);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    AKFixtureTap(host, chat);
    assert(controls.textKind == AKTextKindChat && stick.keyboardVisible);
    [input insertText:@"w"];
    [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
    AKDrainFixtureEvents();
    [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"walk, chat strip, w, Send", guest, @[@"down 13 -", @"up 13 -", @"down 111 -", @"up 111 -", @"down 13 -", @"up 13 -",
                                                            @"down 36 -", @"up 36 -"]);
    assert(!controls.keyboardVisible && [[host valueForKey:@"_mods"] unsignedLongValue] == 0);

    // The game's password box.
    NSDictionary *defaultsBefore = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
    NSDictionary *filesBefore = AKFixtureContainerFiles();
    assert([keyboardButton.accessibilityLabel isEqual:@"Show keyboard"]);
    AKFixtureResetInput(guest);
    AKFixtureSecureInput(YES);
    // rule9_password_field_is_password_type: the field has the keyboard, the composer stays hidden, the stick stands down.
    assert(bridge.active && bridge.field.isFirstResponder && controls.keyboardVisible && controls.textKind == AKTextKindPassword);
    // Ruling A41: secure, but no content type and invisible, so iPadOS offers no saved password (no AutoFill group).
    assert(bridge.field.secureTextEntry && [bridge.field.textContentType isEqualToString:UITextContentTypeOneTimeCode] && bridge.field.alpha == 0 && !bridge.field.hidden);
    assert(composer.hidden && !input.isFirstResponder && stick.keyboardVisible);
    // rule9_autofill_forwards_and_forgets: the whole password at once, as autofill puts it.
    bridge.field.text = @"abc";
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"autofill abc", guest, @[@"down 0 -", @"up 0 -", @"down 11 -", @"up 11 -", @"down 8 -", @"up 8 -"]);
    assert(!bridge.field.text.length && !bridge.active && !controls.keyboardVisible && host.isFirstResponder && !stick.keyboardVisible);
    // The box still has the game's focus: the toolbar's keyboard offers the password again.
    assert([keyboardButton.accessibilityLabel isEqual:@"Type password"]);
    [controls toggleKeyboard];
    assert(bridge.active && controls.textKind == AKTextKindPassword && composer.hidden);
    // The app goes inactive (Control Centre, a notification, a cancelled Face ID) with the Passwords field up: the game
    // turns secure input off on resign and on again on return, and the box is still the game's focus all along. The
    // controls keep that fact (the bridge never re-confirms a field it still has open), so the toolbar's keyboard
    // button and Send still know they belong to a password.
    assert([[controls valueForKey:@"_protectedField"] boolValue]);
    AKFixtureWhileInactive(^{ AKFixturePostSecure(NO); });
    assert([[controls valueForKey:@"_protectedField"] boolValue] && bridge.active && controls.textKind == AKTextKindPassword);
    AKFixturePostSecure(YES);
    AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
    assert([[controls valueForKey:@"_protectedField"] boolValue] && bridge.active && controls.textKind == AKTextKindPassword);
    [controls dismissKeyboard];
    assert(!bridge.active && [keyboardButton.accessibilityLabel isEqual:@"Type password"]);
    [controls toggleKeyboard];
    assert(bridge.active && controls.textKind == AKTextKindPassword && !input.isFirstResponder && composer.hidden);
    // The same with the keyboard down: the field closed, the app inactive, off then on - the box keeps its focus here too.
    [controls dismissKeyboard];
    AKFixtureWhileInactive(^{ AKFixturePostSecure(NO); });
    assert([[controls valueForKey:@"_protectedField"] boolValue] && !bridge.active);
    AKFixturePostSecure(YES);
    AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
    assert([[controls valueForKey:@"_protectedField"] boolValue]);
    [controls dismissKeyboard];
    assert([keyboardButton.accessibilityLabel isEqual:@"Type password"]);
    // A guest's own request for the keyboard (Ctrl+Opt+D) while the box has focus is the Passwords field, never the plain
    // composer that would send the password as chat.
    assert(!bridge.active && !controls.keyboardVisible);
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchKeyboardRequestNotification object:nil];
    assert(bridge.active && controls.textKind == AKTextKindPassword && composer.hidden && !input.isFirstResponder);
    // Typed by hand: each key as it comes, backspace, and the player's own Return closes it.
    AKFixtureResetInput(guest);
    [bridge.field.delegate textField:bridge.field shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@"Q"];
    [bridge.field deleteBackward];
    [bridge.field.delegate textFieldShouldReturn:bridge.field];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"typed Q, backspace, Return", guest, @[@"down 12 S", @"up 12 S", @"down 51 -", @"up 51 -", @"down 36 -", @"up 36 -"]);
    assert(!bridge.active && !bridge.field.text.length);
    // A password nothing else could hold by chance: not in the defaults, not in any file of the app.
    NSString *secret = @"Tp9-Zx!qv7";
    [controls toggleKeyboard];
    bridge.field.text = secret;
    AKDrainFixtureEvents();
    assert(!bridge.active && !bridge.field.text.length);
    assert([NSUserDefaults.standardUserDefaults.dictionaryRepresentation isEqualToDictionary:defaultsBefore]);
    NSDictionary *filesAfter = AKFixtureContainerFiles();
    if (![filesAfter isEqualToDictionary:filesBefore]) {
        for (NSString *file in [NSSet setWithArray:[filesBefore.allKeys arrayByAddingObjectsFromArray:filesAfter.allKeys]])
            if (![filesBefore[file] isEqual:filesAfter[file]])
                fprintf(stderr, "TOUCH_TEXT_HOST: container changed: %s (%s -> %s)\n", file.UTF8String,
                        [filesBefore[file] UTF8String] ?: "none", [filesAfter[file] UTF8String] ?: "none");
        assert(0);
    }
    assert(!AKFixtureContainerHolds(secret));
    // The box loses focus (the app active): the field closes. Back to the plain keyboard button.
    [controls toggleKeyboard];
    assert(bridge.active);
    AKFixtureSecureInput(NO);
    assert(!bridge.active && !controls.keyboardVisible && host.isFirstResponder);
    assert([keyboardButton.accessibilityLabel isEqual:@"Show keyboard"]);
    // The chat composer is up when the game's password box takes focus: the password field takes over.
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat);
    AKFixtureSecureInput(YES);
    assert(controls.textKind == AKTextKindPassword && !input.isFirstResponder && composer.hidden);
    // Going to the background closes it.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    assert(!bridge.active && !controls.keyboardVisible);
    AKFixtureSecureInput(NO);
    AKDrainFixtureEvents();
    [host becomeFirstResponder];
    areas.contract = nil;
    guest.keyEvents = nil;
    guest.mouseEvents = nil;
}

// How many times the game's view took first responder: a keyboard handed from the composer to the password
// field (or back) must not pass through it, which would hide the keyboard and show it again.
static int gHostBecame;
static IMP gHostBecomeOriginal;
static BOOL AKFixtureCountingBecome(id self, SEL _cmd) {
    gHostBecame++;
    return ((BOOL (*)(id, SEL))gHostBecomeOriginal)(self, _cmd);
}
static void AKFixtureCountHostBecome(UIView *host) {
    if (gHostBecomeOriginal) return;
    Class cls = host.class;
    SEL sel = @selector(becomeFirstResponder);
    gHostBecomeOriginal = class_getMethodImplementation(cls, sel);
    const char *types = method_getTypeEncoding(class_getInstanceMethod(cls, sel));
    if (!class_addMethod(cls, sel, (IMP)AKFixtureCountingBecome, types))
        method_setImplementation(class_getInstanceMethod(cls, sel), (IMP)AKFixtureCountingBecome);
}
static void AKFixtureTapButton(UIView *button) {
    assert([button isKindOfClass:UIButton.class]);
    [(UIButton *)button sendActionsForControlEvents:UIControlEventTouchUpInside];
}

// Fix round 1 (rulings A23, A24, A25). Mockup 82: chips choose where the line goes (a slash line), a gold Send,
// a world tap closes the keyboard and sends nothing. Mockups 26-28: the password field is real-size over the box
// and the game slides up with the keyboard. The keyboard passes between the composer and the field without
// going down. While the game's password box has focus, the chat strip opens the password field, never the chat.
static void AKFixtureCheckChatAndSignIn(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    UIView *composer = [controls valueForKey:@"_composer"];
    [host layoutIfNeeded];
    if (!touchPlay) {
        // Every other mode: the accessory row of 1.0.10 (Esc first), Replace, no Send, no gate, no slide.
        [controls toggleKeyboard];
        UIStackView *row = (UIStackView *)controls.inputAccessoryView;
        assert([[(UIButton *)row.arrangedSubviews.firstObject titleForState:UIControlStateNormal] isEqual:@"Esc"]);
        assert(AKFindInputView(row, @"wolkaraforever.chat.party") == nil);
        UIView *send = AKFindInputView(composer, @"wolkaraforever.keyboard.send");
        assert(send == nil || send.hidden);
        assert(!AKFindInputView(composer, @"wolkaraforever.keyboard.insert").hidden);
        assert(AKFindInputView(host, @"wolkaraforever.keyboard.gate") == nil);
        [controls dismissKeyboard];
        AKFixtureSecureInput(YES);
        assert(CGAffineTransformIsIdentity(host.transform));
        AKFixtureSecureInput(NO);
        AKDrainFixtureEvents();
        return;
    }
    AKTouchTextBridge *bridge = [controls valueForKey:@"_textBridge"];
    UITextView *input = [controls valueForKey:@"_keyboardInput"];
    // The login screen's account box (17 Nov 2026: Return there pressed Login with no password). Out of the world,
    // with the password box seen since the player was last in it (here: the box with a remembered account, then a tap on
    // the account box), the composer types into the game's account box: its Return reads Next and is Tab - to the
    // password box - never Return, and no chat key.
    AKFixtureUseClocks(controls);
    if ([(AKTouchWorldSignal *)[controls valueForKey:@"_worldSignal"] state] != AKTouchWorldOut) AKFixtureLeaveWorldPulses();
    AKFixtureSecureInput(YES);
    AKFixtureSecureInput(NO);
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat && input.returnKeyType == UIReturnKeyNext);
    AKFixtureResetInput(guest);
    [input insertText:@"ab"];
    [input insertText:@"\n"];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"the login's account box: ab, Return is Tab", guest, @[@"down 0 -", @"up 0 -", @"down 11 -", @"up 11 -", @"down 48 -", @"up 48 -"]);
    assert(!controls.keyboardVisible);
    // In the world the composer is the chat's again (Send); back out at the character list with no password box since,
    // Return is Return again.
    AKFixtureEnterWorld(host);
    [controls toggleKeyboard];
    assert(input.returnKeyType == UIReturnKeySend);
    [controls dismissKeyboard];
    AKFixtureLeaveWorldPulses();
    [controls toggleKeyboard];
    assert(input.returnKeyType == UIReturnKeySend);
    AKFixtureResetInput(guest);
    [input insertText:@"\n"];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"the character list: a bare Return", guest, @[@"down 36 -", @"up 36 -"]);
    [controls dismissKeyboard];   // nothing typed: Return is just Return, and the keyboard stays (as it always has)
    AKFixtureEnterWorld(host);
    UILabel *label = [controls valueForKey:@"_composerLabel"];
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    areas.contract = contract;
    [host layoutIfNeeded];
    CGSize size = host.bounds.size;
    CGPoint chat = AKFixtureCentre(contract, @"chat", size);
    CGRect windowBounds = host.superview.bounds;

    // Chips (A25): Say, Party, Guild, Whisper, Yell above the keys; a chosen chip makes the line a slash line.
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat);
    UIView *row = controls.inputAccessoryView;
    NSArray *ids = @[@"say", @"party", @"guild", @"whisper", @"yell"], *titles = @[@"Say", @"Party", @"Guild", @"Whisper", @"Yell"];
    for (NSUInteger i = 0; i < ids.count; i++) {
        UIButton *chip = (UIButton *)AKFindInputView(row, [@"wolkaraforever.chat." stringByAppendingString:ids[i]]);
        assert([chip isKindOfClass:UIButton.class] && [[chip titleForState:UIControlStateNormal] isEqual:titles[i]] && !chip.selected && chip.enabled);
    }
    UIButton *send = (UIButton *)AKFindInputView(composer, @"wolkaraforever.keyboard.send");
    assert([send isKindOfClass:UIButton.class] && !send.hidden && [[send titleForState:UIControlStateNormal] isEqual:@"Send"]);
    assert(AKFindInputView(composer, @"wolkaraforever.keyboard.insert").hidden);
    // 1.0.10's keys stay under the chips (Tab and Esc move between the game's own fields).
    assert([AKFindInputView(row, @"wolkaraforever.keyboard.key.0") isKindOfClass:UIButton.class]);
    UIButton *party = (UIButton *)AKFindInputView(row, @"wolkaraforever.chat.party");
    UIButton *whisper = (UIButton *)AKFindInputView(row, @"wolkaraforever.chat.whisper");
    AKFixtureTapButton(party);
    assert(party.selected && [label.text isEqual:@"Party"]);
    AKFixtureResetInput(guest);
    [input insertText:@"hi"];
    AKFixtureTapButton(send);
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"Party chip, hi, Send", guest, @[@"down 44 -", @"up 44 -", @"down 35 -", @"up 35 -", @"down 49 -", @"up 49 -",
        @"down 4 -", @"up 4 -", @"down 34 -", @"up 34 -", @"down 36 -", @"up 36 -"]);
    assert(!controls.keyboardVisible);
    // Whisper is the reply to the last whisper (/r): the app cannot read names. One chip at a time.
    [controls toggleKeyboard];
    assert(party.selected && [label.text isEqual:@"Party"]);
    AKFixtureTapButton(whisper);
    assert(whisper.selected && !party.selected && [label.text isEqual:@"Whisper"]);
    AKFixtureResetInput(guest);
    [input insertText:@"ok"];
    [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"Whisper chip, ok, Return key", guest, @[@"down 44 -", @"up 44 -", @"down 15 -", @"up 15 -", @"down 49 -", @"up 49 -",
        @"down 31 -", @"up 31 -", @"down 40 -", @"up 40 -", @"down 36 -", @"up 36 -"]);
    assert(!controls.keyboardVisible);
    // The chosen chip tapped again: back to the game's own channel (F12 opens the chat on it).
    [controls toggleKeyboard];
    AKFixtureTapButton(whisper);
    assert(!whisper.selected && ![label.text isEqual:@"Whisper"]);
    AKFixtureResetInput(guest);
    [input insertText:@"yo"];
    AKFixtureTapButton(send);
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"no chip, yo, Send", guest, @[@"down 111 -", @"up 111 -", @"down 16 -", @"up 16 -", @"down 31 -", @"up 31 -",
        @"down 36 -", @"up 36 -"]);
    // The keyboard's own Return (17 Nov 2026: "only our Send button sends"): it reads Send and does exactly what
    // Send does, whichever way the keyboard delivers it - a newline typed into the draft, or one that lands in it by a
    // path that skips the text view's delegate - and the keyboard closes as Send closes it.
    NSArray *yoSent = @[@"down 111 -", @"up 111 -", @"down 16 -", @"up 16 -", @"down 31 -", @"up 31 -", @"down 36 -", @"up 36 -"];
    [controls toggleKeyboard];
    assert(input.returnKeyType == UIReturnKeySend);
    AKFixtureResetInput(guest);
    [input insertText:@"yo"];
    [input insertText:@"\n"];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"no chip, yo, the keyboard's Return", guest, yoSent);
    assert(!controls.keyboardVisible);
    [controls toggleKeyboard];
    AKFixtureResetInput(guest);
    [input insertText:@"yo"];
    input.text = @"yo\n";
    [input.delegate textViewDidChange:input];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"no chip, yo, a newline past the delegate", guest, yoSent);
    assert(!controls.keyboardVisible && input.text.length == 0);

    // A world tap while the chat keyboard is up closes it and sends nothing (A25); the toolbar and the composer
    // still take their own taps.
    [controls toggleKeyboard];
    [host layoutIfNeeded];
    UIView *gate = AKFindInputView(host, @"wolkaraforever.keyboard.gate");
    assert(gate != nil && gate.superview == host);
    CGPoint world = CGPointMake(size.width * 0.6, size.height * 0.3);
    assert(![areas claimsPoint:world]);
    assert([host hitTest:world withEvent:nil] == gate);
    CGRect bar = controls.frame;
    assert([[host hitTest:CGPointMake(CGRectGetMinX(bar) + 10, CGRectGetMidY(bar)) withEvent:nil] isDescendantOfView:controls]);
    assert([[host hitTest:CGPointMake(CGRectGetMidX(composer.frame), CGRectGetMidY(composer.frame)) withEvent:nil] isDescendantOfView:composer]);
    AKFixtureResetInput(guest);
    AKFixtureTouch *tap = AKFixtureFinger(world);
    tap.fixtureView = gate;
    [gate touchesBegan:[NSSet setWithObject:tap] withEvent:nil];
    [gate touchesEnded:[NSSet setWithObject:tap] withEvent:nil];
    AKDrainFixtureEvents();
    assert(!controls.keyboardVisible && guest.keyEvents.count == 0 && guest.mouseEvents.count == 0);
    assert([host hitTest:world withEvent:nil] == host);

    // The keyboard passes from the password field to the composer, and back, without the game's view taking it.
    AKFixtureCountHostBecome(host);
    [bridge beginForKind:AKTextKindPassword];   // the field up with the box not focused (Face ID's inactive moment)
    assert(bridge.active);
    gHostBecame = 0;
    AKFixtureTap(host, chat);
    assert(controls.textKind == AKTextKindChat && input.isFirstResponder && !bridge.active);
    assert(gHostBecame == 0);
    AKFixtureSecureInput(YES);
    assert(controls.textKind == AKTextKindPassword && !input.isFirstResponder && composer.hidden);
    assert(gHostBecame == 0);

    // The game slides up with the password keyboard (A23): the box stays above the keys, the field sits on it,
    // the toolbar stays on screen, and a world tap is the game's (no gate).
    CGFloat slide = round(size.height * AKTouchPasswordSlideFraction);
    assert(fabs(host.transform.ty + slide) < 0.5 && host.transform.tx == 0 && host.transform.a == 1 && host.transform.d == 1);
    assert(CGSizeEqualToSize(bridge.field.bounds.size, AKTouchPasswordFieldSize) && bridge.field.undoManager == nil);
    // Text reaching the field past its setter and delegate (another UITextInput path) goes on the real editing-changed
    // event (A23, I3): sent, the field emptied.
    AKFixtureResetInput(guest);
    void (*plainSetText)(id, SEL, NSString *) = (void (*)(id, SEL, NSString *))class_getMethodImplementation(UITextField.class, @selector(setText:));
    plainSetText(bridge.field, @selector(setText:), @"q");
    [bridge.field sendActionsForControlEvents:UIControlEventEditingChanged];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"editing changed", guest, @[@"down 12 -", @"up 12 -"]);
    assert(!bridge.field.text.length && bridge.active);
    assert(fabs(bridge.field.center.x - size.width / 2) < 1 && fabs(bridge.field.center.y - size.height * AKTouchPasswordBoxCentre.y) < 1);
    CGRect onScreen = [host convertRect:controls.frame toView:host.superview];
    assert(fabs(CGRectGetMinY(onScreen) - (host.safeAreaInsets.top + 8)) < 1);
    assert([host hitTest:world withEvent:nil] != gate);
    // The chat strip while the box has focus (A24, interim): the password field again, never the cleartext composer.
    [controls dismissKeyboard];
    assert(!bridge.active && CGAffineTransformIsIdentity(host.transform) && CGRectEqualToRect(host.frame, windowBounds));
    // The password box also took the world away (a real box is not the add-on's pulse), so the strip is not a button
    // now; the interim guard still holds if it were (the add-on pulsing while the box has focus).
    assert(!areas.live);
    areas.live = YES;
    AKFixtureTap(host, chat);
    assert(controls.textKind == AKTextKindPassword && !input.isFirstResponder && composer.hidden);
    AKFixtureSecureInput(NO);
    assert(!bridge.active && CGAffineTransformIsIdentity(host.transform) && CGRectEqualToRect(host.frame, windowBounds));
    // The chat keyboard does not slide the game.
    AKFixtureEnterWorld(host);
    AKFixtureTap(host, chat);
    assert(controls.textKind == AKTextKindChat && CGAffineTransformIsIdentity(host.transform));
    [controls dismissKeyboard];
    AKDrainFixtureEvents();
    [host becomeFirstResponder];
    areas.contract = nil;
    guest.keyEvents = nil;
    guest.mouseEvents = nil;
}

#pragma mark - AutoFill through Face ID (device fix 2)

// iPad run 2 (16 Nov, build 4b9391c): the Passwords suggestion filled nothing, and afterwards the keyboard could not be
// opened again. Two things the fixture never modelled before:
//   - Face ID's sheet resigns the app in the middle of every fill, and the game turns secure input off *inside*
//     UIApplicationWillResignActiveNotification (the adapter's NSApp hands it the resign synchronously). At that moment
//     UIApplication.applicationState still reads Active; only the scene is already foregroundInactive (measured in the
//     simulator: UISceneWillDeactivate, then WillResignActive with applicationState 0 and the scene's state 1).
//   - iOS hands the credential over after Face ID, through UIKit's own completion
//     (-[UIKeyboardHiddenViewController_Autofill passwordViewController:selectedCredential:] ->
//     -[_UIKeyboardStateManager processPayloadInfo:]): it goes to the text input that has the keyboard then, or, if none
//     has, to the password field of the autofill group, which UIKit asks to take the keyboard first.
// The fixture drives that real UIKit completion with a fixture credential; nothing else of AutoFill can run here.
// Ruling A41 (18 Nov 2026, a Face ID fill ended in "You have been disconnected"): no AutoFill. The field is a one-time
// code's, so the same completion now types nothing - proof that UIKit no longer takes it for a password field. The
// resign handling stays: Control Centre and notifications resign the app with the field up too.
@interface AKFixtureCredential : NSObject
@property (nonatomic, copy) NSString *user, *password;
@end
@implementation AKFixtureCredential
@end
static void AKFixtureAutofill(NSString *password) {
    Class hidden = NSClassFromString(@"UIKeyboardHiddenViewController_Autofill");
    SEL selected = NSSelectorFromString(@"passwordViewController:selectedCredential:");
    if (!hidden || ![hidden instancesRespondToSelector:selected]) {
        fprintf(stderr, "TOUCH_AUTOFILL: this UIKit has no %s; the AutoFill checks cannot run\n", sel_getName(selected));
        assert(0);
    }
    AKFixtureCredential *credential = [AKFixtureCredential new];
    credential.user = @"player@example.com";
    credential.password = password;
    id controller = [hidden new];
    ((void (*)(id, SEL, id, id))objc_msgSend)(controller, selected, nil, credential);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    AKDrainFixtureEvents();
}
// Face ID's sheet (or Control Centre) comes up: the scene goes foregroundInactive and WillResignActive is posted while
// applicationState still reads Active. `during` is what the game does inside that notification.
// (UIKit derives applicationState from the scenes, so it is held at the value the iPad reads then.)
static IMP gSceneStateOriginal, gAppStateOriginal;
static void AKFixtureResign(void (^during)(void)) {
    Method method = class_getInstanceMethod(UIScene.class, @selector(activationState));
    gSceneStateOriginal = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^UISceneActivationState(id scene) { (void)scene; return UISceneActivationStateForegroundInactive; }));
    Method app = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    gAppStateOriginal = method_getImplementation(app);
    method_setImplementation(app, imp_implementationWithBlock(^UIApplicationState(id application) { (void)application; return UIApplicationStateActive; }));
    UIScene *scene = UIApplication.sharedApplication.connectedScenes.anyObject;
    [NSNotificationCenter.defaultCenter postNotificationName:UISceneWillDeactivateNotification object:scene];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
                                                              usingBlock:^(NSNotification *note) { (void)note; if (during) during(); }];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    AKDrainFixtureEvents();
}
// ...and goes away again: the app is active.
static void AKFixtureReturn(void) {
    method_setImplementation(class_getInstanceMethod(UIScene.class, @selector(activationState)), gSceneStateOriginal);
    method_setImplementation(class_getInstanceMethod(UIApplication.class, @selector(applicationState)), gAppStateOriginal);
    UIScene *scene = UIApplication.sharedApplication.connectedScenes.anyObject;
    [NSNotificationCenter.defaultCenter postNotificationName:UISceneDidActivateNotification object:scene];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    AKDrainFixtureEvents();
}
static NSUInteger AKFixtureKeyDowns(AKInputFixtureView *guest) {
    NSUInteger downs = 0;
    for (NSString *event in guest.keyEvents) if ([event hasPrefix:@"down"]) downs++;
    return downs;
}
static BOOL AKFixtureProtected(AKTouchControls *controls) { return [[controls valueForKey:@"_protectedField"] boolValue]; }

static void AKFixtureCheckAutofill(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    if (!touchPlay) return;   // no bridge, no Passwords field: AKFixtureCheckTextKeyboard covers every other mode
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKFixtureUseClocks(controls);
    AKTouchTextBridge *bridge = [controls valueForKey:@"_textBridge"];
    UITextView *input = [controls valueForKey:@"_keyboardInput"];
    UIButton *keyboardButton = [controls valueForKey:@"_keyboardButton"];
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    areas.contract = contract;
    [host layoutIfNeeded];
    CGPoint chat = AKFixtureCentre(contract, @"chat", host.bounds.size);
    if (areas.live) AKFixtureLeaveWorldPulses();   // the login screen

    // 1. The app resigns with the field up (Control Centre, a notification; before ruling A41 also Face ID's sheet): the
    //    game turns secure input off inside the resign. The box keeps its focus, so the field stays up and ready.
    AKFixtureResetInput(guest);
    AKFixtureSecureInput(YES);
    assert(bridge.active && controls.textKind == AKTextKindPassword && AKFixtureProtected(controls));
    AKFixtureResign(^{ AKFixturePostSecure(NO); });
    if (!(bridge.kind == AKTextKindPassword && bridge.active && AKFixtureProtected(controls))) {
        fprintf(stderr, "TOUCH_AUTOFILL_MISMATCH resign with the field up: kind %ld active %d protected %d (the resign's off closed the field)\n",
                (long)bridge.kind, bridge.active, AKFixtureProtected(controls));
        assert(0);
    }
    AKFixtureReturn();
    AKFixturePostSecure(YES);   // the game, active again: its box still has focus
    AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
    assert(bridge.active && controls.textKind == AKTextKindPassword);
    // Ruling A41 (no AutoFill): the field is a one-time code's, never a password's, so even UIKit's own credential
    // completion, with the field holding the keyboard, types nothing into the game (before A41 it typed "abc").
    AKFixtureAutofill(@"abc");
    AKFixtureExpectKeys(@"a credential handed to the field (A41: nothing)", guest, @[]);
    assert(bridge.active && bridge.kind == AKTextKindPassword && !bridge.field.text.length);
    assert(!input.isFirstResponder && !input.text.length);
    // Typed by hand instead: each key goes as it is typed.
    [bridge.field.delegate textField:bridge.field shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@"a"];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"typed by hand after a resign", guest, @[@"down 0 -", @"up 0 -"]);
    [controls dismissKeyboard];
    assert(!bridge.active && [keyboardButton.accessibilityLabel isEqual:@"Type password"]);

    // 2. Ruling A41 (no AutoFill): the window has no password field for AutoFill, so a credential that UIKit hands over
    //    with no text input holding the keyboard has nowhere to go - nothing reaches the game, nor the chat draft.
    //    (Before A41 iOS asked the field to take the keyboard back and typed it: 10 key downs.) Rule 9's test password,
    //    so the log check also covers UIKit's own path.
    [controls toggleKeyboard];
    assert(bridge.active && controls.textKind == AKTextKindPassword);
    AKFixtureResetInput(guest);
    [bridge.field resignFirstResponder];
    assert(bridge.kind == AKTextKindPassword && !bridge.active && !controls.keyboardVisible && CGAffineTransformIsIdentity(host.transform));
    AKFixtureAutofill(@"Tp9-Zx!qv7");
    if (AKFixtureKeyDowns(guest) != 0 || bridge.active || input.isFirstResponder || input.text.length) {
        fprintf(stderr, "TOUCH_AUTOFILL_MISMATCH no AutoFill group (A41): %lu key downs, field active %d, draft %d/%lu\n",
                (unsigned long)AKFixtureKeyDowns(guest), bridge.active, input.isFirstResponder, (unsigned long)input.text.length);
        assert(0);
    }
    assert(!bridge.field.text.length && !controls.keyboardVisible);

    // 3. Face ID fails or the sheet is cancelled: no fill. The field is still the box's; the keyboard button closes and
    //    reopens it, and typing by hand works.
    AKFixturePostSecure(NO);    // the player logged in by hand meanwhile; a new login screen:
    AKFixtureSecureInput(YES);
    assert(bridge.active);
    AKFixtureResign(^{ AKFixturePostSecure(NO); });
    AKFixtureReturn();
    AKFixturePostSecure(YES);
    AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
    assert(bridge.active && controls.textKind == AKTextKindPassword);
    [controls toggleKeyboard];
    assert(!controls.keyboardVisible && [keyboardButton.accessibilityLabel isEqual:@"Type password"]);
    [controls toggleKeyboard];
    assert(bridge.active && controls.textKind == AKTextKindPassword);
    [bridge.field resignFirstResponder];   // the sheet took the keyboard and was cancelled
    [controls toggleKeyboard];
    assert(bridge.active && controls.textKind == AKTextKindPassword);
    AKFixtureResetInput(guest);
    [bridge.field.delegate textField:bridge.field shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@"a"];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"typed by hand after a cancelled sheet", guest, @[@"down 0 -", @"up 0 -"]);

    // 4. The game closes the box while the sheet is up (the app active: a real loss of focus). The field closes and a
    //    fill that comes after goes nowhere - never to whatever has the game's focus now. The keyboard opens as the chat.
    [bridge.field resignFirstResponder];
    AKFixturePostSecure(NO);
    assert(bridge.kind == AKTextKindNone && !bridge.active && !AKFixtureProtected(controls));
    AKFixtureResetInput(guest);
    AKFixtureAutofill(@"abc");
    AKFixtureExpectKeys(@"a fill after the box closed", guest, @[]);
    // ...nor to the chat draft: UIKit asks the login group's other text inputs to take the account name, and the draft
    // editor is one of them in the window. It is never opened by anyone but its owner.
    if (input.isFirstResponder || input.text.length || controls.keyboardVisible) {
        fprintf(stderr, "TOUCH_AUTOFILL_MISMATCH a fill after the box closed opened the chat draft (%lu characters in it)\n", (unsigned long)input.text.length);
        assert(0);
    }
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat && input.isFirstResponder && !bridge.active);
    [controls dismissKeyboard];

    // 5. The excerpt's last turn: secure input on for 1.7 s (the timer had not run: the clock moves, nothing settles), then
    //    the resign's off. Nothing opens while the app is away, and nothing stale is left: if the game does not ask
    //    again, the keyboard button and the chat strip open the chat.
    AKFixturePostSecure(YES);
    gFixtureNow += 1.7;
    AKFixtureResign(^{ AKFixturePostSecure(NO); });
    if (bridge.active || controls.keyboardVisible) {
        fprintf(stderr, "TOUCH_AUTOFILL_MISMATCH a field opened while the app was inactive\n");
        assert(0);
    }
    AKFixtureReturn();
    AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
    if (controls.keyboardVisible || AKFixtureProtected(controls)) {
        fprintf(stderr, "TOUCH_AUTOFILL_MISMATCH after the excerpt's resign: keyboard %d protected %d\n", controls.keyboardVisible, AKFixtureProtected(controls));
        assert(0);
    }
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat && input.isFirstResponder);
    [controls dismissKeyboard];
    // ...and if it does ask again, the field opens once the app is active.
    AKFixturePostSecure(YES);
    gFixtureNow += 1.7;
    AKFixtureResign(^{ AKFixturePostSecure(NO); });
    AKFixtureReturn();
    AKFixturePostSecure(YES);
    AKFixtureAdvance(AKTouchPasswordInWorldSeconds + 0.1);
    assert(bridge.active && controls.textKind == AKTextKindPassword && AKFixtureProtected(controls));
    AKFixturePostSecure(NO);
    assert(!bridge.active && !AKFixtureProtected(controls));

    // 6. Self-heal: whatever stale password state is left (here: the box's focus remembered after the game let go of
    //    secure input), the player's own tap ends it and opens the right keyboard - the chat strip in the world and the
    //    toolbar's button alike.
    AKFixtureEnterWorld(host);
    [controls setValue:@YES forKey:@"_protectedField"];
    [bridge beginForKind:AKTextKindPassword];
    [bridge.field resignFirstResponder];
    AKFixtureTap(host, chat);
    if (controls.textKind != AKTextKindChat || !input.isFirstResponder) {
        fprintf(stderr, "TOUCH_AUTOFILL_MISMATCH stale password state: the chat strip opened kind %ld\n", (long)controls.textKind);
        assert(0);
    }
    assert(!AKFixtureProtected(controls) && bridge.kind == AKTextKindNone);
    [controls dismissKeyboard];
    [controls setValue:@YES forKey:@"_protectedField"];
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat && input.isFirstResponder && !AKFixtureProtected(controls));
    [controls dismissKeyboard];
    AKDrainFixtureEvents();
    [host becomeFirstResponder];
    areas.contract = nil;
    guest.keyEvents = nil;
    guest.mouseEvents = nil;
}

#pragma mark - The in-world gate (ruling A24)

// The add-on's secure-input pulses tell the app the player is in the world; until then TouchPlay's buttons are not
// on screen and every touch is 1.0.10's plain touch. A game start is out of the world. One short pulse enters it,
// two leave it, a password box (secure input held) is not it, and a pulse never opens the password keyboard or
// touches the chat composer. Time is the fixture clock. Every other mode: no signal, nothing changes.
static void AKFixtureCheckWorldGate(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    if (!touchPlay) {
        assert([controls valueForKey:@"_worldSignal"] == nil && [host valueForKey:@"_touchAreas"] == nil);
        return;
    }
    AKTouchWorldSignal *signal = [controls valueForKey:@"_worldSignal"];
    AKTouchTextBridge *bridge = [controls valueForKey:@"_textBridge"];
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    assert(signal != nil && bridge != nil && areas != nil);
    AKFixtureUseClocks(controls);
    UIView *composer = [controls valueForKey:@"_composer"];
    UITextView *input = [controls valueForKey:@"_keyboardInput"];
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    CGSize size = host.bounds.size;
    CGPoint walk = CGPointMake(size.width * 0.25, size.height * 0.62);
    [host layoutIfNeeded];

    // game_start_is_not_in_the_world, no notice with live NO.
    assert(!signal.inWorld && !areas.live);
    assert(AKFindInputView(host, @"wolkaraforever.touch.contractMissing") == nil && areas.missingNotice == nil);

    // The A17 notice waits for the world: this game has no button list, and the entering pulse - not the game start -
    // is what shows it (once; it never takes a touch).
    AKFixtureEnterWorldPulse();
    UIView *notice = AKFindInputView(host, @"wolkaraforever.touch.contractMissing");
    assert(areas.live && notice != nil && !notice.userInteractionEnabled && !notice.hidden);
    AKFixtureLeaveWorldPulses();
    assert(!areas.live && !signal.inWorld);

    // Live NO with the button list loaded: plain 1.0.10 touches. A tap on a spell button is a click (no chord), the
    // walk area is a world touch (no stick, no W), and the world is 1.0.8's: a hold right clicks, two taps are two
    // left clicks, the edge clicks, a drag is a left drag - whatever the contract's turn and world key say.
    areas.contract = contract;
    [host layoutIfNeeded];
    assert(contract.turnWithView && contract.worldKey.length);
    CGPoint spell = AKFixtureCentre(contract, @"spell2", size);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, spell);
    AKFixtureExpect(@"live NO: a tap on a spell button is a plain click", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", spell, host), AKFixtureMouse(@"LeftUp", spell, host)]));
    assert(guest.keyEvents.count == 0 && areas.activeFingerCount == 0 && ![areas claimsPoint:spell]);
    assert([host hitTest:walk withEvent:nil] == host && [overlay hitTest:walk withEvent:nil] == nil);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, walk);
    AKFixtureExpect(@"live NO: the walk area is a world touch", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", walk, host), AKFixtureMouse(@"LeftUp", walk, host)]));
    assert(guest.keyEvents.count == 0);
    AKFixtureCheckWorld108(host, guest);
    // The pinch takes a finger on a button's place and in the edge zone, as 1.0.8's does.
    UIPinchGestureRecognizer *pinch = [host valueForKey:@"_pinch"];
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:AKFixtureFinger(spell)]);
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:AKFixtureFinger(CGPointMake(10, 500))]);
    // The chat strip is not a button here: a tap on it is a click, and the keyboard does not open.
    CGPoint chat = AKFixtureCentre(contract, @"chat", size);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, chat);
    assert(!controls.keyboardVisible && guest.keyEvents.count == 0);

    // single_pulse_enters_the_world: one short pulse; nothing is decided until the group window has closed.
    AKFixturePulse();
    assert(!areas.live);
    AKFixtureAdvance(0.7);
    assert(signal.inWorld && areas.live);
    // live YES: as today - a tap on a spell is its chord, the walk area is the stick's, the second tap right clicks.
    AKFixtureResetInput(guest);
    AKFixtureTap(host, spell);
    AKFixtureExpect(@"live YES: spell2's chord", AKFixtureJoin(guest.keyEvents), AKFixtureJoin(AKFixtureChordTap(99)));
    assert(AKFixtureClicks(guest).length == 0);
    assert([host hitTest:walk withEvent:nil] == overlay);
    CGPoint a = CGPointMake(500, 400), b = CGPointMake(520, 410);
    __block NSTimeInterval now = 1000;
    areas.clock = ^NSTimeInterval { return now; };
    AKFixtureResetInput(guest);
    AKFixtureTap(host, a);
    now += 0.4;
    AKFixtureTap(host, b);
    AKFixtureExpect(@"live YES: the second tap right clicks", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", a, host), AKFixtureMouse(@"LeftUp", a, host),
                                    AKFixtureMouse(@"RightDown", b, host), AKFixtureMouse(@"RightUp", b, host)]));
    areas.clock = nil;

    // double_pulse_leaves_the_world, with a thumb walking: W goes up as the buttons go (no W running into the next
    // screen), and the lift after it is nothing.
    AKFixtureResetInput(guest);
    AKFixtureTouch *thumb = AKFixtureFinger(walk);
    thumb.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    thumb.fixturePoint = CGPointMake(walk.x, walk.y - 50);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"walking", guest, @[@"down 13 -"]);
    AKFixtureLeaveWorldPulses();
    AKDrainFixtureEvents();
    assert(!signal.inWorld && !areas.live);
    AKFixtureExpectKeys(@"left the world while walking", guest, @[@"down 13 -", @"up 13 -"]);
    [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"the lift adds nothing", guest, @[@"down 13 -", @"up 13 -"]);
    assert([host hitTest:walk withEvent:nil] == host);

    // A pulse never opens the password keyboard, never touches the chat composer, and is never typing.
    AKFixtureResetInput(guest);
    [controls toggleKeyboard];
    assert(controls.textKind == AKTextKindChat && input.isFirstResponder && !composer.hidden);
    for (int pulse = 0; pulse < 2; pulse++) {
        if (pulse == 0) AKFixtureEnterWorldPulse(); else AKFixtureLeaveWorldPulses();
        assert(!bridge.active && controls.textKind == AKTextKindChat && input.isFirstResponder && !composer.hidden);
        assert(CGAffineTransformIsIdentity(host.transform));
    }
    [input insertText:@"x"];
    assert([input.text hasSuffix:@"x"]);   // the pulses did not touch the draft
    [controls dismissKeyboard];
    AKDrainFixtureEvents();
    assert(guest.keyEvents.count == 0 && guest.mouseEvents.count == 0);
    assert(!bridge.active && controls.textKind == AKTextKindNone && !areas.live);   // entering then leaving: out again
    AKFixtureEnterWorldPulse();
    assert(areas.live);
    // The toolbar's keyboard button still says "Show keyboard": the pulses did not look like the password box.
    assert([[(UIButton *)[controls valueForKey:@"_keyboardButton"] accessibilityLabel] isEqual:@"Show keyboard"]);

    // Ruling A27, in the world: a secure input that is neither a pulse nor a real box (a loading screen stretched the
    // add-on's pulse to 0.5 s) opens no field and keeps the world - the buttons stay live, the toolbar's keyboard
    // button is the plain one, and the chat composer is left alone.
    assert(areas.live && signal.inWorld);
    AKFixturePostSecure(YES);
    AKFixtureAdvance(0.5);
    assert(!bridge.active && areas.live && signal.inWorld && controls.textKind == AKTextKindNone);
    AKFixturePostSecure(NO);
    AKFixtureAdvance(2);
    assert(!bridge.active && areas.live && signal.inWorld && controls.textKind == AKTextKindNone);
    assert([[(UIButton *)[controls valueForKey:@"_keyboardButton"] accessibilityLabel] isEqual:@"Show keyboard"]);
    assert(![[controls valueForKey:@"_protectedField"] boolValue]);
    // ...and a 2 s one is the box: the field opens past 1.5 s (not before), the world goes then, and its end is no pulse.
    AKFixturePostSecure(YES);
    AKFixtureAdvance(1.4);
    assert(!bridge.active && areas.live && signal.inWorld);
    AKFixtureAdvance(0.2);
    assert(bridge.active && controls.textKind == AKTextKindPassword && !areas.live && !signal.inWorld);
    AKFixtureAdvance(3);
    AKFixturePostSecure(NO);
    assert(!bridge.active);
    AKFixtureAdvance(2);
    assert(!areas.live);
    // At the login screen (out of the world) a 0.5 s one is already a box: the field opens after the usual 0.35 s.
    AKFixturePostSecure(YES);
    AKFixtureAdvance(0.3);
    assert(!bridge.active);
    AKFixtureAdvance(0.2);
    assert(bridge.active && controls.textKind == AKTextKindPassword && !areas.live);
    AKFixturePostSecure(NO);
    assert(!bridge.active);
    AKFixtureAdvance(2);
    assert(!areas.live);
    // Entering the world after it: live again. And a second box later, then entering again.
    AKFixtureEnterWorldPulse();
    assert(areas.live);

    // Out of the world again, a tap on a spell is a plain click once more (the same as after the first double pulse).
    AKFixtureLeaveWorldPulses();
    assert(!areas.live);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, spell);
    AKFixtureExpect(@"left again: a plain click", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", spell, host), AKFixtureMouse(@"LeftUp", spell, host)]));
    assert(guest.keyEvents.count == 0);

    // The checks that follow set their own button lists and start in the world.
    areas.contract = nil;
    AKFixtureEnterWorldPulse();
    assert(areas.live);
    guest.keyEvents = nil;
    guest.mouseEvents = nil;
}

#pragma mark - A window open in the world (ruling A32)

// Three pulses: a window or panel is open while the player is still in the world. TouchPlay's buttons, the world touch and
// the walk stick stop as they do out of the world (plain touches), but an auto-run keeps running: run 5 (16 Nov) opened and
// closed the map with auto-run on, and the run stopped. The exact sequence: auto-run lock -> 3 -> 1 -> still running;
// -> 2 -> stopped. A group of four or more is read as two. With a window open (or out of the world) a plain touch is
// 0055's (ruling A33): a tap clicks on lift, a drag is the left button down at its start, moves, up at the lift (an item
// out of a bag), a still hold of 0.45 s is a right click; and no touch area opens the keyboard - only the game's own box.
static void AKFixtureCheckWindowState(UIView *host, AKInputFixtureView *guest, BOOL touchPlay) {
    if (!touchPlay) return;
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKTouchWorldSignal *signal = [controls valueForKey:@"_worldSignal"];
    AKTouchAreas *areas = [host valueForKey:@"_touchAreas"];
    AKTouchGamepad *stick = [controls valueForKey:@"_walkStick"];
    UIView *overlay = AKFindInputView(host, @"wolkaraforever.touch.walkArea");
    UIView *badge = AKFindInputView(host, @"wolkaraforever.touch.autorun"), *lock = AKFindInputView(host, @"wolkaraforever.touch.walkStick.lock");
    assert(signal && areas && stick && overlay && badge && lock);
    AKFixtureEnterWorld(host);
    NSString *path = [NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    AKTouchContract *contract = AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    assert(contract.areas.count == 26 && contract.edgeRun);
    areas.contract = contract;
    [host layoutIfNeeded];
    CGSize size = host.bounds.size;
    CGPoint walk = CGPointMake(size.width * 0.25, size.height * 0.62);
    __block NSTimeInterval now = 300;
    [overlay setValue:^NSTimeInterval { return now; } forKey:@"clock"];
    void (^autoRun)(void) = ^{
        AKFixtureTouch *thumb = AKFixtureFinger(walk); thumb.fixtureView = overlay;
        [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
        thumb.fixturePoint = CGPointMake(walk.x, walk.y - 60);
        [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
        thumb.fixturePoint = AKFixtureWalkLock(host);      // up onto the lock above the ring (ruling A34)
        [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
        now += 0.3; [overlay performSelector:@selector(tick)];   // held there until the lock is full
        [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
        AKDrainFixtureEvents();
    };

    // a32_auto_run_survives_a_window: lock the run, open a window (3), close it (1): still running, W never came up.
    AKFixtureResetInput(guest);
    autoRun();
    assert(stick.autoRunning);
    AKFixtureExpectKeys(@"auto-run", guest, @[@"down 13 -"]);
    AKFixtureWindowPulses();
    AKDrainFixtureEvents();
    assert(signal.state == AKTouchWorldWindow && !areas.live && areas.windowOpen && !signal.inWorld);
    AKFixtureExpectKeys(@"a window open: auto-run kept", guest, @[@"down 13 -"]);
    assert(stick.autoRunning && !badge.hidden && !lock.hidden);

    // With the window open the walk stick stays live (ruling A34) in the stick box only (A34b: the faint rest ring's square
    // and the lock target above it), and the pinch never takes its thumb (patch 0072) - a walk and a tap on the window are
    // two fingers, not a zoom. Elsewhere in the lower-left half (the game's character pane, spellbook, quest log) a tap is
    // a plain click, and it does not stop the run.
    NSMutableArray<NSValue *> *areaRects = [NSMutableArray array];
    for (AKTouchArea *area in contract.areas) [areaRects addObject:[NSValue valueWithCGRect:AKTouchAreaRect(area, size)]];
    CGRect box = AKTouchWalkRestRing(size, contract.leftHanded, areaRects);
    assert(!CGRectIsNull(box) && !CGRectContainsPoint(box, walk));
    CGPoint inBox = CGPointMake(CGRectGetMidX(box), CGRectGetMidY(box));
    assert([host hitTest:inBox withEvent:nil] == overlay);
    assert([host hitTest:walk withEvent:nil] == host);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, walk);
    AKFixtureExpect(@"a34b: a window open, a tap in the lower-left half outside the stick box is a plain click", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", walk, host), AKFixtureMouse(@"LeftUp", walk, host)]));
    assert(guest.keyEvents.count == 0 && stick.autoRunning);
    UIPinchGestureRecognizer *pinch = [host valueForKey:@"_pinch"];
    AKFixtureTouch *onStick = AKFixtureFinger(walk); onStick.fixtureView = overlay;
    // No thumb on the stick now (an auto-run): a finger there may be a pinch's first; the pinch's start decides (0073).
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:onStick]);
    assert([pinch.delegate gestureRecognizerShouldBegin:pinch]);
    AKFixtureTouch *onWindow = AKFixtureFinger(CGPointMake(size.width * 0.55, size.height * 0.5)); onWindow.fixtureView = host;
    assert([pinch.delegate gestureRecognizer:pinch shouldReceiveTouch:onWindow]);
    // Every other touch is plain (0055, ruling A33): a spell button is a click, a drag is down at the start, moves, up at
    // the lift, a still hold is a right click.
    CGPoint spell = AKFixtureCentre(contract, @"spell2", size);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, spell);
    AKFixtureExpect(@"a window open: a tap on a spell button is a plain click", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", spell, host), AKFixtureMouse(@"LeftUp", spell, host)]));
    assert(guest.keyEvents.count == 0 && areas.activeFingerCount == 0);
    // (Within the 10 pt slop nothing moves, so a tap that jitters never starts an item drag.)
    CGPoint from = CGPointMake(size.width * 0.5, size.height * 0.4), to = CGPointMake(from.x + 120, from.y + 60);
    AKFixtureResetInput(guest);
    AKFixtureGesture(host, from, @[[NSValue valueWithCGPoint:CGPointMake(from.x + 3, from.y)], [NSValue valueWithCGPoint:to]]);
    AKFixtureExpect(@"a window open: a drag (an item out of a bag)", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"LeftDown", from, host), AKFixtureMouse(@"LeftDrag", to, host), AKFixtureMouse(@"LeftUp", to, host)]));
    AKFixtureResetInput(guest);
    AKFixtureTouch *held = nil;
    AKFixtureHoldFired(host, from, 0.45, &held);   // 0055's hold time, not TouchPlay's (the buttons are not live)
    AKFixtureExpect(@"a window open: a still hold right clicks", AKFixtureClicks(guest),
                    AKFixtureJoin(@[AKFixtureMouse(@"RightDown", from, host), AKFixtureMouse(@"RightUp", from, host)]));
    [host touchesEnded:[NSSet setWithObject:held] withEvent:nil];
    AKDrainFixtureEvents();
    assert(guest.keyEvents.count == 0);

    // a32_keyboard_only_from_the_game: the chat strip is a plain click, and a chat-strip lift that raced the pulses
    // (the notification itself) opens nothing either.
    CGPoint chat = AKFixtureCentre(contract, @"chat", size);
    AKFixtureResetInput(guest);
    AKFixtureTap(host, chat);
    assert(!controls.keyboardVisible && guest.keyEvents.count == 0);
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchChatAreaTappedNotification object:areas];
    AKDrainFixtureEvents();
    assert(!controls.keyboardVisible && controls.textKind == AKTextKindNone);

    // One pulse: back in the world, still running, the knob still locked; the buttons live again.
    AKFixtureResetInput(guest);
    AKFixtureEnterWorldPulse();
    AKDrainFixtureEvents();
    assert(signal.inWorld && areas.live && !areas.windowOpen);
    assert(stick.autoRunning && !badge.hidden && !lock.hidden && guest.keyEvents.count == 0);
    assert([host hitTest:walk withEvent:nil] == overlay);
    // Two pulses: stopped.
    AKFixtureLeaveWorldPulses();
    AKDrainFixtureEvents();
    assert(signal.state == AKTouchWorldOut && !stick.autoRunning && badge.hidden);
    AKFixtureExpectKeys(@"left the world: auto-run stopped", guest, @[@"up 13 -"]);

    // From the window state straight out (2): stopped too.
    AKFixtureEnterWorldPulse();
    AKFixtureResetInput(guest);
    autoRun();
    AKFixtureWindowPulses();
    AKFixtureLeaveWorldPulses();
    AKDrainFixtureEvents();
    assert(signal.state == AKTouchWorldOut && !stick.autoRunning);
    AKFixtureExpectKeys(@"window then left: stopped", guest, @[@"down 13 -", @"up 13 -"]);

    // a32_four_pulses_are_two: four pulses with the run going: out of the world, stopped.
    AKFixtureEnterWorldPulse();
    AKFixtureResetInput(guest);
    autoRun();
    AKFixturePulse(); AKFixtureAdvance(0.15); AKFixturePulse(); AKFixtureAdvance(0.15); AKFixturePulse(); AKFixtureAdvance(0.15); AKFixturePulse();
    AKFixtureAdvance(1.0);
    AKDrainFixtureEvents();
    assert(signal.state == AKTouchWorldOut && !areas.live && !areas.windowOpen && !stick.autoRunning);
    AKFixtureExpectKeys(@"four pulses: stopped", guest, @[@"down 13 -", @"up 13 -"]);

    // A walking thumb (no run) when the window opens keeps walking (ruling A34); its lift lets go.
    AKFixtureEnterWorldPulse();
    AKFixtureResetInput(guest);
    AKFixtureTouch *thumb = AKFixtureFinger(walk); thumb.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:thumb] withEvent:nil];
    thumb.fixturePoint = CGPointMake(walk.x, walk.y - 50);
    [overlay touchesMoved:[NSSet setWithObject:thumb] withEvent:nil];
    AKFixtureWindowPulses();
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"a window opened under a walking thumb: still walking", guest, @[@"down 13 -"]);
    [overlay touchesEnded:[NSSet setWithObject:thumb] withEvent:nil];
    AKDrainFixtureEvents();
    AKFixtureExpectKeys(@"its lift lets go", guest, @[@"down 13 -", @"up 13 -"]);
    assert(!stick.autoRunning);
    // a34_lock_tap_with_a_window_open: locked with the window open, a tap on the lock stops it.
    AKFixtureResetInput(guest);
    autoRun();
    assert(stick.autoRunning && signal.state == AKTouchWorldWindow);
    CGPoint lockAt = AKFixtureWalkLock(host);
    assert([host hitTest:lockAt withEvent:nil] == overlay);
    AKFixtureTouch *lockTap = AKFixtureFinger(lockAt); lockTap.fixtureView = overlay;
    [overlay touchesBegan:[NSSet setWithObject:lockTap] withEvent:nil];
    [overlay touchesEnded:[NSSet setWithObject:lockTap] withEvent:nil];
    AKDrainFixtureEvents();
    assert(!stick.autoRunning);
    AKFixtureExpectKeys(@"a window open: the lock stops the run", guest, @[@"down 13 -", @"up 13 -"]);
    // With the window open, the game's own request still opens the keyboard (the game focusing a box: the keyboard's
    // one way in while a window is open). It is checked last because the keyboard lets go of an auto-run (typing is
    // not walking).
    assert(signal.state == AKTouchWorldWindow);
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchKeyboardRequestNotification object:nil];
    AKDrainFixtureEvents();
    assert(controls.keyboardVisible);
    [controls dismissKeyboard];
    AKDrainFixtureEvents();
    assert(!controls.keyboardVisible);

    // The checks that follow set their own button lists and start in the world.
    AKFixtureEnterWorldPulse();
    assert(areas.live);
    [overlay setValue:nil forKey:@"clock"];
    areas.contract = nil;
    guest.keyEvents = nil;
    guest.mouseEvents = nil;
}

static void AKFixtureInputSource(void *context) {
    (void)context;
    NSEvent *event = [NSEvent new]; event.type = NSEventTypeMouseMoved;
    [NSApp postEvent:event atStart:NO];
}

// The self-test's watchdog: a blocked main thread fails the run instead of leaving simctl waiting.
static const int AKSelfTestWatchdogSeconds = 30;
static NSTimeInterval gSelfTestStarted;

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
        BOOL accessibilityText = [UIApplication.sharedApplication.preferredContentSizeCategory
            containsString:@"Accessibility"];
        // The card and its action row are sized by the same layout pass, so a read taken between
        // two of them sees the old geometry. Wait for the height this category wants first.
        CGFloat wantedCard = accessibilityText ? 130.5 : 130, wantedRow = accessibilityText ? 44.5 : 44;
        BOOL settled = AKTouchFixtureWaitFor(5.0, ^{
            [card setNeedsLayout];
            [card layoutIfNeeded];
            return (BOOL)(CGRectGetHeight(card.frame) >= wantedCard - 0.5 &&
                           CGRectGetHeight(row.frame) >= wantedRow - 0.5);
        });
        if (!settled)
            fprintf(stderr, "CHAT_COMPOSER_NOT_SETTLED: category=%s card=%.1f row=%.1f editor=%.1f\n",
                    UIApplication.sharedApplication.preferredContentSizeCategory.UTF8String,
                    CGRectGetHeight(card.frame), CGRectGetHeight(row.frame),
                    CGRectGetHeight([input convertRect:input.bounds toView:host]));
        CGRect editorInHost = [input convertRect:input.bounds toView:host];
        CGFloat cardHeight = CGRectGetHeight(card.frame), rowHeight = CGRectGetHeight(row.frame);
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
    // "--mobile-interface" alone is iOS; a value after it ("iosduo", "ipadtouch") is that mode.
    NSArray<NSString *> *launchArguments = NSProcessInfo.processInfo.arguments;
    NSUInteger mobileFlag = [launchArguments indexOfObject:@"--mobile-interface"];
    BOOL mobileInterface = mobileFlag != NSNotFound;
    NSString *mobileMode = @"ios";
    if (mobileInterface && mobileFlag + 1 < launchArguments.count && ![launchArguments[mobileFlag + 1] hasPrefix:@"-"])
        mobileMode = launchArguments[mobileFlag + 1];
    BOOL touchPlayInterface = [mobileMode isEqual:@"ipadtouch"] && mobileInterface;
    // The host's direct-touch gestures (0055): "ios" and, with patch 0065, "ipadtouch". iOS on Duo has the mobile
    // toolbar and not those gestures, as it always had.
    BOOL directGestures = (mobileInterface && [mobileMode isEqual:@"ios"]) || touchPlayInterface;
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
        if (mobileInterface) modes[@"WolkaraForeverInterfaceModeV1"] = mobileMode;
        [NSUserDefaults.standardUserDefaults setVolatileDomain:modes forName:NSArgumentDomain];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--tracking-progress-test"]) {
        NSMutableDictionary *arguments=[[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        arguments[@"TKTouchGamepadEnabled"]=@NO;
        [NSUserDefaults.standardUserDefaults setVolatileDomain:arguments forName:NSArgumentDomain];
    }
    // The toolbar's fold is a saved setting, and a run that was cut short must not hand its state to
    // the next: the self-test starts from the default (folded).
    if ([launchArguments containsObject:@"--self-test"])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverToolbarCollapsed"];
    // iPad touch's self-test starts as a player who once turned the trackpad on in another interface (IPAD RUN 2): the
    // shared switch on (argument domain, nothing written), iPad touch's own never set.
    if (touchPlayInterface && [launchArguments containsObject:@"--self-test"]) {
        NSMutableDictionary *arguments = [[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        arguments[@"TKTouchTrackpadEnabled"] = @YES;
        [NSUserDefaults.standardUserDefaults setVolatileDomain:arguments forName:NSArgumentDomain];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverIPadTouchTrackpadEnabled"];
    }
    [NSApplication sharedApplication];
    self.guest = [[NSWindow alloc] initWithContentRect:((UIWindowScene *)scene).screen.bounds styleMask:0 backing:2 defer:NO];
    self.guest.contentView = [[AKInputFixtureView alloc] initWithFrame:self.guest.frame];
    self.guest.acceptsMouseMovedEvents = YES;
    [self.guest makeFirstResponder:self.guest.contentView];
    [self.guest makeKeyAndOrderFront:nil];
    // The guest's loop: a frame every 16 ms, as the game's own (drain the queue, then act on it).
    self.pump = [NSTimer scheduledTimerWithTimeInterval:0.016 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        AKFixtureFrame();
    }];
    BOOL selfTest = [NSProcessInfo.processInfo.arguments containsObject:@"--self-test"];
    BOOL composerTest = [NSProcessInfo.processInfo.arguments containsObject:@"--composer-test"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--composer-qa"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--composer-visual"];
    BOOL nativeReference = [NSProcessInfo.processInfo.arguments containsObject:@"--native-keyboard-reference"];
    if (selfTest || composerTest) {
        // A blocked main thread must fail instead of leaving simctl waiting.
        gSelfTestStarted = NSProcessInfo.processInfo.systemUptime;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, AKSelfTestWatchdogSeconds * NSEC_PER_SEC),
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
                // The host gate (0055, and patch 0065 for iPad touch): "ios" and "ipadtouch" get the
                // host's direct-touch gestures - several fingers and the pinch recognizer - and every
                // other value (Standard, iOS on Duo) keeps the host it had: no pinch.
                id pinch = [host valueForKey:@"_pinch"];
                if (directGestures) assert(host.multipleTouchEnabled && pinch != nil);
                else assert(pinch == nil);
                // The controller overlay (patch-free, in TouchControls.m): iPad touch has none and
                // attaches no virtual gamepad; every other value has the overlay it always had.
                id gamepad = [controls valueForKey:@"_gamepad"];
                Class overlayClass = NSClassFromString(@"AKGamepadOverlay");
                assert(overlayClass != Nil);
                BOOL overlayPresent = NO;
                for (UIView *subview in host.subviews) if ([subview isKindOfClass:overlayClass]) overlayPresent = YES;
                if (touchPlayInterface) {
                    assert(gamepad == nil && !overlayPresent);
                } else {
                    assert(gamepad != nil && overlayPresent);
                }
                // iPad touch with no TouchPlay buttons saved (this fixture has no game folder): the notice says so in
                // the game view, once, and never takes a touch (ruling A17) - but only in the world (ruling A24): a
                // game start is not, so there is none yet (AKFixtureCheckWorldGate shows it with the entering pulse).
                // No other mode has it.
                UIView *notice = AKFindInputView(host, @"wolkaraforever.touch.contractMissing");
                assert(notice == nil);
                if (!touchPlayInterface) assert([host valueForKey:@"_touchAreas"] == nil);
                // The toolbar stays in every mode.
                assert(AKFindInputView(host, @"wolkaraforever.leaveGame") != nil);
                // ...but in iPad touch the two controls that belong to the controller overlay (its
                // on/off toggle and its settings gear) are hidden, however the toolbar is folded, and
                // the rest are packed together. Every other mode keeps both, as it always has.
                UIView *gamepadToggle = AKFindInputView(host, @"tolkara.gamepad");
                UIView *settingsGear = AKFindInputView(host, @"wolkaraforever.controlSettings");
                UIView *leaveButton = AKFindInputView(host, @"wolkaraforever.leaveGame");
                assert(gamepadToggle != nil && settingsGear != nil);
                BOOL foldedAtStart = [[controls valueForKey:@"_toolbarCollapsed"] boolValue];
                for (NSNumber *fold in @[@YES, @NO]) {
                    if (mobileInterface) AKFixtureSetToolbarCollapsed(controls, fold.boolValue);
                    [host layoutIfNeeded]; [controls layoutIfNeeded];
                    if (touchPlayInterface) {
                        assert(gamepadToggle.hidden && settingsGear.hidden);
                        if (!fold.boolValue) {
                            // Four buttons now: trackpad, keyboard, leave, handle.
                            assert(fabs(controls.frame.size.width - 208) < 1);
                            assert(fabs(leaveButton.frame.origin.x - 104) < 1);
                            assert(!leaveButton.hidden && !leaveButton.superview.hidden);
                            UIView *handle = [controls valueForKey:@"_toolbarHandle"];
                            assert(handle != nil && fabs(handle.frame.origin.x - 156) < 1);
                        }
                    } else if (!mobileInterface || !fold.boolValue) {
                        assert(!gamepadToggle.hidden && !settingsGear.hidden);
                        if (mobileInterface) assert(fabs(controls.frame.size.width - 304) < 1);
                    }
                }
                if (mobileInterface) AKFixtureSetToolbarCollapsed(controls, foldedAtStart);
                [host layoutIfNeeded]; [controls layoutIfNeeded];
                // The gear in iPad touch opens nothing and messages no gamepad.
                if (touchPlayInterface) { [controls showControlSettings]; assert(!controls.configuring); }
                // iPad touch keeps its own chat: the Composer's review mode is never in force there, even when
                // it is the stored mode (a new installation's default). Every other interface follows the mode.
                {
                    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
                    NSDictionary *saved = [defaults volatileDomainForName:NSArgumentDomain];
                    NSMutableDictionary *review = [saved mutableCopy];
                    review[@"AKChatDeliveryMode"] = @"review";
                    [defaults setVolatileDomain:review forName:NSArgumentDomain];
                    AKChatDeliveryModeResetCacheForTesting();
                    BOOL inReview = ((BOOL (*)(id, SEL))objc_msgSend)(controls, NSSelectorFromString(@"composerInReviewMode"));
                    assert(inReview == (!touchPlayInterface && AKChatComposerIsAvailable()));
                    [defaults setVolatileDomain:saved forName:NSArgumentDomain];
                    AKChatDeliveryModeResetCacheForTesting();
                    puts(touchPlayInterface ? "TOUCH_CHAT_KEEPS_TOUCH_FLOW_PASS: in iPad touch the Composer's review mode is never in force"
                                            : "TOUCH_CHAT_FOLLOWS_COMPOSER_MODE_PASS: outside iPad touch the stored review mode is in force");
                }
                assert(fabs(CGRectGetMidX(resting) - CGRectGetMidX(host.bounds)) < 1);
                if (mobileInterface) {
                    // The phone modes rest at the bottom centre, between the thumbs; iPad touch at the top centre (run 5).
                    if (touchPlayInterface) assert(fabs(CGRectGetMinY(resting) - (host.safeAreaInsets.top + 8)) < 1);
                    else assert(fabs(CGRectGetMaxY(resting) - (CGRectGetMaxY(host.bounds) - host.safeAreaInsets.bottom - 8)) < 1);
                    assert(fabs(resting.size.width - 96) < 1 && fabs(resting.size.height - 34) < 1);
                    assert([controls valueForKey:@"_toolbarHandle"] != nil);
                } else {
                    assert(fabs(CGRectGetMinY(resting) - (host.safeAreaInsets.top + 8)) < 1);
                    assert(fabs(resting.size.width - 252) < 1 && fabs(resting.size.height - 44) < 1);
                    assert([controls valueForKey:@"_toolbarHandle"] == nil);
                }
            }
            [controls toggleKeyboard];
            if (!selfTest) {
                // A capture for the pull request: the composer holding a composed draft, with
                // the recogniser's language chosen as the shell would publish it. It asserts
                // nothing - the checks above own that - and it is what a person sees.
                if ([NSProcessInfo.processInfo.arguments containsObject:@"--qa-composer"]) {
                    [NSTimer scheduledTimerWithTimeInterval:1.2 repeats:NO block:^(NSTimer *timer) {
                        (void)timer;
                        UITextView *draft = (UITextView *)AKFindInputView(host, @"wolkaraforever.keyboard.draft");
                        [draft insertText:@"é e\u0301 ñ ü 🙂"];
                        [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchSpeechLanguageDidChange"
                                                                         object:nil
                                                                       userInfo:@{@"stored": @"de-DE"}];
                    }];
                }
                return;
            }
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                (void)timer;
                [host layoutIfNeeded];
                // The keyboard appears asynchronously, and the guide that reports it is laid out
                // with it. Wait for both rather than trusting one second to have covered it.
                BOOL keyboardReady = AKTouchFixtureWaitFor(10.0, ^{
                    [host layoutIfNeeded];
                    return (BOOL)(controls.keyboardVisible &&
                                  host.keyboardLayoutGuide.layoutFrame.size.height > 100 &&
                                  CGSizeEqualToSize(originalSize, host.bounds.size));
                });
                if (!keyboardReady)
                    fprintf(stderr, "TOUCH_UI_KEYBOARD_NOT_SETTLED: visible=%d guide=%.0f bounds=%s original=%s\n",
                            (int)controls.keyboardVisible,
                            host.keyboardLayoutGuide.layoutFrame.size.height,
                            NSStringFromCGSize(host.bounds.size).UTF8String,
                            NSStringFromCGSize(originalSize).UTF8String);
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
                // --- committed Unicode -------------------------------------------------
                //
                // What UIKit committed is what the guest receives: one string, with its
                // composing marks and its emoji intact, rather than a guessed keycode per
                // character. The guest fixture appends exactly `event.characters`, so this is
                // the text a game's own field would insert, and deletion is its own key.
                [fixture.text setString:@""];
                fixture.selection = NSMakeRange(0, 0);
                NSMutableArray<NSString *> *phases = [NSMutableArray array];
                id compositionObserver = [NSNotificationCenter.defaultCenter
                    addObserverForName:AKTouchDraftCompositionDidChangeNotification object:nil
                                queue:NSOperationQueue.mainQueue
                           usingBlock:^(NSNotification *note) {
                    [phases addObject:note.userInfo[AKTouchDraftCompositionPhaseKey] ?: @"?"];
                }];
                // Provisional text stays native: marking it sends nothing.
                [input setMarkedText:@"provisional" selectedRange:NSMakeRange(11, 0)];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@""]);
                // A commit is announced once, when UIKit hands the composed string over.
                [input insertText:@"é"];
                AKDrainFixtureEvents();
                assert(phases.count == 1 && [phases.firstObject isEqual:AKTouchDraftCompositionCommit]);
                assert([fixture.text isEqual:@""]);   // editing a draft is not sending it
                // A cancelled composition is announced as a cancellation, and sends nothing.
                [input setMarkedText:@"discarded" selectedRange:NSMakeRange(9, 0)];
                [input dictationRecognitionFailed];
                AKDrainFixtureEvents();
                assert(phases.count == 2 && [phases.lastObject isEqual:AKTouchDraftCompositionCancel]);
                assert([fixture.text isEqual:@""]);
                [NSNotificationCenter.defaultCenter removeObserver:compositionObserver];
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert(!input.text.length);
                // The sequence the plan names, through the route a transcript and the layer's
                // own keys use: accent, combining acute, ñ, ü and an emoji.
                [controls touchInsertText:@"é"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"é"]);
                [controls touchInsertText:@"e\u0301"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"ée\u0301"]);   // the combining mark is preserved, not folded
                [controls touchInsertText:@"ñü🙂"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"ée\u0301ñü🙂"]);
                // Deletion is a key, and the guest deletes the whole composed character.
                [controls touchSpecialKey:51 characters:@"\x7f"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"ée\u0301ñü"]);
                // Return stays explicit and never arrives as part of the text.
                assert(![fixture.text containsString:@"\r"]);
                [controls touchSpecialKey:36 characters:@"\r"];
                AKDrainFixtureEvents();
                assert([fixture.text hasSuffix:@"\r"]);
                [expected setString:fixture.text];
                // --- the recogniser's language, in the composer -------------------------
                //
                // Recognition configuration, not input: the control is named, it reports its
                // state as a value, and choosing a language asks the shell for it without
                // sending a single key to the guest.
                // The composer is a sibling of the controls, in the host view.
                UIView *composerRoot = controls.window ?: controls.superview ?: controls;
                UIButton *language = FixtureLanguageButton(composerRoot);
                assert(language != nil && language.isAccessibilityElement);
                assert(language.accessibilityLabel.length > 0);
                assert(language.accessibilityHint.length > 0);
                assert(language.accessibilityValue.length > 0);
                assert(language.menu.children.count == 5);
                NSMutableArray<NSString *> *asked = [NSMutableArray array];
                id languageObserver = [NSNotificationCenter.defaultCenter
                    addObserverForName:@"AKTouchSpeechLanguageRequest" object:nil
                                queue:NSOperationQueue.mainQueue
                           usingBlock:^(NSNotification *note) {
                    [asked addObject:note.userInfo[@"stored"] ?: @"?"];
                }];
                NSString *guestBefore = [fixture.text copy];
                [controls chooseSpeechLanguage:@"de-DE"];
                AKDrainFixtureEvents();
                assert(asked.count == 1 && [asked.firstObject isEqual:@"de-DE"]);
                // Nothing reached the guest, and the draft was not changed either.
                assert([fixture.text isEqual:guestBefore]);
                assert(input.text.length == 0);
                // The shell answers with the value now in force, and the control shows it.
                [NSNotificationCenter.defaultCenter postNotificationName:@"AKTouchSpeechLanguageDidChange"
                                                                 object:nil
                                                               userInfo:@{@"stored": @"de-DE"}];
                AKDrainFixtureEvents();
                assert([[language titleForState:UIControlStateNormal] isEqual:@"German"]);
                assert([language.accessibilityValue isEqual:@"German"]);
                [NSNotificationCenter.defaultCenter removeObserver:languageObserver];
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
                // The accessory's Return key, by its identifier: in iPad touch the key row sits under the chat's chips.
                UIButton *accessoryReturn = (UIButton *)AKFindInputView(controls.inputAccessoryView, @"wolkaraforever.keyboard.key.5");
                assert([accessoryReturn isKindOfClass:UIButton.class]);
                [input insertText:@" done"];
                [accessoryReturn sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected]);
                // The system keyboard's key follows the interface. Standard: Done replaces the
                // selected field, exactly as every release through v1.0.7. Mobile: Send puts the
                // draft in the game's chat - F12 (the key the Interface mobile add-on binds to
                // its chat), the line, then Return - and the keyboard goes away. Replace stays
                // the button that fills the selected field without pressing Return.
                NSUInteger keysBefore = fixture.keyCodes.count, replacementsBefore = fixture.replacements;
                if (mobileInterface) {
                    // iPad touch at a game's start is out of the world, at the login screen: the composer types into the
                    // game's account box, and its Return is Tab (to the password box) - no chat key, never Login (17 Nov 2026).
                    unsigned short first = touchPlayInterface ? 2 : 111, last = touchPlayInterface ? 48 : 36;
                    NSString *suffix = touchPlayInterface ? @"done\t" : @"done\r";
                    [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                    AKDrainFixtureEvents();
                    NSArray<NSNumber *> *sent = [fixture.keyCodes subarrayWithRange:NSMakeRange(keysBefore, fixture.keyCodes.count - keysBefore)];
                    if (sent.count < 2 || sent.firstObject.unsignedShortValue != first || sent.lastObject.unsignedShortValue != last ||
                        ![fixture.text hasSuffix:suffix] || fixture.replacements != replacementsBefore || input.text.length) {
                        fprintf(stderr, "TOUCH_UI_SEND_MISMATCH: keys=%s text=%s replacements=%lu->%lu draft=%s\n",
                                sent.description.UTF8String, fixture.text.UTF8String, (unsigned long)replacementsBefore,
                                (unsigned long)fixture.replacements, input.text.UTF8String);
                    }
                    assert(sent.count >= 2 && sent.firstObject.unsignedShortValue == first && sent.lastObject.unsignedShortValue == last);
                    assert([fixture.text hasSuffix:suffix] && fixture.replacements == replacementsBefore && !input.text.length);
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
                [accessoryReturn sendActionsForControlEvents:UIControlEventTouchUpInside];
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
                // Standard and iPad touch: the toolbar never left the top, so the frame is the one it had while
                // typing. The phone modes: the keyboard gone, it is back at the bottom, wherever the
                // gamepad is.
                if (mobileInterface && !touchPlayInterface) {
                    assert(!CGRectEqualToRect(toolbarFrame, controls.frame));
                } else {
                    assert(CGRectEqualToRect(toolbarFrame, controls.frame));
                }
                CGRect down = controls.frame;
                if (touchPlayInterface) {
                    assert(fabs(CGRectGetMinY(down) - (host.safeAreaInsets.top + 8)) < 1);
                } else if (mobileInterface) {
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
                [fixture.text setString:expected];

                [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                    (void)timer;
                    assert([fixture.text isEqual:expected]);
                    assert(!controls.keyboardVisible && host.isFirstResponder);
                    // Each check's own time goes to the log, and the whole run's against its 30 s watchdog, so a slow
                    // check is seen before it trips the watchdog.
                    NSTimeInterval checkStart = NSProcessInfo.processInfo.systemUptime;
#define AKTimedCheck(call) do { call; NSTimeInterval at = NSProcessInfo.processInfo.systemUptime; \
    NSLog(@"TOUCH_UI_CHECK_TIME %s %.1f s", #call, at - checkStart); checkStart = at; } while (0)
                    AKTimedCheck(AKFixtureCheckWorldGate(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckWindowState(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckTouchAreas(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckWalkStick(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckChordFrames(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckInterruptions(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckToolbarDock(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckTextKeyboard(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckChatAndSignIn(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckAutofill(host, fixture, touchPlayInterface));
                    AKTimedCheck(AKFixtureCheckWorldTouch(host, fixture, touchPlayInterface, directGestures));
                    AKTimedCheck(AKFixtureCheckTrackpadSwitch(host, fixture, touchPlayInterface));
#undef AKTimedCheck
                    NSLog(@"TOUCH_UI_SELF_TEST_TIME: %.1f s of %d s since the watchdog started", NSProcessInfo.processInfo.systemUptime - gSelfTestStarted, AKSelfTestWatchdogSeconds);
                    NSLog(@"TOUCH_UI_SELF_TEST_PASS: whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation, cancellation and fixed toolbar%@",
                          touchPlayInterface ? @"; TouchPlay buttons: glow, chord keys on lift, Jump held, button plus world at once, no pinch on a button, a world gesture ends past a held button, reload and resize let go of Jump; the world: second tap right clicks, hold sends the world key, turn drags, drag off a spell aims and clicks or stops, an aim ends a look drag first, the edge posts nothing, no contract is 1.0.8; the walk stick: over the game below the toolbar, W through the host's key path and held through a spell's chord, no chord on a walk key, never in a pinch, none without a contract; leaving the app (resign active or background) with Jump held, the stick auto-running, a hold ring half full and a world right-drag lets go of every one (the host's mouse button too) and a waiting tap or hold never fires, a filling hold sends no hold key, an aimed spell is stopped with Interact's key, the other modes are unchanged; the toolbar handle, folded and open and for either hand, covers no button, takes its taps above the walk stick, folds after 6 s there, stays in the top-centre band folded and open in the world, with a window open, out of it, after a reload and with the keyboard up, and lets taps beside its buttons through; the in-world gate: a game start and a password box are plain 1.0.10 touches, one pulse enters the world, two leave it, three are a window open (plain touches: a drag is down at its start, moves, up at the lift, a hold right clicks; the chat strip opens no keyboard) that keeps an auto-run running through it and after it, four are two, a pulse never opens the password keyboard or touches the chat; the keyboard: the chat strip and the toolbar open the chat, the walk stops first, the password box brings a Passwords field whose text goes to the game and is gone; chips make slash lines, a gold Send, a world tap closes the chat, the keyboard passes without dropping, the game slides up for the password, the chat strip opens the password field while the box has focus" : directGestures ? @"; direct touch: hold right clicks, taps left click, drag looks" : @"");
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
