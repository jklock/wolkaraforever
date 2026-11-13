// Original fixture: tests our lifecycle with fake transports, then permits
// manual testing of Apple's real virtual controller. No game or network.
#import <UIKit/UIKit.h>
#import "../translation/AppKit/InterfaceMode.h"
#import "../translation/AppKit/TouchGamepad.h"
#import "../translation/AppKit/TouchGamepadLayout.h"
#import "../translation/AppKit/TouchCamera.h"
#import "../translation/AppKit/TouchControllerLog.h"
#import "../translation/AppKit/TouchHaptics.h"
#include <assert.h>
#include <math.h>
#include <unistd.h>
#import "../translation/AppKit/AKTouchEventPump.h"

@interface AKTouchGamepad (FixtureSeams)
- (NSArray<GCController *> *)connectedControllers;
- (GCVirtualController *)makeController;
- (AKTouchHaptics *)makeHaptics;
// Whether the controller this drives carries the stick's own button. Apple's virtual one does
// not, which the app honours; a fixture subclass answers yes to prove the other path.
- (BOOL)stickButtonsAvailable;
@end
@interface AKTouchHaptics (FixtureSeams)
- (void)emitImpact:(BOOL)limit;
@end
@interface AKFixtureHaptics : AKTouchHaptics
@property NSUInteger buttons;
@property NSUInteger limits;
@end
@implementation AKFixtureHaptics
- (void)emitImpact:(BOOL)limit { if (limit) self.limits++; else self.buttons++; }
@end

static void TestHaptics(void) {
    AKFixtureHaptics *haptics=[AKFixtureHaptics new];
    [haptics buttonPressed]; [haptics stickMoved:CGPointMake(1,0) left:YES];
    assert(!haptics.buttons && !haptics.limits);
    haptics.enabled=YES; [haptics buttonPressed]; assert(haptics.buttons==1);
    [haptics stickMoved:CGPointMake(.7,.7) left:YES]; assert(!haptics.limits);
    [haptics stickMoved:CGPointMake(sqrt(.5),sqrt(.5)) left:YES]; assert(haptics.limits==1);
    // Holding, sliding around the edge and small radial jitter do not repeat.
    for (NSUInteger i=0; i<100; i++) {
        [haptics stickMoved:CGPointMake(.98,0) left:YES];
        [haptics stickMoved:CGPointMake(0,1) left:YES];
    }
    assert(haptics.limits==1);
    [haptics stickMoved:CGPointMake(0,-1) left:NO]; assert(haptics.limits==2);
    [haptics stickMoved:CGPointMake(.84,0) left:YES];
    [haptics stickMoved:CGPointMake(1,0) left:YES]; assert(haptics.limits==3);
    [haptics reset];
    [haptics stickMoved:CGPointMake(1,0) left:YES];
    [haptics stickMoved:CGPointMake(1,0) left:NO]; assert(haptics.limits==5);
    haptics.enabled=NO;
    [haptics buttonPressed]; [haptics stickMoved:CGPointZero left:YES];
    [haptics stickMoved:CGPointMake(1,0) left:YES];
    assert(haptics.buttons==1 && haptics.limits==5);
    haptics.enabled=YES;
    [haptics stickMoved:CGPointMake(NAN,0) left:YES];
    [haptics stickMoved:CGPointMake(INFINITY,0) left:NO]; assert(haptics.limits==5);
    [haptics stickMoved:CGPointMake(1,0) left:YES]; assert(haptics.limits==6);
    puts("TOUCH_HAPTICS_PASS: independent stick edges, held/jitter suppression, inward rearm, cancellation and disabled feedback.");
}
@interface AKFixtureController : NSObject
@property BOOL isSnapshot;
@property id extendedGamepad;
@property id microGamepad;
@end
@implementation AKFixtureController
@end
@interface AKFixtureConnection : NSObject
@property GCController *controller;
@property(copy) void (^reply)(NSError *);
@property NSUInteger disconnects;
- (void)finish:(NSError *)error;
@end
@implementation AKFixtureConnection
- (void)connectWithReplyHandler:(void (^)(NSError *))reply { self.reply=reply; }
- (void)disconnect { self.disconnects++; self.controller=nil; }
- (void)finish:(NSError *)error {
    if (!error) {
        AKFixtureController *controller=[AKFixtureController new]; controller.extendedGamepad=@YES;
        self.controller=(id)controller;
    }
    void (^reply)(NSError *)=self.reply; self.reply=nil; reply(error);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false);
}
@end
@interface AKFixtureGamepad : AKTouchGamepad
@property NSArray<GCController *> *devices;
@property AKFixtureConnection *lastConnection;
@property NSUInteger connections;
@end
@implementation AKFixtureGamepad
- (NSArray<GCController *> *)connectedControllers { return self.devices?:@[]; }
- (GCVirtualController *)makeController {
    self.connections++; self.lastConnection=[AKFixtureConnection new]; return (id)self.lastConnection;
}
@end

// The simulator can forward a host controller after lazy discovery. This
// fixture-only option still uses Apple's real controller, but lets us inspect it
// without disconnecting the user's hardware. Production always prioritizes it.
@interface AKPreviewGamepad : AKTouchGamepad
@property GCVirtualController *created;
@property AKFixtureHaptics *feedback;
// Apple's virtual controller has no stick button, which the app honours by refusing that
// gesture. This stands in for a controller that has one, so the positive path - one press of
// the right element, one release - is proved rather than described.
@property BOOL forceStickButtons;
@end
@implementation AKPreviewGamepad
- (BOOL)stickButtonsAvailable { return self.forceStickButtons || [super stickButtonsAvailable]; }
- (AKTouchHaptics *)makeHaptics { self.feedback=[AKFixtureHaptics new]; return self.feedback; }
- (GCVirtualController *)makeController { self.created=[super makeController]; return self.created; }
- (NSArray<GCController *> *)connectedControllers {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ignore-other-controllers"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"]) return @[];
    return [super connectedControllers];
}
@end


static UIView *Find(UIView *view, NSString *identifier) {    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *found=Find(child,identifier); if (found) return found; }
    return nil;
}
static UIControl *Button(UIView *host, NSString *name) {
    UIControl *control=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:name]);
    assert(control && !control.hidden); return control;
}
static void Drain(void) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false); }
// The lifecycle answers on the main queue: a connect or disconnect reply lands there, and a
// refresh that arrives while one is in flight waits for that reply. Sampling a fixed instant
// measured the scheduler rather than the rule, which is what made this fixture flake once.
static BOOL WaitUntil(BOOL (^predicate)(void)) {
    for (NSTimeInterval waited=0; waited<2.0; waited+=0.01) {
        if (predicate()) return YES;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,false);
    }
    return predicate();
}
@interface AKFixtureTouch : UITouch
@property CGPoint point;
// A tap is judged by the clock, so the fixture owns the clock: a real UITouch's timestamp is
// whatever UIKit said, and these traces are the ones this file writes.
@property NSTimeInterval when;
@end
@implementation AKFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
- (NSTimeInterval)timestamp { return _when > 0 ? _when : NSProcessInfo.processInfo.systemUptime; }
@end
@interface AKFixturePan : UIPanGestureRecognizer
@property CGPoint movement;
@property UIGestureRecognizerState testState;
@end
@implementation AKFixturePan
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.movement; }
- (UIGestureRecognizerState)state { return self.testState; }
@end
@interface UIView (LayoutFixture)
- (void)drag:(UIPanGestureRecognizer *)pan;
@end
// The movement stick's auto-run check, which the overlay's own timer calls; the fixture drives
// it with the clock it wants rather than waiting two real seconds.
@interface UIView (FloatingFixture)
- (void)pollAutoRun:(NSTimeInterval)now;
@end
// The host, with the one delegate method the mobile jump uses: a key pressed or released. It
// answers like the app's host view does, which is what decides Space over the gamepad's A.
@interface AKFixtureHostView : UIView
@property BOOL recordsKeys;
@property(readonly) NSMutableArray<NSString *> *keys;
@end
@implementation AKFixtureHostView { NSMutableArray<NSString *> *_keys; }
- (NSMutableArray<NSString *> *)keys { if (!_keys) _keys=[NSMutableArray new]; return _keys; }
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector==@selector(touchKey:characters:pressed:)) return self.recordsKeys;
    return [super respondsToSelector:selector];
}
- (void)touchKey:(unsigned short)code characters:(NSString *)characters pressed:(BOOL)pressed {
    [self.keys addObject:[NSString stringWithFormat:@"%u'%@'%@",code,characters,pressed?@"down":@"up"]];
}
@end
static void TestPreferences(void) {
    NSString *suite=[@"org.tolkara.layout-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    assert([[AKGamepadLayout alloc] initWithDefaults:defaults].swapShoulders);
    // Existing installations keep layout, opacity, size and haptic settings.
    [defaults setObject:@{@"opacity":@0.6,@"rearScale":@1.2,@"frontScale":@0.9,
        @"hapticsEnabled":@NO,@"positions":@{@"menu":@[@0.5,@0.5]}} forKey:@"WowkaraTouchLayoutV1"];
    AKGamepadLayout *migrated=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(fabs(migrated.opacity-.6)<.001 && fabs(migrated.rearScale-1.2)<.001 &&
           fabs(migrated.frontScale-.9)<.001 && !migrated.hapticsEnabled && !migrated.swapShoulders);
    assert([defaults dictionaryForKey:@"WolkaraForeverTouchLayoutV1"]);
    CGRect migratedFrame=[migrated frameForItem:@"menu" defaultFrame:CGRectMake(0,0,100,100) inBounds:CGRectMake(0,0,500,300)];
    assert(CGRectEqualToRect(migratedFrame,CGRectMake(200,100,100,100)));
    migrated.opacity=.3;[migrated save];
    assert(fabs([[AKGamepadLayout alloc] initWithDefaults:defaults].opacity-.3)<.001);
    // Explicit current values (even malformed ones) must not resurrect old values.
    [defaults setObject:@{@"opacity":@"bad",@"rearScale":@99,@"frontScale":@(-2),
        @"positions":@{@"broken":@[@"x",@0],@"left":@[@(-1),@4]}} forKey:@"WolkaraForeverTouchLayoutV1"];
    AKGamepadLayout *layout=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(layout.opacity==0.8 && layout.rearScale==1.5 && layout.frontScale==0.65 && layout.hapticsEnabled);
    layout.opacity=NAN; layout.rearScale=INFINITY; layout.frontScale=-INFINITY;
    assert(layout.opacity==0.8 && layout.rearScale==1 && layout.frontScale==1);
    CGRect bounds=CGRectMake(20,10,500,300), frame=CGRectMake(200,60,120,120);
    [layout moveItem:@"menu" toFrame:frame inBounds:bounds]; layout.opacity=.4; layout.hapticsEnabled=NO;
    layout.performanceOverlayEnabled=YES; layout.swapShoulders=YES; [layout save];
    layout=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(layout.opacity==.4 && !layout.hapticsEnabled && layout.performanceOverlayEnabled && layout.swapShoulders);
    layout.swapShoulders=NO; [layout save];
    assert(![[AKGamepadLayout alloc] initWithDefaults:defaults].swapShoulders);
    assert(CGRectEqualToRect([layout frameForItem:@"menu" defaultFrame:frame inBounds:bounds],frame));
    CGRect small=CGRectMake(0,0,220,120);
    assert(CGRectContainsRect(small,[layout frameForItem:@"menu" defaultFrame:frame inBounds:small]));
    [layout reset]; assert(layout.opacity==.8 && layout.frontScale==1 && layout.hapticsEnabled && !layout.performanceOverlayEnabled && layout.swapShoulders);
    assert(CGRectEqualToRect([layout frameForItem:@"menu" defaultFrame:frame inBounds:bounds],frame));
    // Templates and saved arrangements: the layout is data the user can keep and come back to.
    [layout reset];
    assert([AKGamepadLayout templateNames].count==3);
    [layout applyTemplateNamed:@"plain"];
    assert(!layout.sticksOnly && !layout.floatingSticks && layout.keepFree.count==0);
    [layout applyTemplateNamed:@"duo"];
    assert(layout.sticksOnly && layout.floatingSticks && layout.keepFree.count==0);
    [layout applyTemplateNamed:@"duo-addon"];
    assert(layout.floatingSticks && layout.keepFree.count==2);
    assert([layout saveAsProfileNamed:@"test-setup"]);
    assert([[layout savedProfileNames] containsObject:@"test-setup"]);
    [layout applyTemplateNamed:@"plain"];
    assert(!layout.floatingSticks);
    assert([layout applyProfileNamed:@"test-setup"] && layout.floatingSticks && layout.keepFree.count==2);
    assert([layout deleteProfileNamed:@"test-setup"]);
    assert(![[layout savedProfileNames] containsObject:@"test-setup"]);
    assert(![layout applyProfileNamed:@"test-setup"]);
    assert(![layout saveAsProfileNamed:@""]);
    // An arrangement from a hand-edited file cannot smuggle in an out-of-range value.
    [layout applyArrangement:@{@"opacity":@99, @"keepFree":@[@{@"x":@(NAN),@"y":@0,@"w":@0.1,@"h":@0.1},
                                                            @{@"x":@0.5,@"y":@0.5,@"w":@0.2,@"h":@0.2}]}];
    assert(layout.opacity==1 && layout.keepFree.count==1);
    // Everything the user sets survives a relaunch and an app update: it is all in the saved
    // dictionary, and a newer version's unknown key does not erase it.
    layout.opacity=.55; layout.rearScale=1.4; layout.frontScale=.7; layout.hapticsEnabled=NO;
    layout.swapShoulders=NO; layout.performanceOverlayEnabled=YES; layout.sticksOnly=NO;
    layout.floatingSticks=YES; [layout clearKeepFreeAreas];
    [layout addKeepFreeAreaWithX:0.1 y:0.2 width:0.3 height:0.4];
    [layout moveItem:@"menu" toFrame:CGRectMake(10,20,44,44) inBounds:bounds];
    [layout save];
    AKGamepadLayout *relaunched=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(fabs(relaunched.opacity-.55)<.001 && fabs(relaunched.rearScale-1.4)<.001 &&
           fabs(relaunched.frontScale-.7)<.001 && !relaunched.hapticsEnabled && !relaunched.swapShoulders &&
           relaunched.performanceOverlayEnabled && !relaunched.sticksOnly && relaunched.floatingSticks);
    assert(relaunched.keepFree.count==1 && fabs(relaunched.keepFree[0][@"w"].doubleValue-0.3)<.001);
    assert(CGRectEqualToRect([relaunched frameForItem:@"menu" defaultFrame:frame inBounds:bounds],
                             [layout frameForItem:@"menu" defaultFrame:frame inBounds:bounds]));
    // A version that adds a key writes it beside ours; ours still loads.
    NSMutableDictionary *stored=[NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"WolkaraForeverTouchLayoutV1"]];
    stored[@"aKeyFromALaterVersion"]=@{@"anything":@YES};
    [defaults setObject:stored forKey:@"WolkaraForeverTouchLayoutV1"];
    AKGamepadLayout *updated=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(fabs(updated.opacity-.55)<.001 && updated.floatingSticks && updated.keepFree.count==1);
    // Which element each control sends is data too, it is unique per control, and it survives.
    [updated clearElementMapping];
    assert([[updated elementForSlot:GCInputButtonA] isEqual:GCInputButtonA]);
    assert([updated setElement:GCInputLeftShoulder forSlot:GCInputButtonA]);
    assert([[updated elementForSlot:GCInputButtonA] isEqual:GCInputLeftShoulder]);
    // One element cannot be two controls: the second is refused, not silently won.
    assert(![updated setElement:GCInputLeftShoulder forSlot:GCInputButtonB]);
    assert([[updated elementForSlot:GCInputButtonB] isEqual:GCInputButtonB]);
    // Nonsense is refused.
    assert(![updated setElement:@"Nonsense" forSlot:GCInputButtonA]);
    assert(![updated setElement:GCInputButtonX forSlot:@"Nonsense"]);
    [updated save];
    AKGamepadLayout *mapped=[[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert([[mapped elementForSlot:GCInputButtonA] isEqual:GCInputLeftShoulder]);
    [mapped clearElementMapping];
    assert([[mapped elementForSlot:GCInputButtonA] isEqual:GCInputButtonA]);
    [defaults removePersistentDomainForName:suite];
}
// With sticks only, the jump is the one button under the camera stick, and its reach is the
// lower half of the space around that stick: the drawn ring, the gap next to the stick and a
// band below the ring. Above or beside the stick, and far below it, the touch is the game's.
static void TestJumpReach(UIView *host, AKPreviewGamepad *manager) {
    [manager toggleSettings];
    UISwitch *sticksOnly=(id)Find(host,@"wolkaraforever.controls.sticksOnly");
    sticksOnly.on=YES; [sticksOnly sendActionsForControlEvents:UIControlEventValueChanged];
    [manager toggleSettings]; [host layoutIfNeeded];
    UIControl *jump=Button(host,GCInputButtonA);
    UIView *rightStick=Find(host,@"tolkara.gamepad.rightStick"), *ring=rightStick.superview;
    CGPoint centre=CGPointMake(CGRectGetMidX(ring.bounds),CGRectGetMidY(ring.bounds));
    CGPoint (^at)(CGFloat, CGFloat)=^CGPoint(CGFloat radius, CGFloat degreesFromDown) {
        CGFloat angle=M_PI_2+degreesFromDown*M_PI/180;
        return [ring convertPoint:CGPointMake(centre.x+radius*cos(angle),centre.y+radius*sin(angle)) toView:host];
    };
    assert([host hitTest:at(0,0) withEvent:nil]==rightStick);
    assert([host hitTest:at(82,0) withEvent:nil]==jump);    // the drawn ring
    assert([host hitTest:at(56,0) withEvent:nil]==jump);    // the gap next to the stick
    assert([host hitTest:at(118,0) withEvent:nil]==jump);   // just under the ring
    assert([host hitTest:at(118,-50) withEvent:nil]==jump); // down and to the left
    assert([host hitTest:at(118,50) withEvent:nil]==jump);  // down and to the right
    assert([host hitTest:at(118,-90) withEvent:nil]!=jump); // beside the stick
    assert([host hitTest:at(82,180) withEvent:nil]!=jump);  // above it
    assert([host hitTest:at(160,0) withEvent:nil]!=jump);   // far below
    [jump sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(manager.created.controller.extendedGamepad.buttonA.pressed); // a host without keys
    [jump sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    assert(!manager.created.controller.extendedGamepad.buttonA.pressed);
    AKFixtureHostView *keyed=(id)host;
    keyed.recordsKeys=YES;
    [jump sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert([keyed.keys isEqual:@[@"49' 'down"]] && !manager.created.controller.extendedGamepad.buttonA.pressed);
    [jump sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(keyed.keys.count==1); // still held: no second press
    [jump sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    assert([keyed.keys isEqual:(@[@"49' 'down",@"49' 'up"])]);
    [jump sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    manager.keyboardVisible=YES; Drain();
    assert([keyed.keys.lastObject isEqual:@"49' 'up"] && keyed.keys.count==4);
    [jump sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    assert(keyed.keys.count==4); // released once only
    manager.keyboardVisible=NO; Drain();
    keyed.recordsKeys=NO;
    puts("TOUCH_GAMEPAD_JUMP_REACH_PASS: with sticks only the jump takes the ring, the gap by the stick and the band below, not beside, above or far below; it holds Space while pressed and always releases it.");
}
static void TestFloating(UIView *host, AKPreviewGamepad *manager);
// The mode's one rule: explicit choices win, "auto" is the device's own hardware class, and
// anything missing or unrecognised is Standard. Read through the same argument domain the
// scene uses, and put back exactly what was there.
static void TestInterfaceMode(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *key=AKInterfaceModeDefaultsKey;
    BOOL phone=UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPhone;
    id original=[defaults objectForKey:key];
    void (^setMode)(id)=^(id value) {
        NSMutableDictionary *modes=[[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary new];
        if (value) modes[key]=value; else [modes removeObjectForKey:key];
        [defaults setVolatileDomain:modes forName:NSArgumentDomain];
    };
    setMode(AKInterfaceModeIOS); assert(AKInterfaceModeIsMobile() && !AKInterfaceModeIsAutomatic());
    setMode(AKInterfaceModeIOSDuo);
    assert(AKInterfaceModeIsMobile() && !AKInterfaceModeIsAutomatic());
    assert([AKInterfaceModeName() isEqual:AKInterfaceModeIOSDuo]);
    assert([AKInterfaceModeStoredName() isEqual:AKInterfaceModeIOSDuo]);
    setMode(AKInterfaceModeIPadOS); assert(!AKInterfaceModeIsMobile() && !AKInterfaceModeIsAutomatic());
    setMode(AKInterfaceModeAuto);
    assert(AKInterfaceModeIsMobile()==phone && AKInterfaceModeIsAutomatic());
    assert([AKInterfaceModeName() isEqual:AKInterfaceModeAutomaticName()]);
    assert([AKInterfaceModeStoredName() isEqual:AKInterfaceModeAuto]);
    setMode(@"AUTO"); assert(AKInterfaceModeIsMobile()==phone);
    setMode(@"duo"); assert(!AKInterfaceModeIsMobile() && !AKInterfaceModeIsAutomatic());
    assert([AKInterfaceModeName() isEqual:AKInterfaceModeIPadOS]);
    setMode(nil); assert(!AKInterfaceModeIsMobile() && !AKInterfaceModeIsAutomatic());
    assert([AKInterfaceModeStoredName() isEqual:AKInterfaceModeIPadOS]);
    setMode(AKInterfaceModeIPadOS);
    NSString *automatic=AKInterfaceModeAutomaticName();
    assert(([automatic isEqual:AKInterfaceModeIOS] || [automatic isEqual:AKInterfaceModeIOSDuo])==phone);
    setMode(original);
    puts("TOUCH_INTERFACE_MODE_PASS: ios and ipados are explicit, auto is the device's own hardware class (spelled in any case), and a missing or unrecognised value is Standard.");
}
// --- the log a fixture can read ------------------------------------------------
//
// Every touch-controller line goes to the sink while these fixtures run. Counting presses
// against releases here is how "one press has one release" is proved rather than asserted in
// prose: the lines are the same ones a device log carries.
static NSMutableArray<NSString *> *AKFixtureLogLines;
static void AKFixtureCollectLine(NSString *line) {
    if (!AKFixtureLogLines) AKFixtureLogLines = [NSMutableArray new];
    [AKFixtureLogLines addObject:line];
}
static void AKFixtureBeginLog(void) {
    AKFixtureLogLines = [NSMutableArray new];
    AKTouchControllerLogSink = AKFixtureCollectLine;
}
static void AKFixtureEndLog(void) { AKTouchControllerLogSink = NULL; }
static NSUInteger AKFixtureLogCount(NSString *needle) {
    NSUInteger count = 0;
    for (NSString *line in AKFixtureLogLines) if ([line containsString:needle]) count++;
    return count;
}
static BOOL AKFixtureLogHas(NSString *needle) { return AKFixtureLogCount(needle) > 0; }
// The lines themselves, when an assertion needs to say what happened rather than that
// something did. Bounded, so a wrong expectation cannot flood a build log.
static void AKFixtureDumpLog(void) {
    NSUInteger from = AKFixtureLogLines.count > 12 ? AKFixtureLogLines.count - 12 : 0;
    for (NSUInteger index = from; index < AKFixtureLogLines.count; index++)
        fprintf(stderr, "   log: %s\n", AKFixtureLogLines[index].UTF8String);
    fflush(stderr);
}
// Every press that was sent has a release that was sent: the invariant the feature is built on.
static void AKFixtureAssertPressesHaveReleases(void) {
    NSUInteger presses = AKFixtureLogCount(@"event=press outcome=sent");
    NSUInteger releases = AKFixtureLogCount(@"event=release outcome=sent");
    if (presses != releases)
        fprintf(stderr, "TOUCH_PRESS_PAIRING_MISMATCH: presses=%lu releases=%lu\n",
                (unsigned long)presses, (unsigned long)releases);
    assert(presses == releases);
}
// No line may carry anything but a word in a known key: this is the boundary in the log.
static void TestTouchControllerLog(void) {
    NSString *line = AKTouchControllerLogLine(AKTouchControllerEventPress, @"sent",
        @{@"control": @"button",
          @"element": @"/etc/passwd",
          @"mode": @"two words",
          @"reason": [@"" stringByPaddingToLength:300 withString:@"a" startingAtIndex:0],
          @"secret": @"should-not-appear"});
    assert([line hasPrefix:@"[touch-controller] event=press outcome=sent "]);
    assert([line containsString:@"control=button"]);
    assert([line containsString:@"element=-"]);        // a path
    assert([line containsString:@"mode=-"]);           // a sentence
    assert([line containsString:@"reason=-"]);         // longer than any word
    assert(![line containsString:@"/etc"]);
    assert(![line containsString:@"should-not-appear"]); // a key that is not in the list
    assert(line.length < 160);
    // Every event has the spelling the log's readers expect.
    assert([AKTouchControllerEventName(AKTouchControllerEventLayout) isEqual:@"layout"]);
    assert([AKTouchControllerEventName(AKTouchControllerEventGesture) isEqual:@"gesture"]);
    assert([AKTouchControllerEventName(AKTouchControllerEventPress) isEqual:@"press"]);
    assert([AKTouchControllerEventName(AKTouchControllerEventRelease) isEqual:@"release"]);
    assert([AKTouchControllerEventName(AKTouchControllerEventThreshold) isEqual:@"threshold"]);
    assert([AKTouchControllerEventName(AKTouchControllerEventCancel) isEqual:@"cancel"]);
    assert([AKTouchControllerEventName(AKTouchControllerEventLifecycle) isEqual:@"lifecycle"]);
    puts("TOUCH_CONTROLLER_LOG_PASS: one tag, a closed key list, and a value that is not a short word is replaced before it reaches the line.");
}
// --- the layout's second schema -------------------------------------------------
static void TestLayoutSchema(void) {
    NSString *suite = [@"org.tolkara.touch2." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    NSString *key = @"WolkaraForeverTouchLayoutV1";
    CGRect bounds = CGRectMake(0,0,1000,500);
    CGRect defaultFrame = CGRectMake(0,0,56,44);
    AKFixtureBeginLog();
    // 1. Nothing stored: a fresh install is Full, and reading it writes nothing at all - so
    //    every default that depends on "nothing was saved" still holds (the shoulder order
    //    among them, which an update must not change for a new player).
    AKGamepadLayout *fresh = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(fresh.mode == AKGamepadLayoutModeFull && !fresh.stickButtonsEnabled && fresh.abilityZones.count == 0);
    assert(!fresh.newerThanThisBuild && [fresh.modeName isEqual:@"full"]);
    assert(fresh.swapShoulders);
    assert([defaults dictionaryForKey:key] == nil);
    assert(!AKFixtureLogHas(@"event=layout outcome=migrated"));
    // 2. A dictionary every release through v1.0.10 wrote: it becomes Full, and every value it
    //    carried is still there - the update must not move a control.
    [defaults removePersistentDomainForName:suite];
    AKFixtureBeginLog();
    [defaults setObject:@{@"opacity":@0.55,@"swapShoulders":@NO,@"positions":@{@"LB":@[@0.25,@0.10]}}
                 forKey:key];
    AKGamepadLayout *migrated = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(migrated.mode == AKGamepadLayoutModeFull && fabs(migrated.opacity-0.55) < 0.001 && !migrated.swapShoulders);
    CGRect moved = [migrated frameForItem:@"LB" defaultFrame:defaultFrame inBounds:bounds];
    assert(fabs(CGRectGetMinX(moved)-0.25*(1000-56)) < 0.5);
    assert(fabs(CGRectGetMinY(moved)-0.10*(500-44)) < 0.5);
    NSDictionary *upgraded = [defaults dictionaryForKey:key];
    assert([upgraded[@"version"] integerValue] == 2 && [upgraded[@"mode"] isEqual:@"full"]);
    assert(AKFixtureLogHas(@"event=layout outcome=migrated mode=full from=0 to=2"));
    // 3. A dictionary a *later* build wrote is read as defaults and never overwritten.
    [defaults removePersistentDomainForName:suite];
    NSDictionary *future = @{@"version":@3,@"mode":@"simple",@"stickButtons":@YES,
                             @"opacity":@0.4,@"positions":@{@"LB":@[@0,@0]}};
    [defaults setObject:future forKey:key];
    AKFixtureBeginLog();
    AKGamepadLayout *newer = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(newer.newerThanThisBuild && newer.mode == AKGamepadLayoutModeFull);
    assert(fabs(newer.opacity-0.8) < 0.001 && !newer.stickButtonsEnabled && newer.abilityZones.count == 0);
    assert(AKFixtureLogHas(@"event=layout outcome=refused reason=newer-schema"));
    newer.opacity = 0.1; [newer setModeName:@"simple"]; [newer save];
    assert([[defaults dictionaryForKey:key] isEqualToDictionary:future]);
    // 4. A mode this build does not ship is Full, never an experiment - in the dictionary and
    //    through the setter.
    for (id value in @[@"Simple", @"TURBO", @"", @42]) {
        [defaults setObject:@{@"version":@2,@"mode":value} forKey:key];
        assert([[AKGamepadLayout alloc] initWithDefaults:defaults].mode == AKGamepadLayoutModeFull);
    }
    [defaults setObject:@{@"version":@2,@"mode":@"full"} forKey:key];
    AKGamepadLayout *layout = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(![layout setModeName:@"turbo"] && layout.mode == AKGamepadLayoutModeFull);
    // 5. Simple and Full keep their own positions, and turning Simple off is a rollback that
    //    deletes nothing.
    assert([layout setModeName:@"simple"] && layout.mode == AKGamepadLayoutModeSimple);
    [layout moveItem:@"LB" toFrame:CGRectMake(0,0,56,44) inBounds:bounds];
    [layout save];
    AKGamepadLayout *simple = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(simple.mode == AKGamepadLayoutModeSimple);
    assert(CGRectEqualToRect([simple frameForItem:@"LB" defaultFrame:defaultFrame inBounds:bounds],
                             CGRectMake(0,0,56,44)));
    [simple setModeName:@"full"]; [simple save];
    AKGamepadLayout *full = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(full.mode == AKGamepadLayoutModeFull);
    assert(CGRectEqualToRect([full frameForItem:@"LB" defaultFrame:CGRectMake(300,40,56,44) inBounds:bounds],
                             CGRectMake(300,40,56,44)));
    NSDictionary *rollback = [defaults dictionaryForKey:key];
    assert(rollback[@"simplePositions"] && [rollback[@"simplePositions"][@"LB"] isKindOfClass:NSArray.class]);
    // 6. The stick buttons are off unless asked for, and the answer survives a relaunch.
    assert(!full.stickButtonsEnabled);
    full.stickButtonsEnabled = YES; [full save];
    assert([[AKGamepadLayout alloc] initWithDefaults:defaults].stickButtonsEnabled);
    // 7. An ability zone sends one button: a stick and a D-pad direction are refused, a place
    //    that is not two finite fractions is refused, a place off screen is brought inside, and
    //    six is the most.
    assert(![full addAbilityZoneForElement:GCInputLeftThumbstick atX:0.5 y:0.5]);
    assert(![full addAbilityZoneForElement:@"dpad.up" atX:0.5 y:0.5]);
    assert(![full addAbilityZoneForElement:@"Whatever" atX:0.5 y:0.5]);
    assert(![full addAbilityZoneForElement:GCInputButtonB atX:NAN y:0.5]);
    assert([full addAbilityZoneForElement:GCInputButtonA atX:0.5 y:0.5]);
    assert([full addAbilityZoneForElement:GCInputButtonB atX:2 y:-1]);
    assert(fabs([full.abilityZones[1][@"x"] doubleValue]-1) < 0.001 &&
           fabs([full.abilityZones[1][@"y"] doubleValue]-0) < 0.001);
    while (full.abilityZones.count < 6)
        assert([full addAbilityZoneForElement:GCInputRightShoulder atX:0.2 y:0.2]);
    assert(![full addAbilityZoneForElement:GCInputButtonX atX:0.5 y:0.5]);
    assert([full setAbilityZoneElement:GCInputButtonX atIndex:0]);
    assert(![full setAbilityZoneElement:@"dpad.left" atIndex:0]);
    assert(![full setAbilityZoneElement:GCInputButtonX atIndex:99]);
    assert([full moveAbilityZoneAtIndex:0 toX:0.1 y:0.9]);
    [full save];
    AKGamepadLayout *zones = [[AKGamepadLayout alloc] initWithDefaults:defaults];
    assert(zones.abilityZones.count == 6);
    assert([zones.abilityZones[0][@"element"] isEqual:GCInputButtonX]);
    assert(fabs([zones.abilityZones[0][@"x"] doubleValue]-0.1) < 0.001);
    [zones removeAbilityZoneAtIndex:0];
    assert(zones.abilityZones.count == 5);
    // A hand-edited arrangement cannot smuggle in a zone that is not a button.
    [zones applyArrangement:@{@"abilityZones":@[@{@"element":GCInputLeftThumbstick,@"x":@0.5,@"y":@0.5},
                                               @{@"element":GCInputButtonA,@"x":@0.5,@"y":@0.5}]}];
    assert(zones.abilityZones.count == 1 && [zones.abilityZones[0][@"element"] isEqual:GCInputButtonA]);
    [zones clearAbilityZones];
    assert(zones.abilityZones.count == 0);
    // 8. A template is about sticks and reserved areas, not about the arrangement, and a saved
    //    profile carries everything the layout is - including the mode.
    [zones setModeName:@"simple"];
    [zones applyTemplateNamed:@"plain"];
    assert(zones.mode == AKGamepadLayoutModeSimple);
    assert([zones saveAsProfileNamed:@"touch2-profile"]);
    [zones setModeName:@"full"];
    assert([zones applyProfileNamed:@"touch2-profile"]);
    assert(zones.mode == AKGamepadLayoutModeSimple && zones.stickButtonsEnabled);
    [zones deleteProfileNamed:@"touch2-profile"];
    [defaults removePersistentDomainForName:suite];
    AKFixtureEndLog();
    puts("TOUCH_LAYOUT_SCHEMA_PASS: an old dictionary migrates to Full with everything it carried, a newer one is never rewritten, an unknown mode is Full, Simple keeps its own positions and turning it off deletes nothing, and only buttons may become ability zones.");
}
// --- the direct camera ----------------------------------------------------------
static void AKFixtureCameraEmit(void *context, AKTrackpadAction action, double x, double y, unsigned button) {
    NSMutableArray<NSString *> *events = (__bridge NSMutableArray<NSString *> *)context;
    switch (action) {
        case AKTrackpadDown: [events addObject:[NSString stringWithFormat:@"down%u",button]]; break;
        case AKTrackpadUp: [events addObject:[NSString stringWithFormat:@"up%u",button]]; break;
        case AKTrackpadMove: [events addObject:[NSString stringWithFormat:@"move%.1f,%.1f",x,y]]; break;
        case AKTrackpadScroll: [events addObject:[NSString stringWithFormat:@"scroll%.1f,%.1f",x,y]]; break;
    }
}
// The camera is a gesture with an end. Every one of these traces is a sequence UIKit can
// produce, and the point of each is what the *next* touch does after it.
static void TestDirectCamera(void) {
    AKTouchCameraGesture camera = {0};
    NSMutableArray<NSString *> *events = [NSMutableArray new];
    void *context = (__bridge void *)events;
    CGSize surface = CGSizeMake(1000,500);
    AKFixtureBeginLog();
    // A tap where the finger was: one press, one release, no motion.
    AKTouchCameraUpdate(&camera,1,100,100,1,surface,AKFixtureCameraEmit,context);
    AKTouchCameraUpdate(&camera,0,0,0,1.1,surface,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down0",@"up0"]]));
    assert(!AKTouchCameraIsActive(&camera));
    // Hold, then drag: one press, the motion, one release. The threshold hand-off is reported
    // once, and only once.
    [events removeAllObjects];
    AKTouchCameraUpdate(&camera,1,100,100,2,surface,AKFixtureCameraEmit,context);
    assert(AKTouchCameraHold(&camera,2.5,AKFixtureCameraEmit,context));
    assert(!AKTouchCameraHold(&camera,2.6,AKFixtureCameraEmit,context)); // already dragging
    AKTouchCameraUpdate(&camera,1,110,104,2.6,surface,AKFixtureCameraEmit,context);
    AKTouchCameraUpdate(&camera,0,0,0,2.7,surface,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down0",@"move10.0,4.0",@"up0"]]));
    assert(AKFixtureLogCount(@"event=threshold outcome=handoff") == 1);
    // A centroid jump is a new gesture, not a drag: the held button is released exactly once,
    // nothing is moved by the jump, and the camera answers the very next movement - which is
    // what makes a recentered pointer survivable.
    [events removeAllObjects];
    AKTouchCameraUpdate(&camera,1,100,100,3,surface,AKFixtureCameraEmit,context);
    assert(AKTouchCameraHold(&camera,3.5,AKFixtureCameraEmit,context));
    AKTouchCameraUpdate(&camera,1,900,400,3.6,surface,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down0",@"up0"]]));
    assert(AKFixtureLogHas(@"event=threshold outcome=rebased"));
    AKTouchCameraUpdate(&camera,1,905,402,3.7,surface,AKFixtureCameraEmit,context);
    assert([events.lastObject isEqual:@"move5.0,2.0"]);
    AKTouchCameraUpdate(&camera,0,0,0,3.8,surface,AKFixtureCameraEmit,context);
    // Every exit the *app* causes is one release and nothing left behind, and the next touch
    // is a camera drag immediately. Each pass uses its own clock, because a finger trace that
    // goes back in time is itself a cancellation.
    NSTimeInterval clock = 10;
    for (NSString *reason in @[@"background",@"resign",@"resize",@"settings",@"controller",@"teardown"]) {
        [events removeAllObjects];
        AKTouchCameraUpdate(&camera,1,300,200,clock,surface,AKFixtureCameraEmit,context);
        assert(AKTouchCameraHold(&camera,clock+0.5,AKFixtureCameraEmit,context));
        AKTouchCameraReset(&camera,reason,AKFixtureCameraEmit,context);
        assert(([events isEqual:@[@"down0",@"up0"]]));
        assert(!AKTouchCameraIsActive(&camera));
        // A second reset on a gesture that is already gone emits nothing at all.
        AKTouchCameraReset(&camera,reason,AKFixtureCameraEmit,context);
        assert(events.count == 2);
        AKTouchCameraUpdate(&camera,1,320,210,clock+1,surface,AKFixtureCameraEmit,context);
        AKTouchCameraUpdate(&camera,1,330,214,clock+1.1,surface,AKFixtureCameraEmit,context);
        assert([events.lastObject isEqual:@"move10.0,4.0"]);
        AKTouchCameraUpdate(&camera,0,0,0,clock+1.2,surface,AKFixtureCameraEmit,context);
        clock += 10;
    }
    // A *cancelled* touch is the platform's rule, not the app's: the held button is released
    // once, and then the rest of that gesture is suppressed until every finger is lifted. The
    // leftover finger must not become camera motion - that is the jump `AKTrackpadCancel`
    // blocks, and this app keeps it.
    [events removeAllObjects];
    clock = 200;
    AKTouchCameraUpdate(&camera,1,300,200,clock,surface,AKFixtureCameraEmit,context);
    assert(AKTouchCameraHold(&camera,clock+0.5,AKFixtureCameraEmit,context));
    AKTouchCameraReset(&camera,@"cancelled",AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down0",@"up0"]]));
    assert(AKTouchCameraIsActive(&camera));            // the finger is still down
    AKTouchCameraUpdate(&camera,1,360,240,clock+1,surface,AKFixtureCameraEmit,context);
    assert(events.count == 2);                          // and it does not drag the camera
    AKTouchCameraUpdate(&camera,0,0,0,clock+1.1,surface,AKFixtureCameraEmit,context);
    assert(events.count == 2);                          // lifting it is not a click either
    assert(!AKTouchCameraIsActive(&camera));
    AKTouchCameraUpdate(&camera,1,320,210,clock+2,surface,AKFixtureCameraEmit,context);
    AKTouchCameraUpdate(&camera,1,330,214,clock+2.1,surface,AKFixtureCameraEmit,context);
    assert([events.lastObject isEqual:@"move10.0,4.0"]); // a new touch drags at once
    AKTouchCameraUpdate(&camera,0,0,0,clock+2.2,surface,AKFixtureCameraEmit,context);
    assert(AKFixtureLogHas(@"event=lifecycle outcome=cleanup reason=background"));
    assert(AKFixtureLogHas(@"event=cancel outcome=cancelled"));
    // Everything above is paired, press for release, before the one case that has no delegate
    // left to tell.
    AKFixtureAssertPressesHaveReleases();
    // Teardown: the delegate may already be gone, so nothing is emitted - but the gesture is
    // still cleared, so nothing can answer a later frame.
    AKTouchCameraUpdate(&camera,1,300,200,1000,surface,AKFixtureCameraEmit,context);
    AKTouchCameraReset(&camera,@"teardown",NULL,NULL);
    assert(!AKTouchCameraIsActive(&camera));
    AKFixtureEndLog();
    puts("TOUCH_CAMERA_LIFECYCLE_PASS: a tap clicks once, a hold drags, a centroid jump is rebased with one release and the next movement still turns the camera, every exit the app causes releases once and leaves nothing behind, and a cancelled touch releases once and then stays suppressed until the finger lifts, as it always has.");
}
// --- the arrangement, the stick buttons and the zones, through the real controls ---
// A control by name, drawn or not: the identifier the gamepad gives its own controls, without
// the helper that insists a control is visible.
static UIView *GamepadControl(UIView *host, NSString *name) {
    return Find(host, [@"tolkara.gamepad." stringByAppendingString:name]);
}
static void TestTouchControllerTwo(UIView *host, AKPreviewGamepad *manager);
static void TestNativeInput(UIView *host, AKPreviewGamepad *manager) {
    GCExtendedGamepad *pad=manager.created.controller.extendedGamepad;
    assert(pad && manager.visible);
    [host layoutIfNeeded];
    // The mobile interface starts with the sticks and the jump only, because a phone's gamepad
    // buttons cover the game; Standard starts with every button, as every release through
    // v1.0.7 has. The nine-button layout below is what this function tests, so mobile turns the
    // arrangement off - and its default is asserted here, where the switch first exists.
    if (AKInterfaceModeIsMobile()) {
        [manager toggleSettings];
        UISwitch *sticksOnly=(id)Find(host,@"wolkaraforever.controls.sticksOnly");
        assert(sticksOnly && sticksOnly.on);
        sticksOnly.on=NO; [sticksOnly sendActionsForControlEvents:UIControlEventValueChanged];
        [manager toggleSettings]; [host layoutIfNeeded];
    }
    // Ring sectors own their visible area, leave the stick and separator gaps
    // untouched, and put + on the same row as the bottom labels.
    UIButton *top=(id)Button(host,@"dpad.up");
    CALayer *guestSurface=[CALayer layer];
    guestSurface.frame=host.bounds; [host.layer addSublayer:guestSurface];
    assert(top.superview.superview.layer.zPosition > guestSurface.zPosition);
    [guestSurface removeFromSuperlayer];
    assert([top pointInside:CGPointMake(108,26) withEvent:nil]);
    assert(![top pointInside:CGPointMake(108,108) withEvent:nil]);
    assert(![top pointInside:CGPointMake(26,108) withEvent:nil]);
    assert(![top pointInside:CGPointMake(166,50) withEvent:nil]);
    // Mobile only, and only while the interface is on: the app's toolbar then has the bottom
    // centre (44 pt tall, 8 pt up), so + is centred just above it instead of sharing the
    // bottom labels' row. Standard keeps the row it has always had.
    UIButton *a=(id)Button(host,GCInputButtonA), *plus=(id)Button(host,GCInputButtonMenu);
    if (AKInterfaceModeIsMobile()) {
        CGRect plusFrame=[plus convertRect:plus.bounds toView:host];
        assert(fabs(CGRectGetMidX(plusFrame)-CGRectGetMidX(host.bounds))<1);
        assert(CGRectGetMaxY(plusFrame)<=CGRectGetMaxY(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets))-8-44-4);
    } else {
        assert(fabs([a convertPoint:a.titleLabel.center toView:host].y-[plus convertPoint:plus.titleLabel.center toView:host].y)<1);
    }
    assert(Find(host,@"tolkara.gamepad.minus")==nil);
    NSArray *names=@[GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,GCInputLeftShoulder,
        GCInputRightShoulder,GCInputLeftTrigger,GCInputRightTrigger,GCInputButtonMenu];
    for (NSString *name in names) {
        UIControl *button=Button(host,name);
        NSUInteger pulses=manager.feedback.buttons;
        assert(CGRectContainsRect(host.bounds,[button convertRect:button.bounds toView:host]));
        [button sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
        assert(manager.created.controller.physicalInputProfile.buttons[name].value==1);
        assert(manager.feedback.buttons==pulses+1);
        [button sendActionsForControlEvents:UIControlEventTouchDown];
        assert(manager.feedback.buttons==pulses+1); // Still held, no new press.
        [button sendActionsForControlEvents:UIControlEventTouchUpOutside]; Drain();
        assert(manager.created.controller.physicalInputProfile.buttons[name].value==0);
        assert(manager.feedback.buttons==pulses+1); // Releasing is silent.
    }
    UIControl *up=Button(host,@"dpad.up"), *right=Button(host,@"dpad.right"), *left=Button(host,@"dpad.left");
    [up sendActionsForControlEvents:UIControlEventTouchDown];
    [right sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.dpad.xAxis.value==1 && pad.dpad.yAxis.value==1);
    [up sendActionsForControlEvents:UIControlEventTouchCancel]; Drain();
    assert(pad.dpad.xAxis.value==1 && pad.dpad.yAxis.value==0);
    [left sendActionsForControlEvents:UIControlEventTouchDown]; Drain(); assert(pad.dpad.xAxis.value==0);
    [left sendActionsForControlEvents:UIControlEventTouchUpInside];
    [right sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain(); assert(pad.dpad.xAxis.value==0);
    UIControl *leftStick=(id)Find(host,@"tolkara.gamepad.leftStick"), *rightStick=(id)Find(host,@"tolkara.gamepad.rightStick");
    AKFixtureTouch *touch=[AKFixtureTouch new]; touch.point=CGPointMake(leftStick.bounds.size.width,leftStick.bounds.size.height/2);
    assert([leftStick beginTrackingWithTouch:touch withEvent:nil]);
    touch.point=CGPointZero; assert([rightStick beginTrackingWithTouch:touch withEvent:nil]);
    [Button(host,GCInputLeftShoulder) sendActionsForControlEvents:UIControlEventTouchDown];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.leftThumbstick.xAxis.value==1 && pad.leftThumbstick.yAxis.value==0);
    assert(manager.feedback.limits==2);
    [leftStick continueTrackingWithTouch:touch withEvent:nil]; // Move around rim.
    assert(manager.feedback.limits==2);
    [leftStick cancelTrackingWithEvent:nil];
    [leftStick beginTrackingWithTouch:touch withEvent:nil];
    assert(manager.feedback.limits==3);
    assert(pad.rightThumbstick.xAxis.value < -0.70 && pad.rightThumbstick.yAxis.value > 0.70);
    assert(pad.leftShoulder.pressed && pad.buttonA.pressed);
    // The empty surface continues to belong to the existing trackpad/guest.
    assert([host hitTest:CGPointMake(host.bounds.size.width/2,host.bounds.size.height/2) withEvent:nil]==host);
    // Entering settings releases held inputs and prevents editing from sending
    // gameplay input. Preferences and dragged positions survive a new model.
    [manager toggleSettings]; [host layoutIfNeeded]; Drain();
    assert(!pad.leftShoulder.pressed && !pad.buttonA.pressed && pad.leftThumbstick.xAxis.value==0);
    assert(Find(host,@"wolkaraforever.controls.settings"));
    UIView *panel=Find(host,@"wolkaraforever.controls.settings");
    if (UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets).size.width>=620) assert(panel.bounds.size.width>390);
    // Mobile: the app's toolbar sits at the bottom centre, 44 pt tall and 8 pt up, so the
    // sheet hangs from the top and leaves that strip free. Standard: it hangs from the
    // bottom, under the toolbar that is at the top.
    if (AKInterfaceModeIsMobile()) {
        CGFloat toolbarTop=CGRectGetMaxY(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets))-8-44;
        assert(CGRectGetMaxY([panel convertRect:panel.bounds toView:host])<=toolbarTop+0.5);
        assert(fabs(CGRectGetMinY([panel convertRect:panel.bounds toView:host])-CGRectGetMinY(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets))-8)<=0.5);
    }
    CGRect normalBounds=host.bounds;
    host.bounds=CGRectMake(0,0,390,600); [host layoutIfNeeded];
    assert(CGRectContainsRect(host.bounds,[panel convertRect:panel.bounds toView:host]));
    UIView *done=Find(host,@"wolkaraforever.controls.done");
    assert(done && CGRectContainsRect(panel.bounds,[done convertRect:done.bounds toView:panel]));
    host.bounds=normalBounds; [host layoutIfNeeded];
    UISwitch *outer=(id)Find(host,@"wolkaraforever.controls.swapShoulders");
    // Said out loud when it is not the row this fixture expects: a missing row and a row that
    // is on are different faults, and the message has to say which one happened.
    if (!outer || outer.on) {
        AKGamepadLayout *current=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        fprintf(stderr, "TOUCH_SWAP_ROW_MISMATCH: found=%d on=%d mode=%s swapShoulders=%d\n",
                outer != nil, outer.on, current.modeName.UTF8String, current.swapShoulders);
        fflush(stderr);
    }
    assert(outer && !outer.on);
    assert(CGRectGetMidX(Button(host,GCInputLeftTrigger).frame)>CGRectGetMidX(Button(host,GCInputLeftShoulder).frame));
    assert(CGRectGetMidX(Button(host,GCInputRightTrigger).frame)<CGRectGetMidX(Button(host,GCInputRightShoulder).frame));
    outer.on=YES; [outer sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    assert(CGRectGetMidX(Button(host,GCInputLeftTrigger).frame)<CGRectGetMidX(Button(host,GCInputLeftShoulder).frame));
    assert(CGRectGetMidX(Button(host,GCInputRightTrigger).frame)>CGRectGetMidX(Button(host,GCInputRightShoulder).frame));
    assert(![[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults].swapShoulders);
    outer.on=NO; [outer sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    NSUInteger silentButtons=manager.feedback.buttons, silentLimits=manager.feedback.limits;
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(!pad.buttonA.pressed);
    assert(!manager.feedback.enabled && manager.feedback.buttons==silentButtons && manager.feedback.limits==silentLimits);
    UISwitch *haptics=(id)Find(host,@"wolkaraforever.controls.haptics"); assert(haptics.on);
    haptics.on=NO; [haptics sendActionsForControlEvents:UIControlEventValueChanged];
    UISwitch *overlay=(id)Find(host,@"wolkaraforever.controls.performanceOverlay");
    assert(overlay && !overlay.on);
    overlay.on=YES; [overlay sendActionsForControlEvents:UIControlEventValueChanged];
    UISlider *scale=(id)Find(host,@"wolkaraforever.controls.frontScale");
    scale.value=1.3; [scale sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    UIView *cluster=Find(host,@"wolkaraforever.layout.left"); assert(cluster.frame.size.width>216);
    UISlider *opacity=(id)Find(host,@"wolkaraforever.controls.transparency");
    opacity.value=.7; [opacity sendActionsForControlEvents:UIControlEventValueChanged];
    assert(fabs(cluster.alpha-.3)<.001);
    UISwitch *edit=(id)Find(host,@"wolkaraforever.controls.edit");
    edit.on=YES; [edit sendActionsForControlEvents:UIControlEventValueChanged]; [host layoutIfNeeded];
    assert(!Find(host,@"wolkaraforever.controls.settings"));
    // Standalone buttons must remain hit-testable for their pan recognizer;
    // disabling them would allow groups to move but trap shoulders and +.
    for (NSString *name in @[GCInputLeftTrigger,GCInputLeftShoulder,GCInputRightTrigger,GCInputRightShoulder,GCInputButtonMenu]) {
        UIControl *button=Button(host,name);
        assert(button.enabled);
        CGPoint center=[button convertPoint:CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds)) toView:host];
        assert([host hitTest:center withEvent:nil]==button);
        [button sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
        assert(manager.created.controller.physicalInputProfile.buttons[name].value==0);
        assert(manager.feedback.buttons==silentButtons && manager.feedback.limits==silentLimits);
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        AKFixturePan *buttonPan=[AKFixturePan new]; [button addGestureRecognizer:buttonPan];
        UIView *overlay=button.superview; CGRect original=button.frame;
        buttonPan.testState=UIGestureRecognizerStateBegan; [overlay drag:buttonPan];
        buttonPan.movement=CGPointMake(12,20); buttonPan.testState=UIGestureRecognizerStateChanged; [overlay drag:buttonPan];
        buttonPan.testState=UIGestureRecognizerStateEnded; [overlay drag:buttonPan];
        assert(!CGRectEqualToRect(button.frame,original));
        [button removeGestureRecognizer:buttonPan];
    }
    CGRect before=cluster.frame;
    AKFixturePan *pan=[AKFixturePan new]; [cluster addGestureRecognizer:pan];
    pan.testState=UIGestureRecognizerStateBegan; [cluster.superview drag:pan];
    pan.movement=CGPointMake(120,-40); pan.testState=UIGestureRecognizerStateChanged; [cluster.superview drag:pan];
    pan.testState=UIGestureRecognizerStateEnded; [cluster.superview drag:pan];
    assert(cluster.frame.origin.x>before.origin.x && cluster.frame.origin.y<before.origin.y);
    [cluster removeGestureRecognizer:pan];
    // Dragging a swapped trigger updates its visual slot, not the other button.
    UIControl *trigger=Button(host,GCInputLeftTrigger);
    CGRect triggerBefore=trigger.frame;
    AKFixturePan *triggerPan=[AKFixturePan new]; [trigger addGestureRecognizer:triggerPan];
    triggerPan.testState=UIGestureRecognizerStateBegan; [trigger.superview drag:triggerPan];
    triggerPan.movement=CGPointMake(30,60); triggerPan.testState=UIGestureRecognizerStateEnded;
    [trigger.superview drag:triggerPan]; [host layoutIfNeeded];
    assert(trigger.frame.origin.x>triggerBefore.origin.x && trigger.frame.origin.y>triggerBefore.origin.y);
    AKGamepadLayout *dragged=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    CGRect safe=UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets);
    assert(CGRectEqualToRect([dragged frameForItem:@"LB" defaultFrame:trigger.frame inBounds:safe],trigger.frame));
    [trigger removeGestureRecognizer:triggerPan];
    AKGamepadLayout *saved=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    assert(fabs(saved.frontScale-1.3)<.001 && fabs(saved.opacity-.3)<.001);
    assert(!saved.hapticsEnabled && saved.performanceOverlayEnabled && saved.swapShoulders);
    [(UIButton *)Find(host,@"wolkaraforever.layout.done") sendActionsForControlEvents:UIControlEventTouchUpInside];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.buttonA.pressed && manager.feedback.buttons==silentButtons);
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchUpInside];
    [manager toggleSettings];
    [(UIButton *)Find(host,@"wolkaraforever.controls.reset") sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(((UISwitch *)Find(host,@"wolkaraforever.controls.haptics")).on);
    assert(!((UISwitch *)Find(host,@"wolkaraforever.controls.performanceOverlay")).on);
    // The sticks-only switch exists only where sticks-only does.
    UISwitch *sticksOnly=(id)Find(host,@"wolkaraforever.controls.sticksOnly");
    if (AKInterfaceModeIsMobile()) {
        assert(sticksOnly.on);
        sticksOnly.on=NO; [sticksOnly sendActionsForControlEvents:UIControlEventValueChanged];
    } else {
        assert(sticksOnly==nil);
    }
    [manager toggleSettings]; [host layoutIfNeeded];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(manager.feedback.buttons==silentButtons+1 && manager.feedback.enabled);
    assert(fabs(cluster.frame.size.width-216)<.01);
    assert(CGRectGetMidX(Button(host,GCInputLeftTrigger).frame)>CGRectGetMidX(Button(host,GCInputLeftShoulder).frame));
    assert(CGRectGetMidX(Button(host,GCInputRightTrigger).frame)<CGRectGetMidX(Button(host,GCInputRightShoulder).frame));
    TestPreferences();
    // Sticks-only is a mobile arrangement: Standard has no switch to turn it on with.
    if (AKInterfaceModeIsMobile()) { TestJumpReach(host,manager); TestFloating(host,manager); }
    TestTouchControllerTwo(host,manager);
    manager.keyboardVisible=YES; Drain();
    assert(!manager.visible && !pad.leftShoulder.pressed && !pad.buttonA.pressed);
    assert(!manager.feedback.enabled);
    assert(pad.leftThumbstick.xAxis.value==0 && pad.rightThumbstick.yAxis.value==0);
    [leftStick cancelTrackingWithEvent:nil]; [rightStick cancelTrackingWithEvent:nil];
    [manager invalidate];
    puts("TOUCH_GAMEPAD_INPUT_PASS: all nine buttons, D-pad diagonals/opposition/cancel, both sticks, held modifiers, neutral reset and trackpad passthrough.");
}
// --- the arrangement, the stick buttons and the zones, through the real controls ---
static void TestTouchControllerTwo(UIView *host, AKPreviewGamepad *manager) {
    AKFixtureBeginLog();
    // The panel is the only place these are turned on, so it is where the test stands.
    [manager toggleSettings]; [host layoutIfNeeded];
    UISwitch *simpleSwitch = (id)Find(host,@"wolkaraforever.controls.simpleLayout");
    UISwitch *stickSwitch = (id)Find(host,@"wolkaraforever.controls.stickButtons");
    UIButton *addZone = (id)Find(host,@"wolkaraforever.controls.addAbilityZone");
    UIButton *clearZones = (id)Find(host,@"wolkaraforever.controls.clearAbilityZones");
    assert(simpleSwitch && stickSwitch && addZone && clearZones);
    assert(!simpleSwitch.on && !stickSwitch.on && !clearZones.enabled);
    // Full is what an existing installation has: the triggers and the D-pad are drawn.
    assert(!GamepadControl(host,GCInputLeftTrigger).hidden && !GamepadControl(host,@"dpad.up").hidden);
    simpleSwitch.on = YES; [simpleSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    [manager toggleSettings]; [host layoutIfNeeded];
    // Simple draws both sticks, the four face buttons, both shoulders and the menu - and not
    // the triggers or the D-pad. Said out loud when it is not so, because "missing" and
    // "still drawn" are different faults.
    UIView *leftTrigger = GamepadControl(host,GCInputLeftTrigger), *rightTrigger = GamepadControl(host,GCInputRightTrigger);
    UIView *dpadUp = GamepadControl(host,@"dpad.up"), *dpadLeft = GamepadControl(host,@"dpad.left");
    if (!leftTrigger.hidden || !rightTrigger.hidden || !dpadUp.hidden || !dpadLeft.hidden) {
        AKGamepadLayout *current = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        fprintf(stderr, "TOUCH_SIMPLE_MISMATCH: mode=%s found=%d/%d/%d/%d hidden=%d/%d/%d/%d\n",
                current.modeName.UTF8String, leftTrigger != nil, rightTrigger != nil, dpadUp != nil, dpadLeft != nil,
                (int)leftTrigger.hidden, (int)rightTrigger.hidden, (int)dpadUp.hidden, (int)dpadLeft.hidden);
        fflush(stderr);
    }
    assert(leftTrigger && rightTrigger && leftTrigger.hidden && rightTrigger.hidden);
    assert(dpadUp.hidden && dpadLeft.hidden);
    for (NSString *name in @[GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,
                             GCInputLeftShoulder,GCInputRightShoulder,GCInputButtonMenu])
        assert(!GamepadControl(host,name).hidden);
    assert(!Find(host,@"tolkara.gamepad.leftStick").hidden);
    // The shoulders sit at the far corners in Simple, where the triggers used to be - and a
    // control that is not placed is not drawn, so the frame is measured, not just the flag.
    UIView *leftShoulder = GamepadControl(host,GCInputLeftShoulder);
    UIView *rightShoulder = GamepadControl(host,GCInputRightShoulder);
    CGRect shoulderFrame = [leftShoulder convertRect:leftShoulder.bounds toView:host];
    CGRect rightShoulderFrame = [rightShoulder convertRect:rightShoulder.bounds toView:host];
    if (shoulderFrame.size.width < 20 || shoulderFrame.size.height < 20 ||
        rightShoulderFrame.size.width < 20 || CGRectGetMaxX(rightShoulderFrame) > host.bounds.size.width) {
        fprintf(stderr, "TOUCH_SIMPLE_SHOULDER_FRAME: left=%.0fx%.0f at %.0f right=%.0fx%.0f at %.0f host=%.0f\n",
                shoulderFrame.size.width, shoulderFrame.size.height, CGRectGetMinX(shoulderFrame),
                rightShoulderFrame.size.width, rightShoulderFrame.size.height, CGRectGetMaxX(rightShoulderFrame),
                host.bounds.size.width);
        fflush(stderr);
    }
    assert(shoulderFrame.size.width > 20 && shoulderFrame.size.height > 20);
    assert(rightShoulderFrame.size.width > 20 && CGRectGetMaxX(rightShoulderFrame) <= host.bounds.size.width);
    assert(CGRectGetMinX(shoulderFrame) < host.bounds.size.width * 0.25);
    assert(CGRectGetMidX(rightShoulderFrame) > host.bounds.size.width * 0.75);
    // Turning it off restores Full exactly: the same code path, the same saved positions.
    [manager toggleSettings]; [host layoutIfNeeded];
    simpleSwitch = (id)Find(host,@"wolkaraforever.controls.simpleLayout");
    assert(simpleSwitch.on);
    // Triggers on the outside is a choice about controls Simple does not draw: the row stays
    // where it is and its switch cannot be used.
    UISwitch *swapRow = (id)Find(host, @"wolkaraforever.controls.swapShoulders");
    if (!swapRow || swapRow.enabled) {
        AKGamepadLayout *current = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        fprintf(stderr, "TOUCH_SWAP_ROW_MISMATCH: found=%d enabled=%d mode=%s panel=%d\n",
                swapRow != nil, (int)swapRow.enabled, current.modeName.UTF8String,
                Find(host,@"wolkaraforever.controls.settings") != nil);
        fflush(stderr);
    }
    assert(swapRow && !swapRow.enabled);
    simpleSwitch.on = NO; [simpleSwitch sendActionsForControlEvents:UIControlEventValueChanged];
    [host layoutIfNeeded];
    assert(swapRow.enabled);
    [manager toggleSettings]; [host layoutIfNeeded];
    assert(!GamepadControl(host,GCInputLeftTrigger).hidden && !GamepadControl(host,@"dpad.up").hidden);
    // A stick button is a double tap, and only that. Measured first: the controller this app
    // creates has no stick button at all - Apple's virtual controller's extended profile is the
    // face buttons, the shoulders, the triggers, the menu, the D-pad and the sticks' directions
    // and nothing else - so off it is, the row that owns it says it cannot be used, and a
    // gesture that asks for it is refused rather than pretended.
    UIControl *leftStick = (id)Find(host,@"tolkara.gamepad.leftStick");
    CGPoint middle = CGPointMake(CGRectGetMidX(leftStick.bounds),CGRectGetMidY(leftStick.bounds));
    AKFixtureTouch *first = [AKFixtureTouch new], *second = [AKFixtureTouch new];
    first.point = second.point = middle;
    [manager toggleSettings]; [host layoutIfNeeded];
    stickSwitch = (id)Find(host,@"wolkaraforever.controls.stickButtons");
    assert(stickSwitch && !stickSwitch.on && !stickSwitch.enabled);
    assert(stickSwitch.accessibilityHint.length);        // it says why it cannot be used
    [manager toggleSettings]; [host layoutIfNeeded];
    first.when = 100; [leftStick beginTrackingWithTouch:first withEvent:nil];
    first.when = 100.06; [leftStick endTrackingWithTouch:first withEvent:nil]; Drain();
    second.when = 100.14; [leftStick beginTrackingWithTouch:second withEvent:nil];
    second.when = 100.20; [leftStick endTrackingWithTouch:second withEvent:nil]; Drain();
    assert(AKFixtureLogHas(@"event=gesture outcome=refused control=leftStick reason=disabled"));
    // Turned on in the layout by a controller that could carry it, the same double tap is
    // refused for the other reason: this one has nowhere to send it.
    AKGamepadLayout *layout = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    layout.stickButtonsEnabled = YES; [layout save];
    [manager reloadLayout]; [host layoutIfNeeded];
    first.when = 200; [leftStick beginTrackingWithTouch:first withEvent:nil];
    first.when = 200.06; [leftStick endTrackingWithTouch:first withEvent:nil]; Drain();
    second.when = 200.14; [leftStick beginTrackingWithTouch:second withEvent:nil];
    second.when = 200.20; [leftStick endTrackingWithTouch:second withEvent:nil]; Drain();
    assert(AKFixtureLogHas(@"event=gesture outcome=refused control=leftStick reason=unsupported"));
    assert(!AKFixtureLogHas(@"event=press outcome=sent control=stickButton"));
    // Given a controller that does carry the element - which is what the fixture's own
    // override stands in for - the gesture is exactly one press of the stick's own button and
    // one release, on a timer, and a single tap or a drag is neither.
    manager.forceStickButtons = YES;
    [manager reloadLayout]; [host layoutIfNeeded];
    [manager toggleSettings]; [host layoutIfNeeded];
    stickSwitch = (id)Find(host,@"wolkaraforever.controls.stickButtons");
    assert(stickSwitch.enabled && stickSwitch.on);
    [manager toggleSettings]; [host layoutIfNeeded];
    first.when = 300; [leftStick beginTrackingWithTouch:first withEvent:nil];
    first.when = 300.06; [leftStick endTrackingWithTouch:first withEvent:nil]; Drain();
    assert(!AKFixtureLogHas(@"event=press outcome=sent control=stickButton element=leftThumbstickButton"));
    assert(AKFixtureLogHas(@"event=gesture outcome=armed control=leftStick"));
    AKFixtureTouch *drag = [AKFixtureTouch new];
    drag.point = middle; drag.when = 301;
    [leftStick beginTrackingWithTouch:drag withEvent:nil];
    drag.when = 301.04; drag.point = CGPointMake(middle.x+40,middle.y);
    [leftStick continueTrackingWithTouch:drag withEvent:nil];
    drag.when = 301.08; [leftStick endTrackingWithTouch:drag withEvent:nil]; Drain();
    assert(!AKFixtureLogHas(@"event=press outcome=sent control=stickButton"));
    first.when = 400; [leftStick beginTrackingWithTouch:first withEvent:nil];
    first.when = 400.05; [leftStick endTrackingWithTouch:first withEvent:nil];
    second.when = 400.12; [leftStick beginTrackingWithTouch:second withEvent:nil];
    second.when = 400.18; [leftStick endTrackingWithTouch:second withEvent:nil]; Drain();
    if (!AKFixtureLogHas(@"event=gesture outcome=recognized control=leftStick element=leftThumbstickButton"))
        AKFixtureDumpLog();
    assert(AKFixtureLogHas(@"event=gesture outcome=recognized control=leftStick element=leftThumbstickButton"));
    assert(AKFixtureLogHas(@"event=press outcome=sent control=stickButton element=leftThumbstickButton"));
    // Let the bounded hold expire: it is off again with no finger on it.
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 1;
    while (!AKFixtureLogHas(@"event=release outcome=sent control=stickButton element=leftThumbstickButton reason=expired") &&
           NSProcessInfo.processInfo.systemUptime < deadline) Drain();
    assert(AKFixtureLogHas(@"event=release outcome=sent control=stickButton element=leftThumbstickButton reason=expired"));
    // A press whose gesture is taken away is released, once, not left on.
    first.when = 500; [leftStick beginTrackingWithTouch:first withEvent:nil];
    first.when = 500.05; [leftStick endTrackingWithTouch:first withEvent:nil];
    second.when = 500.12; [leftStick beginTrackingWithTouch:second withEvent:nil];
    second.when = 500.18; [leftStick endTrackingWithTouch:second withEvent:nil]; Drain();
    manager.keyboardVisible = YES; Drain();
    if (!AKFixtureLogHas(@"event=release outcome=sent control=stickButton element=leftThumbstickButton"))
        AKFixtureDumpLog();
    assert(AKFixtureLogHas(@"event=release outcome=sent control=stickButton element=leftThumbstickButton"));
    manager.keyboardVisible = NO; Drain();
    assert(WaitUntil(^{ return manager.visible; }));
    // Back to what an installation has: the preference off, so the row is off again too, and
    // the rest of the fixture measures the arrangement it expects.
    layout = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    layout.stickButtonsEnabled = NO; [layout save];
    manager.forceStickButtons = NO;
    [manager reloadLayout]; [host layoutIfNeeded];
    // An ability zone is a button you place: press it, and one virtual press goes out; lift it,
    // and one release follows. Nothing else is ever sent.
    [manager toggleSettings]; [host layoutIfNeeded];
    addZone = (id)Find(host,@"wolkaraforever.controls.addAbilityZone");
    clearZones = (id)Find(host,@"wolkaraforever.controls.clearAbilityZones");
    [addZone sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(clearZones.enabled);
    [manager toggleSettings]; [host layoutIfNeeded];
    UIControl *zone1 = (id)Find(host,@"wolkaraforever.abilityZone.1");
    assert(zone1 && !zone1.hidden);
    [zone1 sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    GCExtendedGamepad *live = manager.created.controller.extendedGamepad;
    BOOL anyDown = live.buttonA.pressed || live.buttonB.pressed || live.buttonX.pressed || live.buttonY.pressed ||
                   live.leftShoulder.pressed || live.rightShoulder.pressed ||
                   live.leftTrigger.pressed || live.rightTrigger.pressed || live.buttonMenu.pressed;
    assert(anyDown);
    [zone1 sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    assert(!live.buttonA.pressed && !live.buttonB.pressed && !live.buttonX.pressed && !live.buttonY.pressed);
    assert(AKFixtureLogHas(@"event=press outcome=sent control=zone1"));
    assert(AKFixtureLogHas(@"event=release outcome=sent control=zone1"));
    // Two surfaces on one element: the value stays down until the last one lets go.
    AKGamepadLayout *saved = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    assert([saved addAbilityZoneForElement:saved.abilityZones[0][@"element"] atX:0.62 y:0.47]);
    [saved save]; [manager reloadLayout]; [host layoutIfNeeded];
    [manager toggleSettings]; [host layoutIfNeeded];
    [manager toggleSettings]; [host layoutIfNeeded];
    zone1 = (id)Find(host,@"wolkaraforever.abilityZone.1");
    UIControl *zone2 = (id)Find(host,@"wolkaraforever.abilityZone.2");
    assert(zone1 && zone2);
    [zone1 sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    [zone2 sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    GCExtendedGamepad *shared = manager.created.controller.extendedGamepad;
    BOOL sharedDown = shared.buttonA.pressed || shared.buttonB.pressed || shared.buttonX.pressed || shared.buttonY.pressed ||
                      shared.leftShoulder.pressed || shared.rightShoulder.pressed ||
                      shared.leftTrigger.pressed || shared.rightTrigger.pressed || shared.buttonMenu.pressed;
    assert(sharedDown);
    [zone1 sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    BOOL stillDown = shared.buttonA.pressed || shared.buttonB.pressed || shared.buttonX.pressed || shared.buttonY.pressed ||
                     shared.leftShoulder.pressed || shared.rightShoulder.pressed ||
                     shared.leftTrigger.pressed || shared.rightTrigger.pressed || shared.buttonMenu.pressed;
    assert(stillDown);          // the second finger is still on it
    [zone2 sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    assert(!shared.buttonA.pressed && !shared.buttonB.pressed && !shared.buttonX.pressed && !shared.buttonY.pressed);
    // Cancelling takes both away, and the pair count is what proves there was one each.
    [zone1 sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    [zone2 sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    manager.keyboardVisible = YES; Drain();
    assert(!shared.buttonA.pressed && !shared.buttonB.pressed && !shared.buttonX.pressed && !shared.buttonY.pressed);
    manager.keyboardVisible = NO; Drain();
    assert(WaitUntil(^{ return manager.visible; }));
    [manager toggleSettings]; [host layoutIfNeeded];
    clearZones = (id)Find(host,@"wolkaraforever.controls.clearAbilityZones");
    [clearZones sendActionsForControlEvents:UIControlEventTouchUpInside];
    [manager toggleSettings]; [host layoutIfNeeded];
    assert(Find(host,@"wolkaraforever.abilityZone.1") == nil);
    AKFixtureAssertPressesHaveReleases();
    AKFixtureEndLog();
    puts("TOUCH_CONTROLLER_TWO_PASS: Simple hides the triggers and the D-pad and turning it off restores them, one tap is not a stick button while a double tap is and lets go by itself, a drag never becomes one, and an ability zone sends exactly one press and one release even when two of them share a button.");
}
// The floating arrangement is the mobile interface's, and only its: the mode is the whole gate.
// In it, each thumb's half of the screen is its stick and the corner beyond the camera stick is
// the jump; the add-on's own chat strip and wheel tabs are not ours, so the touch goes on to
// what is underneath - the app's own hit-testing, not a forwarded touch. Auto-run arms, lights
// up, runs on release and stops on the next touch, and leaving the arrangement lets go of it.
static void TestFloating(UIView *host, AKPreviewGamepad *manager) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *key=AKInterfaceModeDefaultsKey;
    // The mode is chosen the way this fixture chooses it at launch: in the argument domain,
    // which outranks anything the app writes. Nothing else is touched, so "no value" really is
    // no value.
    void (^mode)(NSString *)=^(NSString *value) {
        NSMutableDictionary *modes=[[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary new];
        if (value) modes[key]=value; else [modes removeObjectForKey:key];
        [defaults setVolatileDomain:modes forName:NSArgumentDomain];
    };
    // Standard: no floating switch, and the floating geometry is not in force.
    for (NSString *value in @[@"ipados", @"duo"]) {
        mode(value);
        [manager toggleSettings];
        assert(Find(host,@"wolkaraforever.controls.sticksOnly")==nil);
        assert(Find(host,@"wolkaraforever.controls.floatingSticks")==nil);
        [manager toggleSettings]; [host layoutIfNeeded];
        assert([host hitTest:CGPointMake(CGRectGetWidth(host.bounds)*0.40,CGRectGetHeight(host.bounds)*0.50) withEvent:nil]
               !=Find(host,@"tolkara.gamepad.leftStick"));
    }
    mode(nil);
    [manager toggleSettings];
    assert(Find(host,@"wolkaraforever.controls.floatingSticks")==nil);
    [manager toggleSettings];
    // Mobile: the arrangement exists, and both arrangements are switched on.
    mode(AKInterfaceModeIOS);
    [manager toggleSettings];
    UISwitch *sticksOnly=(id)Find(host,@"wolkaraforever.controls.sticksOnly");
    UISwitch *floating=(id)Find(host,@"wolkaraforever.controls.floatingSticks");
    assert(sticksOnly && floating);
    sticksOnly.on=YES; [sticksOnly sendActionsForControlEvents:UIControlEventValueChanged];
    floating.on=YES; [floating sendActionsForControlEvents:UIControlEventValueChanged];
    [manager toggleSettings]; [host layoutIfNeeded];
    UIView *leftStick=Find(host,@"tolkara.gamepad.leftStick"), *rightStick=Find(host,@"tolkara.gamepad.rightStick");
    UIView *overlay=leftStick.superview.superview;
    assert(leftStick && rightStick && overlay);
    CGRect b=overlay.bounds;
    CGPoint (^at)(CGFloat,CGFloat)=^CGPoint(CGFloat fx,CGFloat fy) {
        return [overlay convertPoint:CGPointMake(CGRectGetMinX(b)+b.size.width*fx,CGRectGetMinY(b)+b.size.height*fy) toView:host];
    };
    UIView *jump=Button(host,GCInputButtonA);
    // Each thumb's half is its stick; outside them the touch is the game's (the host itself,
    // because the overlay declined it).
    assert([host hitTest:at(0.25,0.70) withEvent:nil]==leftStick);
    assert([host hitTest:at(0.70,0.50) withEvent:nil]==rightStick);
    assert([host hitTest:at(0.25,0.30) withEvent:nil]==host);   // above the left half
    assert([host hitTest:at(0.05,0.70) withEvent:nil]==host);   // the left margin of it
    assert([host hitTest:at(0.55,0.60) withEvent:nil]==host);   // between the two halves
    assert([host hitTest:at(0.85,0.10) withEvent:nil]==host);   // above the right half
    CGFloat h=b.size.height;
    CGPoint corner=CGPointMake(CGRectGetMaxX(b),CGRectGetMaxY(b));
    CGPoint nearCorner=[overlay convertPoint:CGPointMake(corner.x-0.05*h,corner.y-0.05*h) toView:host];
    assert([host hitTest:nearCorner withEvent:nil]==jump);
    // Nothing is reserved by default: the far corner beyond the jump is still the camera half.
    CGFloat far=0.25*h;
    CGPoint beyondJump=[overlay convertPoint:CGPointMake(corner.x-far*0.7071,corner.y-far*0.7071) toView:host];
    assert([host hitTest:beyondJump withEvent:nil]==rightStick);
    // The bottom centre belongs to neither thumb, so it is the game's - and an add-on's.
    assert([host hitTest:at(0.5,0.97) withEvent:nil]==host);
    // A reserved area is the player's own data, and it wins over a thumb's half.
    AKGamepadLayout *prefs=(id)[overlay valueForKey:@"preferences"];
    assert(prefs && prefs.keepFree.count==0);
    [prefs addKeepFreeAreaWithX:0.66 y:0.44 width:0.10 height:0.12];
    assert(prefs.keepFree.count==1);
    assert([host hitTest:at(0.70,0.50) withEvent:nil]==host);
    // An area that is not four finite fractions of the screen is refused, not clamped in.
    [prefs clearKeepFreeAreas];
    [prefs addKeepFreeAreaWithX:1.5 y:-2 width:0 height:0];
    assert(prefs.keepFree.count==0);
    assert([host hitTest:at(0.70,0.50) withEvent:nil]==rightStick);
    // A stick held by one finger is not grabbed by another touch in its half.
    AKFixtureTouch *touch=[AKFixtureTouch new];
    touch.point=CGPointMake(CGRectGetMidX(leftStick.bounds),0);
    UIControl *stick=(id)leftStick;
    [stick beginTrackingWithTouch:touch withEvent:nil];
    assert([host hitTest:at(0.25,0.80) withEvent:nil]!=leftStick);
    // Auto-run: a forward hold arms it after two seconds, a drag up confirms, the release runs.
    UIView *lock=Find(host,@"wolkaraforever.controls.autorunLock");
    UIView *badge=Find(host,@"wolkaraforever.controls.autorun");
    assert(lock && badge && lock.hidden && badge.hidden);
    [stick pollAutoRun:100]; assert(lock.hidden);
    [stick pollAutoRun:103]; assert(!lock.hidden);
    touch.point=CGPointMake(CGRectGetMidX(leftStick.bounds),-100);
    [stick continueTrackingWithTouch:touch withEvent:nil];
    assert(!lock.hidden);
    [stick endTrackingWithTouch:touch withEvent:nil];
    assert(!badge.hidden && lock.hidden);
    CGPoint held=[[leftStick valueForKey:@"position"] CGPointValue];
    assert(held.y>0.9 && fabs(held.x)<0.01);
    // The next touch on the stick stops the run, and does not turn into a click on the game.
    touch.point=CGPointMake(CGRectGetMidX(leftStick.bounds),CGRectGetMidY(leftStick.bounds));
    [stick beginTrackingWithTouch:touch withEvent:nil];
    assert(badge.hidden);
    [stick endTrackingWithTouch:touch withEvent:nil];
    CGPoint stopped=[[leftStick valueForKey:@"position"] CGPointValue];
    assert(fabs(stopped.x)<0.01 && fabs(stopped.y)<0.01);
    // Leaving the arrangement lets go of everything, including a run.
    touch.point=CGPointMake(CGRectGetMidX(leftStick.bounds),0);
    [stick beginTrackingWithTouch:touch withEvent:nil];
    [stick pollAutoRun:200]; [stick pollAutoRun:203];
    touch.point=CGPointMake(CGRectGetMidX(leftStick.bounds),-100);
    [stick continueTrackingWithTouch:touch withEvent:nil];
    [stick endTrackingWithTouch:touch withEvent:nil];
    assert(!badge.hidden);
    mode(AKInterfaceModeIPadOS);
    [manager toggleSettings]; [host layoutIfNeeded];
    assert(badge.hidden);
    assert(!((UISwitch *)Find(host,@"wolkaraforever.controls.floatingSticks")));
    [manager toggleSettings];
    mode(AKInterfaceModeIOS);
    // Back to the arrangements the rest of the fixture expects: both off, as a fresh install has
    // them, so the fixed rings are what the remaining checks measure.
    [manager toggleSettings];
    sticksOnly=(id)Find(host,@"wolkaraforever.controls.sticksOnly");
    UISwitch *off=(id)Find(host,@"wolkaraforever.controls.floatingSticks");
    if (off.on) { off.on=NO; [off sendActionsForControlEvents:UIControlEventValueChanged]; }
    sticksOnly.on=NO; [sticksOnly sendActionsForControlEvents:UIControlEventValueChanged];
    [manager toggleSettings]; [host layoutIfNeeded];
    puts("TOUCH_GAMEPAD_FLOATING_PASS: the floating arrangement exists only with the mobile interface (ipados, a malformed value and no value keep Standard), each thumb's half is its stick, the corner is the jump, the bottom centre is left to the game, a reserved area is the player's own and wins over a half, and auto-run arms, confirms, runs, stops and is released by leaving the arrangement.");
}
static void TestStickMapping(void) {
    CGSize size=CGSizeMake(100,100);
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(50,50),size),CGPointZero));
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(52,50),size),CGPointZero));
    CGPoint value=AKTouchGamepadStickPosition(CGPointMake(500,50),size); assert(value.x==1 && value.y==0);
    value=AKTouchGamepadStickPosition(CGPointMake(0,0),size); assert(fabs(hypot(value.x,value.y)-1)<0.0001 && value.y>0 && value.x<0);
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(NAN,1),size),CGPointZero));
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointZero,CGSizeZero),CGPointZero));
    assert(CGPointEqualToPoint(AKTouchGamepadStickPosition(CGPointMake(CGFLOAT_MAX,CGFLOAT_MAX),CGSizeMake(0.001,0.001)),CGPointZero));
}

// Exercise work UIKit queues specifically for tracking, and its deferred UI
// completion phase, from a nested pump rather than UIApplication's outer loop.
static void TestTrackingPump(void) {
    CFRunLoopRef loop=CFRunLoopGetCurrent();
    __block BOOL defaultTimer=NO, trackingTimer=NO;
    // A future fire date makes the closed, zero-duration pump assertion meaningful:
    // it must not wait for work that is not yet ready.
    CFAbsoluteTime fireDate=CFAbsoluteTimeGetCurrent()+.01;
    CFRunLoopTimerRef defaultModeTimer=CFRunLoopTimerCreateWithHandler(NULL,fireDate,0,0,0,
        ^(__unused CFRunLoopTimerRef t) { defaultTimer=YES; });
    CFRunLoopAddTimer(loop,defaultModeTimer,kCFRunLoopDefaultMode);
    CFRunLoopTimerRef trackingModeTimer=CFRunLoopTimerCreateWithHandler(NULL,fireDate,0,0,0,
        ^(__unused CFRunLoopTimerRef t) { trackingTimer=YES; });
    CFRunLoopAddTimer(loop,trackingModeTimer,(__bridge CFStringRef)UITrackingRunLoopMode);
    AKPumpTouchEvents(NO);
    assert(!defaultTimer && !trackingTimer);
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+.25;
    while ((!defaultTimer || !trackingTimer) && CFAbsoluteTimeGetCurrent()<deadline)
        AKPumpTouchEvents(YES);
    assert(defaultTimer && trackingTimer);
    CFRunLoopTimerInvalidate(defaultModeTimer); CFRelease(defaultModeTimer);
    CFRunLoopTimerInvalidate(trackingModeTimer); CFRelease(trackingModeTimer);
    puts("TOUCH_TRACKING_PUMP_PASS: deferred UI and tracking timers progress; closed-panel pump remains nonblocking.");
}

static void TestLifecycle(UIView *host) {
    TestTrackingPump();
    TestStickMapping();
    TestHaptics();
    TestInterfaceMode();
    // The Touch Controller 2 fixtures that need no window: the log's boundary, the layout's
    // second schema, and the direct camera's gesture. They run here, in both interfaces, so a
    // broken migration or a lost release fails the same suite that proves the lifecycle.
    TestTouchControllerLog();
    TestLayoutSchema();
    TestDirectCamera();
    AKFixtureGamepad *pad=[[AKFixtureGamepad alloc] initWithHostView:host];
    // The fixture asserts the controller lifecycle, not the device's foreground phase.
    // A simulator launched by simctl reports the app Inactive, which would gate every
    // connection below on a property this test does not measure; the notification is
    // the activation the product itself reacts to.
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [pad refresh]; assert(WaitUntil(^{ return (BOOL)(pad.connections==1); }) && !pad.visible);
    AKFixtureController *physical=[AKFixtureController new]; physical.extendedGamepad=@YES;
    pad.devices=@[(id)physical]; [pad refresh];
    assert(WaitUntil(^{ return (BOOL)!pad.visible; }));
    AKFixtureConnection *opened=pad.lastConnection; [opened finish:nil];
    assert(WaitUntil(^{ return (BOOL)(!pad.visible && opened.disconnects); }));
    pad.devices=@[]; [pad refresh]; [pad.lastConnection finish:nil];
    assert(WaitUntil(^{ return (BOOL)pad.visible; }));
    // Our own connect event must never be mistaken for physical hardware.
    pad.devices=@[pad.lastConnection.controller];
    [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:pad.lastConnection.controller];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false);
    assert(pad.visible && pad.connections==2);
    pad.devices=@[]; pad.keyboardVisible=YES;
    assert(WaitUntil(^{ return (BOOL)!pad.visible; }) && pad.lastConnection.disconnects);
    pad.keyboardVisible=NO; [pad.lastConnection finish:nil]; assert(WaitUntil(^{ return (BOOL)pad.visible; }));
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    assert(!pad.visible);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    // Keyboard opening while connect is pending cancels a late success.
    pad.keyboardVisible=YES; [pad.lastConnection finish:nil]; assert(!pad.visible);
    NSUInteger count=pad.connections;
    [pad refresh]; assert(pad.connections==count);
    pad.keyboardVisible=NO;
    [pad.lastConnection finish:[NSError errorWithDomain:@"Fixture" code:1 userInfo:nil]];
    assert(!pad.visible); count=pad.connections;
    [pad refresh]; [pad refresh]; assert(pad.connections==count); // no retry loop
    pad.enabled=NO; pad.enabled=YES; [pad.lastConnection finish:nil]; assert(WaitUntil(^{ return (BOOL)pad.visible; }));
    [pad toggleSettings]; assert(pad.configuring);
    pad.devices=@[(id)physical]; [pad refresh]; assert(!pad.visible && !pad.configuring);
    assert(!Find(host,@"wolkaraforever.controls.settings"));
    pad.devices=@[]; [pad refresh]; [pad.lastConnection finish:nil]; assert(WaitUntil(^{ return (BOOL)pad.visible; }));
    // A controller that is already connected closes nothing: keyboard, window and
    // application notifications reach -refresh too, and closing on those hid the panel
    // while it was being used on any device that already had a controller.
    pad.devices=@[(id)physical]; [pad refresh]; assert(!pad.visible);
    [pad toggleSettings]; assert(pad.configuring);
    [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidBecomeHiddenNotification object:nil];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false);
    assert(pad.configuring && Find(host,@"wolkaraforever.controls.settings"));
    [pad toggleSettings]; assert(!pad.configuring);
    pad.devices=@[]; [pad refresh]; [pad.lastConnection finish:nil]; assert(WaitUntil(^{ return (BOOL)pad.visible; }));
    [pad toggleSettings];
    UISwitch *edit=(id)Find(host,@"wolkaraforever.controls.edit");
    edit.on=YES; [edit sendActionsForControlEvents:UIControlEventValueChanged]; assert(pad.configuring);
    pad.devices=@[(id)physical]; [pad refresh]; assert(!pad.visible && !pad.configuring);
    physical.isSnapshot=YES; [pad refresh]; [pad.lastConnection finish:nil]; assert(WaitUntil(^{ return (BOOL)pad.visible; }));
    host.hidden=YES; [pad refresh]; assert(!pad.visible);
    host.hidden=NO; [pad refresh];
    [pad invalidate]; [pad.lastConnection finish:nil]; assert(!pad.visible);
    count=pad.connections; [pad refresh]; assert(pad.connections==count);
    puts("TOUCH_GAMEPAD_LIFECYCLE_PASS: physical connection closes settings and editing; physical priority, own/snapshot filtering, keyboard/focus cancellation, late replies, failure, retry and teardown.");
}

@interface AKGamepadFixtureScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property AKTouchGamepad *gamepad;
@property UILabel *status;
@property UILabel *input;
@property NSUInteger events;
@property NSUInteger presses;
@property NSUInteger axisUpdates;
@property BOOL inputTestScheduled;
@end
@implementation AKGamepadFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    // The mobile interface is chosen before anything reads it, exactly as the launcher
    // chooses it: by the defaults key, here in the argument domain.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--mobile-interface"]) {
        NSMutableDictionary *modes=[[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        modes[@"WolkaraForeverInterfaceModeV1"]=@"ios";
        [NSUserDefaults.standardUserDefaults setVolatileDomain:modes forName:NSArgumentDomain];
    }
    UIViewController *vc=[UIViewController new]; vc.view=[AKFixtureHostView new]; vc.view.backgroundColor=[UIColor colorWithRed:.04 green:.07 blue:.12 alpha:1];
    self.window.rootViewController=vc;
    self.status=[UILabel new]; self.input=[UILabel new];
    for (UILabel *label in @[self.status,self.input]) {
        label.textColor=UIColor.whiteColor; label.numberOfLines=0;
        label.font=[UIFont systemFontOfSize:18]; label.translatesAutoresizingMaskIntoConstraints=NO;
        [vc.view addSubview:label];
    }
    self.status.text=@"Touch controller test · Waiting for activation";
    self.input.text=@"Original input fixture — no game runs here";
    [NSLayoutConstraint activateConstraints:@[
        [self.status.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:68],
        [self.status.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [self.status.widthAnchor constraintLessThanOrEqualToAnchor:vc.view.widthAnchor constant:-100],
        [self.input.topAnchor constraintEqualToAnchor:self.status.bottomAnchor constant:10],
        [self.input.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [self.input.widthAnchor constraintLessThanOrEqualToAnchor:vc.view.widthAnchor constant:-100]
    ]];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(start) withObject:nil afterDelay:.5];
}
- (void)start {
    BOOL test=[NSProcessInfo.processInfo.arguments containsObject:@"--self-test"];
    if (test || [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"]) {
        // A fresh installation, stated rather than assumed: the key is removed *and* the
        // arrangement written back from this build's own defaults, so a layout left on the
        // simulator - Simple, stick buttons, zones - cannot decide what these tests measure.
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverTouchLayoutV1"];
        [[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults] reset];
    }
    if (test) { TestLifecycle(self.window.rootViewController.view); fflush(stdout); exit(0); }
    // A plain launch is for looking at the fixture. Without --stay it closes itself
    // after a minute anyway, so a headless run cannot sit on it for ever. (The
    // --self-test-input path above has its own shorter watchdog.)
    if (![NSProcessInfo.processInfo.arguments containsObject:@"--stay"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                fprintf(stderr, "TOUCH_GAMEPAD_LIFETIME_REACHED (pass --stay to keep it open)\n");
                _Exit(EXIT_SUCCESS);
            });
    }
    // Two demonstration arrangements for a person looking at the fixture. They go through the
    // same layout object the controls read, so what is on screen is what a player would get.
    NSArray<NSString *> *arguments=NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"--demo-simple"]) {
        AKGamepadLayout *demo=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        [demo setModeName:@"simple"];
        [demo addAbilityZoneForElement:GCInputButtonY atX:0.50 y:0.55];
        [demo addAbilityZoneForElement:GCInputButtonB atX:0.80 y:0.30];
        [demo save];
    } else if ([arguments containsObject:@"--demo-full"]) {
        AKGamepadLayout *demo=[[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        [demo setModeName:@"full"];
        [demo clearAbilityZones];
        [demo save];
    }
    self.gamepad=[[AKPreviewGamepad alloc] initWithHostView:self.window.rootViewController.view];
    UIButton *settings=[UIButton buttonWithType:UIButtonTypeSystem];
    [settings setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    settings.accessibilityLabel=@"Touch control settings";
    settings.frame=CGRectMake(self.window.bounds.size.width/2-22,8,44,44);
    settings.layer.zPosition=100001;
    [settings addTarget:self.gamepad action:@selector(toggleSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.window.rootViewController.view addSubview:settings];
    __weak AKGamepadFixtureScene *weakSelf=self;
    self.gamepad.visibilityChanged=^(BOOL visible) {
        weakSelf.status.text=visible?@"Touch controller active":@"Touch controller hidden";
        NSLog(@"VIRTUAL_CONTROLLER_VISIBLE=%d",visible);
        if (visible && [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"]) {
            if (!weakSelf.inputTestScheduled) {
                weakSelf.inputTestScheduled=YES;
                [weakSelf performSelector:@selector(testInput) withObject:nil afterDelay:0.1];
            }
            return;
        }
        GCController *own=((AKPreviewGamepad *)weakSelf.gamepad).created.controller;
        if (visible) for (GCController *controller in own ? @[own] : @[]) {
            controller.extendedGamepad.valueChangedHandler=^(GCExtendedGamepad *pad, GCControllerElement *element) {
                BOOL press=[element isKindOfClass:GCControllerButtonInput.class] && ((GCControllerButtonInput *)element).isPressed;
                BOOL axis=[element isKindOfClass:GCControllerDirectionPad.class];
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.events++; weakSelf.presses+=press; weakSelf.axisUpdates+=axis;
                    weakSelf.input.text=[NSString stringWithFormat:@"Events %lu · Presses %lu · Axes %lu\nA %.1f · B %.1f · X %.1f · Y %.1f · + %.1f\nL (%.2f, %.2f) · R (%.2f, %.2f) · Pad (%.0f, %.0f)",
                        (unsigned long)weakSelf.events,(unsigned long)weakSelf.presses,(unsigned long)weakSelf.axisUpdates,
                        pad.buttonA.value,pad.buttonB.value,pad.buttonX.value,pad.buttonY.value,
                        pad.buttonMenu.value,
                        pad.leftThumbstick.xAxis.value,pad.leftThumbstick.yAxis.value,
                        pad.rightThumbstick.xAxis.value,pad.rightThumbstick.yAxis.value,pad.dpad.xAxis.value,pad.dpad.yAxis.value];
                });
            };
        }
    };
    NSLog(@"FIXTURE_CONTROLLER_COUNT=%lu",(unsigned long)GCController.controllers.count);
    // The input fixture measures the pad's own routing; a simctl-launched app can
    // report Inactive, which would leave the preview pad unconnected for ever. The same goes
    // for the demonstration arrangements, which exist to be looked at.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--activate"])
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [self.gamepad refresh];
    // A panel to photograph, for the same reason: it is the real one.
    if ([arguments containsObject:@"--demo-settings"]) [self performSelector:@selector(openSettings) withObject:nil afterDelay:1.5];
    [self performSelector:@selector(report) withObject:nil afterDelay:2];
    // The guest owns the main thread after a timer callout and polls UIKit
    // re-entrantly. Keep an interactive fixture for that distinct input path.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--guest-pump"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(__unused NSTimer *timer) {
            NSLog(@"FIXTURE_GUEST_PUMP_STARTED");
            BOOL legacy = [NSProcessInfo.processInfo.arguments containsObject:@"--legacy-pump"];
            for (;;) { @autoreleasepool {
                if (legacy) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0,false);
                else AKPumpTouchEvents(self.gamepad.configuring);
                usleep(16000);
            } }
        }];
    }
}
- (void)testInput { TestNativeInput(self.window.rootViewController.view,(id)self.gamepad); fflush(stdout); exit(0); }
- (void)openSettings { [self.gamepad toggleSettings]; }
- (void)report {
    NSLog(@"FIXTURE_GAMEPAD: active=%d key=%d hidden=%d visible=%d controllers=%lu",UIApplication.sharedApplication.applicationState==UIApplicationStateActive,self.window.isKeyWindow,self.window.hidden,self.gamepad.visible,(unsigned long)GCController.controllers.count);
}
@end
@interface AKGamepadFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKGamepadFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"Gamepad fixture" sessionRole:session.role];
    config.delegateClass=AKGamepadFixtureScene.class; return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
                // Say how far it got before the process is taken out: a timeout with no
                // passes listed is a fixture that cannot be diagnosed.
                fflush(stdout); fflush(stderr);
                fputs("TOUCH_GAMEPAD_LIFECYCLE_TIMEOUT\n",stderr); fflush(stderr); _Exit(1);
            });
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(AKGamepadFixtureApp.class));
    }
}
