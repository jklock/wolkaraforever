// Original fixture: tests our lifecycle with fake transports, then permits
// manual testing of Apple's real virtual controller. No game or network.
#import <UIKit/UIKit.h>
#import "../translation/AppKit/InterfaceMode.h"
#import "../translation/AppKit/TouchGamepad.h"
#import "../translation/AppKit/TouchGamepadLayout.h"
#import "../translation/AppKit/TouchCamera.h"
#import "../translation/AppKit/ControllerPointer.h"
#import "../translation/AppKit/TouchControllerLog.h"
#import "../translation/AppKit/TouchHaptics.h"
#import "../translation/AppKit/TouchContract.h"
#import "../translation/AppKit/TouchAreas.h"
#import "../translation/AppKit/AKHostLocalization.h"
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
@property (weak) UIView *fixtureView;
@end
@implementation AKFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
- (NSTimeInterval)timestamp { return _when > 0 ? _when : NSProcessInfo.processInfo.systemUptime; }
- (UIView *)view { return self.fixtureView; }
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
// The walk stick's auto-run hold  on the fixture's clock: the overlay's own timer calls -tick while the
// lock fills; the fixture moves its clock and calls it.
@interface UIView (WalkHoldFixture)
@property(nonatomic, copy) NSTimeInterval (^clock)(void);
@property(nonatomic, readonly) BOOL armed;
@property(nonatomic) CGFloat lockFill;
- (void)tick;
@end
static NSTimeInterval gWalkNow = 5000;
static void WalkClock(UIView *overlay) { overlay.clock = ^NSTimeInterval { return gWalkNow; }; }
static void WalkWait(UIView *overlay, NSTimeInterval seconds) { gWalkNow += seconds; [overlay tick]; }
// The host, with the one delegate method the mobile jump uses: a key pressed or released. It
// answers like the app's host view does, which is what decides Space over the gamepad's A.
// In iPad touch it is also the host's key sink (patch 0077's touchKey:characters:modifiers:pressed:):
// the walk stick's movement keys and TouchPlay's chord keys both arrive here, as "13v -" (W down, no
// modifiers) or "120^ COS" (F2 up with control, option and shift).
@interface AKFixtureHostView : UIView <AKTouchKeySink>
@property BOOL recordsKeys;
@property(readonly) NSMutableArray<NSString *> *keys;
@property(readonly) NSMutableArray<NSString *> *sunk;
@end
@implementation AKFixtureHostView { NSMutableArray<NSString *> *_keys, *_sunk; }
- (NSMutableArray<NSString *> *)keys { if (!_keys) _keys=[NSMutableArray new]; return _keys; }
- (NSMutableArray<NSString *> *)sunk { if (!_sunk) _sunk=[NSMutableArray new]; return _sunk; }
- (void)touchKey:(unsigned short)code characters:(NSString *)characters modifiers:(NSUInteger)modifiers pressed:(BOOL)pressed {
    (void)characters;
    NSString *mods=modifiers==0 ? @"-" : [NSString stringWithFormat:@"%@%@%@",
        (modifiers & (1<<18)) ? @"C" : @"", (modifiers & (1<<19)) ? @"O" : @"", (modifiers & (1<<17)) ? @"S" : @""];
    [self.sunk addObject:[NSString stringWithFormat:@"%u%@ %@",code,pressed?@"v":@"^",mods]];
}
- (void)touchPointerAt:(CGPoint)p click:(BOOL)click { (void)p; (void)click; }
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
    // iPad touch is the TouchPlay mode: mobile, its own name, its own stored spelling, and the
    // only value for which the TouchPlay query answers YES. ios and iosduo are not TouchPlay.
    setMode(AKInterfaceModeIPadTouch);
    assert(AKInterfaceModeIsMobile() && !AKInterfaceModeIsAutomatic() && AKInterfaceModeIsTouchPlay());
    assert([AKInterfaceModeIPadTouch isEqual:@"ipadtouch"]);
    assert([AKInterfaceModeName() isEqual:AKInterfaceModeIPadTouch]);
    assert([AKInterfaceModeStoredName() isEqual:AKInterfaceModeIPadTouch]);
    setMode(@"IPadTouch"); assert(AKInterfaceModeIsMobile() && AKInterfaceModeIsTouchPlay());
    for (NSString *other in @[AKInterfaceModeIOS, AKInterfaceModeIOSDuo, AKInterfaceModeIPadOS, AKInterfaceModeAuto, @"touchplay", @""]) {
        setMode(other); assert(!AKInterfaceModeIsTouchPlay());
    }
    setMode(nil); assert(!AKInterfaceModeIsTouchPlay());
    // "auto" still resolves to the hardware's own answer; on an iPad that is iPadOS, never iPad touch.
    setMode(AKInterfaceModeAuto);
    assert(!AKInterfaceModeIsTouchPlay());
    assert(phone || [AKInterfaceModeName() isEqual:AKInterfaceModeIPadOS]);
    assert(![AKInterfaceModeAutomaticName() isEqual:AKInterfaceModeIPadTouch]);
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
    puts("TOUCH_INTERFACE_MODE_PASS: ios, iosduo, ipadtouch (the only TouchPlay mode) and ipados are explicit, auto is the device's own hardware class (spelled in any case), and a missing or unrecognised value is Standard.");
}
// The crash fallback for iPad touch: only while it is the stored mode, a start that never exits
// cleanly is counted; two in a row put the mode back to iPadOS and clear the count. The fixture
// writes the persistent domain (the launcher's own write) and lifts any argument-domain value
// for the duration, because that domain outranks the persistent one.
static void CrashGuardExitVerifier(void);
static void TestCrashGuard(void) {
    // Registered before the product's own exit handler can be (the first session below installs it),
    // so that, atexit handlers running last-in first-out, it sees the result of that handler.
    static dispatch_once_t verifierOnce;
    dispatch_once(&verifierOnce, ^{ atexit(CrashGuardExitVerifier); });
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSString *key=AKInterfaceModeDefaultsKey;
    NSMutableDictionary *arguments=[[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary new];
    id argumentMode=arguments[key];
    [arguments removeObjectForKey:key]; [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
    id originalMode=[defaults objectForKey:key];
    void (^reset)(NSString *)=^(NSString *mode) {
        if (mode) [defaults setObject:mode forKey:key]; else [defaults removeObjectForKey:key];
        [defaults removeObjectForKey:AKTouchCrashGuardDefaultsKey];
    };
    // crash_fallback_after_two
    reset(AKInterfaceModeIPadTouch);
    assert(!AKTouchCrashGuardShouldFallBack());
    AKTouchCrashGuardWillStart(); assert(!AKTouchCrashGuardShouldFallBack());
    AKTouchCrashGuardWillStart(); assert(AKTouchCrashGuardShouldFallBack());
    assert(AKTouchCrashGuardApplyFallback());
    assert([AKInterfaceModeStoredName() isEqual:AKInterfaceModeIPadOS] && !AKInterfaceModeIsTouchPlay());
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    assert(!AKTouchCrashGuardShouldFallBack() && !AKTouchCrashGuardApplyFallback()); // once only
    // one_unclean_start_keeps_mode
    reset(AKInterfaceModeIPadTouch);
    AKTouchCrashGuardWillStart();
    assert(!AKTouchCrashGuardShouldFallBack() && !AKTouchCrashGuardApplyFallback());
    assert([AKInterfaceModeStoredName() isEqual:AKInterfaceModeIPadTouch]);
    // A clean exit clears the run: unclean, clean, unclean is never two in a row.
    AKTouchCrashGuardDidExitCleanly(); AKTouchCrashGuardWillStart();
    assert(!AKTouchCrashGuardShouldFallBack() && [defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
    AKTouchCrashGuardDidExitCleanly(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    // other_modes_never_count: nothing is read, written or reset under any other value.
    for (NSString *other in @[AKInterfaceModeIPadOS, AKInterfaceModeIOS, AKInterfaceModeIOSDuo, AKInterfaceModeAuto]) {
        reset(other);
        for (int i=0; i<3; i++) AKTouchCrashGuardWillStart();
        assert(![defaults objectForKey:AKTouchCrashGuardDefaultsKey]);
        assert(!AKTouchCrashGuardShouldFallBack() && !AKTouchCrashGuardApplyFallback());
        [defaults setInteger:5 forKey:AKTouchCrashGuardDefaultsKey];
        AKTouchCrashGuardDidExitCleanly();
        assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==5);
        assert([AKInterfaceModeStoredName() isEqual:other]);
    }
    // --- The session: what main.m drives. Begin counts the start and installs the exit handler and
    // the background/foreground watch once; End is any clean way out; Abandon is a start that never
    // got going. Only a real crash may leave the count up.
    NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
    void (^background)(void)=^{ [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil]; };
    void (^foreground)(void)=^{ [center postNotificationName:UIApplicationWillEnterForegroundNotification object:nil]; };
    // normal_quit_via_atexit: the handler registered with atexit() is the clean-exit mark.
    reset(AKInterfaceModeIPadTouch);
    AKTouchCrashGuardBeginSession();
    assert(AKTouchCrashGuardExitHandlerInstalled() && [defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
    AKTouchCrashGuardExitHandler();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    // background_then_killed_not_counted: a game put away is not a game that crashed.
    reset(AKInterfaceModeIPadTouch);
    AKTouchCrashGuardBeginSession(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
    background(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    // ...killed here by iPadOS: the next start finds nothing to hold against it, however often.
    AKTouchCrashGuardBeginSession(); background(); AKTouchCrashGuardBeginSession(); background();
    assert(!AKTouchCrashGuardShouldFallBack() && [defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    // An earlier real crash stays on record through a background trip of the next session.
    [defaults setInteger:1 forKey:AKTouchCrashGuardDefaultsKey];
    AKTouchCrashGuardBeginSession(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==2);
    background(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1 && !AKTouchCrashGuardShouldFallBack());
    // foreground_then_crash_counted: back in front, the session is at risk again.
    foreground(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==2 && AKTouchCrashGuardShouldFallBack());
    foreground(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==2); // not twice
    background(); background(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
    // A fresh run: start, away, back, crash = one unclean start; the next start makes two.
    reset(AKInterfaceModeIPadTouch);
    AKTouchCrashGuardBeginSession(); background(); foreground();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1); // crash: nothing more is written
    AKTouchCrashGuardBeginSession();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==2 && AKTouchCrashGuardShouldFallBack());
    // failed_start_not_counted: a start that never began is taken back, and later foregrounds
    // do not bring it back.
    [defaults setInteger:1 forKey:AKTouchCrashGuardDefaultsKey];
    AKTouchCrashGuardBeginSession(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==2);
    AKTouchCrashGuardAbandonSession();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1 && !AKTouchCrashGuardShouldFallBack());
    foreground(); background(); foreground();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
    // ...and the orderly exit that follows the closing page does not undo it either.
    AKTouchCrashGuardExitHandler(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
    // A clean end clears the run and ends the watch.
    AKTouchCrashGuardBeginSession(); AKTouchCrashGuardEndSession();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    foreground(); assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==0);
    // other modes: the whole session API leaves the counter alone.
    for (NSString *other in @[AKInterfaceModeIPadOS, AKInterfaceModeIOS, AKInterfaceModeIOSDuo, AKInterfaceModeAuto]) {
        reset(other);
        AKTouchCrashGuardBeginSession(); background(); foreground(); AKTouchCrashGuardAbandonSession();
        AKTouchCrashGuardBeginSession(); AKTouchCrashGuardEndSession(); AKTouchCrashGuardExitHandler();
        assert(![defaults objectForKey:AKTouchCrashGuardDefaultsKey]);
    }
    reset(nil);
    for (int i=0; i<3; i++) AKTouchCrashGuardWillStart();
    assert(![defaults objectForKey:AKTouchCrashGuardDefaultsKey] && !AKTouchCrashGuardShouldFallBack());
    // Nonsense in the counter is read as zero, never as a reason to change the mode.
    reset(AKInterfaceModeIPadTouch);
    [defaults setObject:@"many" forKey:AKTouchCrashGuardDefaultsKey]; assert(!AKTouchCrashGuardShouldFallBack());
    [defaults setInteger:-3 forKey:AKTouchCrashGuardDefaultsKey]; assert(!AKTouchCrashGuardShouldFallBack());
    reset(nil);
    if (originalMode) [defaults setObject:originalMode forKey:key]; else [defaults removeObjectForKey:key];
    if (argumentMode) { arguments[key]=argumentMode; [defaults setVolatileDomain:arguments forName:NSArgumentDomain]; }
    puts("TOUCH_CRASH_GUARD_PASS: two unclean iPad touch starts in a row fall back to iPadOS once; one does not; a clean exit clears the run; every other mode leaves the counter alone.");
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
// --- the controller touchpad as the pointer ------------------------------------
// The relay's deliveries, as the in-game layer receives them. Motion is the platform's own
// trackpad; a tap never clicks; the click under the pad is the button, released exactly once.
static void TestControllerPointer(void) {
    AKControllerPointer pointer = {0};
    NSMutableArray<NSString *> *events = [NSMutableArray new];
    void *context = (__bridge void *)events;
    // One finger moves, and a quick tap with no travel is not a click.
    AKControllerPointerUpdate(&pointer,1,0,0,1,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,1,12,-6,1.02,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,0,0,0,1.04,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"move12.0,-6.0"]]));
    [events removeAllObjects];
    AKControllerPointerUpdate(&pointer,1,50,50,2,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,0,0,0,2.05,AKFixtureCameraEmit,context);
    assert(events.count == 0);
    AKControllerPointerUpdate(&pointer,2,50,50,3,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,0,0,0,3.05,AKFixtureCameraEmit,context);
    assert(events.count == 0);
    // Two fingers scroll, in whole lines, as on the glass.
    AKControllerPointerUpdate(&pointer,2,0,0,4,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,2,0,36,4.1,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"scroll0.0,3.0"]]));
    AKControllerPointerUpdate(&pointer,0,0,0,4.2,AKFixtureCameraEmit,context);
    // The click with one finger is the left button, held while the finger slides: a drag.
    [events removeAllObjects];
    AKControllerPointerUpdate(&pointer,1,0,0,5,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,true,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,true,AKFixtureCameraEmit,context);   // a repeated edge
    AKControllerPointerUpdate(&pointer,1,20,0,5.1,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,false,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,false,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,0,0,0,5.15,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down0",@"move20.0,0.0",@"up0"]]));
    // With two fingers down it is the right button, and the release names the button the press
    // did even if a finger lifted in between.
    [events removeAllObjects];
    AKControllerPointerUpdate(&pointer,2,0,0,6,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,true,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,1,0,0,6.1,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,false,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,0,0,0,6.2,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down1",@"up1"]]));
    // A controller that leaves mid-click releases the button once, and leaves nothing behind.
    [events removeAllObjects];
    AKControllerPointerUpdate(&pointer,1,0,0,7,AKFixtureCameraEmit,context);
    AKControllerPointerClick(&pointer,true,AKFixtureCameraEmit,context);
    AKControllerPointerReset(&pointer,AKFixtureCameraEmit,context);
    AKControllerPointerReset(&pointer,AKFixtureCameraEmit,context);
    assert(([events isEqual:@[@"down0",@"up0"]]));
    assert(!pointer.clicked && !pointer.pad.fingers);
    AKControllerPointerUpdate(&pointer,1,0,0,8,AKFixtureCameraEmit,context);
    AKControllerPointerUpdate(&pointer,1,4,2,8.1,AKFixtureCameraEmit,context);
    assert([events.lastObject isEqual:@"move4.0,2.0"]);
    // Teardown forgets without telling anyone.
    AKControllerPointerClick(&pointer,true,AKFixtureCameraEmit,context);
    NSUInteger before = events.count;
    AKControllerPointerReset(&pointer,NULL,NULL);
    assert(events.count == before && !pointer.clicked);
    puts("CONTROLLER_TOUCHPAD_POINTER_PASS: one finger moves, two fingers scroll, a tap never clicks, the click is the left button (right with two fingers) held for a drag and released exactly once, and a reset releases what is held.");
}
// --- the arrangement, the stick buttons and the zones, through the real controls ---
// A control by name, drawn or not: the identifier the gamepad gives its own controls, without
// the helper that insists a control is visible.
static UIView *GamepadControl(UIView *host, NSString *name) {
    return Find(host, [@"tolkara.gamepad." stringByAppendingString:name]);
}
static void CollectSwitches(UIView *view, NSMutableArray<UISwitch *> *out) {
    if ([view isKindOfClass:UISwitch.class]) { [out addObject:(UISwitch *)view]; return; }
    for (UIView *child in view.subviews) CollectSwitches(child,out);
}
// Every switch in the settings sheet is whole and inside the sheet: a long label beside it
// wraps instead of pushing it past the edge, where it could barely be pressed.
static CGRect DrawnExtent(UIView *view, UIView *target) {
    CGRect extent=[view convertRect:view.bounds toView:target];
    for (UIView *child in view.subviews) if (!child.hidden && child.alpha>0) extent=CGRectUnion(extent,DrawnExtent(child,target));
    return extent;
}
static UIScrollView *EnclosingScroll(UIView *view) {
    for (UIView *v=view.superview; v; v=v.superview) if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
    return nil;
}
static void AssertSettingsSwitchesReachable(UIView *panel) {
    NSMutableArray<UISwitch *> *switches=[NSMutableArray new]; CollectSwitches(panel,switches);
    assert(switches.count>=4);
    // What a switch draws, not only its frame, stays inside the clipping scroll view: the
    // switch's track is drawn a little past its bounds, and a clip there squares its end.
    for (UISwitch *toggle in switches) {
        UIScrollView *scroll=EnclosingScroll(toggle); if (!scroll) continue;
        CGRect drawn=DrawnExtent(toggle,scroll), frame=[toggle convertRect:toggle.bounds toView:scroll];
        CGFloat visibleMax=scroll.contentOffset.x+scroll.bounds.size.width;
        if (CGRectGetMaxX(drawn)>visibleMax+0.5) {
            fprintf(stderr,"TOUCH_SETTINGS_SWITCH_OVERHANG: %s frameMaxX=%.1f drawnMaxX=%.1f clipMaxX=%.1f width=%.1f intrinsic=%.1f\n",
                    toggle.accessibilityIdentifier.UTF8String,CGRectGetMaxX(frame),CGRectGetMaxX(drawn),visibleMax,
                    toggle.bounds.size.width,toggle.intrinsicContentSize.width);
            fflush(stderr); assert(0);
        }
    }
    CGFloat natural=[UISwitch new].intrinsicContentSize.width;
    for (UISwitch *toggle in switches) {
        CGRect frame=[toggle convertRect:toggle.bounds toView:panel];
        if (toggle.bounds.size.width<natural-0.5 || CGRectGetMaxX(frame)>panel.bounds.size.width+0.5 || CGRectGetMinX(frame)<-0.5) {
            fprintf(stderr,"TOUCH_SETTINGS_SWITCH_CLIPPED: %s width=%.1f maxX=%.1f panel=%.1f\n",
                    toggle.accessibilityIdentifier.UTF8String,toggle.bounds.size.width,CGRectGetMaxX(frame),panel.bounds.size.width);
            fflush(stderr); assert(0);
        }
    }
}
static void TestTouchControllerTwo(UIView *host, AKPreviewGamepad *manager);
// The last check, through the process's real exit(): a verifier is registered first (in TestCrashGuard,
// so it runs last, atexit handlers being last-in first-out), then a session begins in iPad touch, then exit(0) runs
// the handler the product registered. The verifier reads the stored count and tidies the defaults.
static void CrashGuardExitVerifier(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSInteger count=[defaults integerForKey:AKTouchCrashGuardDefaultsKey];
    [defaults removeObjectForKey:AKTouchCrashGuardDefaultsKey];
    [defaults removeObjectForKey:AKInterfaceModeDefaultsKey];
    if (count!=0) { fprintf(stderr,"TOUCH_CRASH_GUARD_EXIT_FAIL: count %ld after exit(0)\n",(long)count); _Exit(3); }
    puts("TOUCH_CRASH_GUARD_EXIT_PASS: a game that quits through exit(0) is a clean exit; the registered handler cleared the count.");
    fflush(stdout);
}
static void TestCrashGuardRealExit(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *arguments=[[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary new];
    [arguments removeObjectForKey:AKInterfaceModeDefaultsKey]; [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
    [defaults setObject:AKInterfaceModeIPadTouch forKey:AKInterfaceModeDefaultsKey];
    [defaults removeObjectForKey:AKTouchCrashGuardDefaultsKey];
    AKTouchCrashGuardBeginSession();
    assert([defaults integerForKey:AKTouchCrashGuardDefaultsKey]==1);
}
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
    AssertSettingsSwitchesReachable(panel);
    CGRect normalBounds=host.bounds;
    // A phone in landscape, where the two columns are narrowest beside each other.
    host.bounds=CGRectMake(0,0,852,393); [host layoutIfNeeded]; AssertSettingsSwitchesReachable(panel);
    host.bounds=CGRectMake(0,0,390,600); [host layoutIfNeeded];
    assert(CGRectContainsRect(host.bounds,[panel convertRect:panel.bounds toView:host]));
    AssertSettingsSwitchesReachable(panel);
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
    [manager toggleSettings]; [host layoutIfNeeded];
    {
        // The mobile sheet has the two longest rows; none of its switches may hang off the edge.
        UIView *panel=Find(host,@"wolkaraforever.controls.settings");
        AssertSettingsSwitchesReachable(panel);
        CGRect normalBounds=host.bounds;
        host.bounds=CGRectMake(0,0,852,393); [host layoutIfNeeded]; AssertSettingsSwitchesReachable(panel);
        host.bounds=normalBounds; [host layoutIfNeeded];
    }
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
    // A budget, not a claim about speed: the timers are due in 10 ms, and 250 ms was enough
    // on an idle machine and not enough inside validate.sh, where the simulator is busy and
    // this suite follows the touch-controls one. It failed there on a device check with both
    // timers still unmoved, passed when run alone the minute before and after. What the
    // assertion must prove is that the pump runs both modes' work at all; how long the
    // machine needs to get to it is not the product's behaviour.
    CFAbsoluteTime started=CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime deadline=started+2.0;
    while ((!defaultTimer || !trackingTimer) && CFAbsoluteTimeGetCurrent()<deadline)
        AKPumpTouchEvents(YES);
    if (!(defaultTimer && trackingTimer))
        fprintf(stderr, "TOUCH_TRACKING_PUMP_TIMEOUT: default=%d tracking=%d after %.3fs\n",
                (int)defaultTimer, (int)trackingTimer, CFAbsoluteTimeGetCurrent()-started);
    assert(defaultTimer && trackingTimer);
    CFRunLoopTimerInvalidate(defaultModeTimer); CFRelease(defaultModeTimer);
    CFRunLoopTimerInvalidate(trackingModeTimer); CFRelease(trackingModeTimer);
    puts("TOUCH_TRACKING_PUMP_PASS: deferred UI and tracking timers progress; closed-panel pump remains nonblocking.");
}

#pragma mark - The walk stick under the thumb (iPad touch, the input path, only the walk stick, with no virtual controller)

// TouchPlay's saved buttons as the iPad wrote them (26 areas, hand R), copied into the fixture's bundle.
static AKTouchContract *WalkContract(void) {
    NSString *path=[NSBundle.mainBundle pathForResource:@"TouchPlay-v1" ofType:@"lua"];
    AKTouchContract *contract=AKTouchContractParse([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]);
    assert(contract && contract.areas.count==26 && !contract.leftHanded && contract.edgeRun);
    return contract;
}
static void WalkMode(NSString *value) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *modes=[[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary new];
    if (value) modes[AKInterfaceModeDefaultsKey]=value; else [modes removeObjectForKey:AKInterfaceModeDefaultsKey];
    [defaults setVolatileDomain:modes forName:NSArgumentDomain];
}
static void WalkCheck(BOOL ok, const char *test, const char *condition, NSString *what, NSArray *keys) {
    if (ok) return;
    fprintf(stderr,"TOUCH_WALK_STICK_FAIL %s: %s -- %s (keys: %s)\n",test,condition,what.UTF8String,[keys componentsJoinedByString:@", "].UTF8String);
    fflush(stderr); _Exit(4);
}
#define WALK(test, cond, ...) WalkCheck((cond), test, #cond, [NSString stringWithFormat:@"" __VA_ARGS__], keyed.sunk)
// One walk stick in iPad touch over the fixture host, with TouchPlay's areas made over the same view
// (as the host makes them in iPad touch) and the host as the key sink.
typedef struct { AKTouchGamepad *walk; AKTouchAreas *areas; UIView *overlay, *ring; } AKWalkRig;
static AKWalkRig WalkRig(UIView *host, AKTouchContract *contract) {
    AKWalkRig rig;
    rig.areas=[[AKTouchAreas alloc] initWithView:host];
    rig.areas.contract=contract;
    rig.walk=[[AKTouchGamepad alloc] initWalkStickWithHostView:host below:nil];
    [host layoutIfNeeded];
    rig.overlay=Find(host,@"wolkaraforever.touch.walkArea");
    rig.ring=Find(host,@"wolkaraforever.touch.walkStick");
    WalkClock(rig.overlay);
    AKTouchSetKeySink((id<AKTouchKeySink>)host);
    [((AKFixtureHostView *)host).sunk removeAllObjects];
    return rig;
}
static void WalkRigDone(UIView *host, AKWalkRig rig) {
    [rig.walk invalidate];
    rig.areas.contract=nil;
    assert(Find(host,@"wolkaraforever.touch.walkArea")==nil);
    AKTouchSetKeySink(nil);
}
// An event whose touches are the ones given (a finger UIKit lost is simply not among them).
@interface AKWalkFixtureEvent : UIEvent
@property NSSet<UITouch *> *fixtureTouches;
@end
@implementation AKWalkFixtureEvent
- (NSSet<UITouch *> *)allTouches { return self.fixtureTouches; }
- (UIEventType)type { return UIEventTypeTouches; }
@end
// A touch from a trackpad, mouse or Pencil, as UIKit has it when the walk layer is hit-tested.
@interface AKWalkPointerTouch : UITouch
@property UITouchType fixtureType;
@end
@implementation AKWalkPointerTouch
- (UITouchType)type { return self.fixtureType; }
- (UITouchPhase)phase { return UITouchPhaseBegan; }
- (UIView *)view { return nil; }
@end
static AKFixtureTouch *WalkFinger(CGPoint p) { AKFixtureTouch *t=[AKFixtureTouch new]; t.point=p; return t; }
static void WalkBegin(UIView *overlay, AKFixtureTouch *t) { [overlay touchesBegan:[NSSet setWithObject:t] withEvent:nil]; }
static void WalkMove(UIView *overlay, AKFixtureTouch *t, CGPoint p) { t.point=p; [overlay touchesMoved:[NSSet setWithObject:t] withEvent:nil]; }
static void WalkEnd(UIView *overlay, AKFixtureTouch *t) { [overlay touchesEnded:[NSSet setWithObject:t] withEvent:nil]; }
static CGPoint WalkAt(CGPoint p, CGFloat dx, CGFloat dy) { return CGPointMake(p.x+dx,p.y+dy); }
static CGPoint AreaCentre(AKTouchContract *contract, NSString *name, CGSize size) {
    CGRect r=AKTouchAreaRect([contract areaNamed:name],size); return CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r));
}
static BOOL Showing(UIView *view) { return view && !view.hidden && view.alpha>0.5 && view.window; }
// A player device check showed: the auto-run lock is a plate above the ring. Its centre in the host's coordinates
// (the walk layer covers the host), wherever the ring is drawn now.
static UIView *WalkPlate(UIView *host) { return Find(host,@"wolkaraforever.touch.walkStick.lockPlate"); }
static CGPoint WalkLockAt(UIView *host) { UIView *plate=WalkPlate(host); return [plate.superview convertPoint:plate.center toView:host]; }
// Up into the ring, on up past its top onto the lock, held there until the lock is full (0.25 s), and let go: the one
// way to lock an auto-run.
static void WalkLockRun(UIView *overlay, UIView *host, CGPoint p) {
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(overlay,t); WalkMove(overlay,t,WalkAt(p,0,-60)); WalkMove(overlay,t,WalkLockAt(host)); WalkWait(overlay,0.25); WalkEnd(overlay,t);
}
// The walk keys still down after `sunk` ("13v -" down, "13^ -" up): none means the stick holds nothing.
static NSUInteger WalkKeysDown(NSArray<NSString *> *sunk) {
    NSMutableSet *down=[NSMutableSet new];
    for (NSString *k in sunk) {
        NSRange v=[k rangeOfString:@"v"], u=[k rangeOfString:@"^"];
        if (v.location!=NSNotFound) [down addObject:[k substringToIndex:v.location]];
        else if (u.location!=NSNotFound) [down removeObject:[k substringToIndex:u.location]];
    }
    return down.count;
}
// A point `radius` pt from `p` at `degrees` from straight up, clockwise (90 = right).
static CGPoint WalkAngle(CGPoint p, CGFloat radius, CGFloat degrees) {
    CGFloat a=degrees*M_PI/180; return CGPointMake(p.x+radius*sin(a),p.y-radius*cos(a));
}

// The walk area (a player, a device check: a pinch in the middle grabbed the stick): the outer third away from the hand, from
// 460 units down (the lower 55 %, one unit = height / 1024), out of the 20 pt edge zone - never the middle of the screen.
// The contract's areas are carved out per point.
static BOOL WalkClose(CGRect a, CGRect b) {
    return fabs(a.origin.x-b.origin.x)<0.01 && fabs(a.origin.y-b.origin.y)<0.01 && fabs(a.size.width-b.size.width)<0.01 && fabs(a.size.height-b.size.height)<0.01;
}
static void walk_area_follows_size(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    CGRect r=AKTouchWalkArea(CGSizeMake(1366,1024),NO);
    WALK("walk_area_follows_size", WalkClose(r,CGRectMake(20,460,1366/3.0-20,544)), "%@", NSStringFromCGRect(r));
    r=AKTouchWalkArea(CGSizeMake(1366,1024),YES);
    WALK("walk_area_follows_size", WalkClose(r,CGRectMake(1366*2/3.0,460,1366/3.0-20,544)), "left-handed: %@", NSStringFromCGRect(r));
    r=AKTouchWalkArea(CGSizeMake(1024,768),NO);
    WALK("walk_area_follows_size", WalkClose(r,CGRectMake(20,345,1024/3.0-20,403)), "smaller view: %@", NSStringFromCGRect(r));
    for (NSValue *v in @[[NSValue valueWithCGSize:CGSizeMake(1366,1024)],[NSValue valueWithCGSize:CGSizeMake(1210,834)],[NSValue valueWithCGSize:CGSizeMake(1024,768)]])
        for (NSNumber *left in @[@NO,@YES]) {
            CGSize size=v.CGSizeValue;
            WALK("walk_area_follows_size", !CGRectContainsPoint(AKTouchWalkArea(size,left.boolValue),CGPointMake(size.width/2,size.height/2))
                 && !CGRectContainsPoint(AKTouchWalkArea(size,left.boolValue),CGPointMake(size.width*(left.boolValue?0.62:0.38),size.height*0.6)),
                 "%@ %@: the middle of the screen is never the stick's", NSStringFromCGSize(size), left);
        }
    WALK("walk_area_follows_size", CGRectIsEmpty(AKTouchWalkArea(CGSizeZero,NO)), "no size, no area");
    // A view that changes size: the stick follows the new third, and a held stick lets go of its keys.
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGRect frame=host.frame;
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t); WalkMove(rig.overlay,t,WalkAt(p,0,-50));
    WALK("walk_area_follows_size", [keyed.sunk isEqual:@[@"13v -"]], "walking forward");
    host.frame=CGRectMake(frame.origin.x,frame.origin.y,size.width-500,size.height);
    [host layoutIfNeeded];
    WALK("walk_area_follows_size", [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && !rig.walk.leftStickVisible &&
         CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "a resize lets go");
    WalkEnd(rig.overlay,t);
    WALK("walk_area_follows_size", keyed.sunk.count==2, "the old finger's lift adds nothing");
    CGFloat third=(size.width-500)/3;
    WALK("walk_area_follows_size", [host hitTest:CGPointMake(third+30,size.height*0.62) withEvent:nil]==host, "past the new third");
    WALK("walk_area_follows_size", [host hitTest:CGPointMake(third-30,size.height*0.62) withEvent:nil]==rig.overlay, "inside the new third");
    host.frame=frame; [host layoutIfNeeded];
    WalkRigDone(host,rig);
}

static void rule3_stick_appears_under_thumb(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGSize size=host.bounds.size;
    WALK("rule3_stick_appears_under_thumb", rig.overlay && rig.ring, "the walk stick is made in iPad touch");
    UIView *rest=Find(host,@"wolkaraforever.touch.walkStick.rest");
    WALK("rule3_stick_appears_under_thumb", !rig.walk.leftStickVisible && !Showing(rig.ring), "no live stick at rest");
    WALK("rule3_stick_appears_under_thumb", rest && !rest.hidden && rest.alpha>0.1 && rest.window, "the rest ring is drawn at its usual place ");
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    WALK("rule3_stick_appears_under_thumb", [host hitTest:p withEvent:nil]==rig.overlay, "a thumb in the walk area is the stick's");
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t);
    WALK("rule3_stick_appears_under_thumb", rig.walk.leftStickVisible && Showing(rig.ring) && rest.hidden, "the ring shows, the rest ring goes");
    WALK("rule3_stick_appears_under_thumb", hypot(rig.ring.center.x-p.x,rig.ring.center.y-p.y)<0.5 &&
         fabs(rig.ring.bounds.size.width-175)<0.5, "centred under the thumb, 175 pt (25%% larger): %@ %@",
         NSStringFromCGPoint(rig.ring.center),NSStringFromCGRect(rig.ring.bounds));
    UIView *knob=Find(rig.ring,@"wolkaraforever.touch.walkStick.knob");
    WALK("rule3_stick_appears_under_thumb", knob && fabs(knob.bounds.size.width-70)<0.5, "knob 70 pt");
    WALK("rule3_stick_appears_under_thumb", keyed.sunk.count==0 && CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "no key at rest");
    // Up 50 pt: forward (W), no modifiers. Up and right: W and D (8 directions). Right: D alone.
    WalkMove(rig.overlay,t,WalkAt(p,0,-50));
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:@[@"13v -"]] && rig.walk.leftStickVector.y>0.5 &&
         fabs(rig.walk.leftStickVector.x)<0.01, "W down");
    WALK("rule3_stick_appears_under_thumb", fabs(knob.center.y-(87.5-rig.walk.leftStickVector.y*87.5))<0.5, "the knob follows: %@", NSStringFromCGPoint(knob.center));
    WalkMove(rig.overlay,t,WalkAt(p,35,-35));
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:(@[@"13v -",@"2v -"])], "up-right adds D");
    WalkMove(rig.overlay,t,WalkAt(p,50,0));
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:(@[@"13v -",@"2v -",@"13^ -"])], "right alone lets go of W");
    WalkMove(rig.overlay,t,WalkAt(p,-35,35));
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:(@[@"13v -",@"2v -",@"13^ -",@"2^ -",@"0v -",@"1v -"])], "down-left: A and S");
    WalkMove(rig.overlay,t,WalkAt(p,4,3));
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:(@[@"13v -",@"2v -",@"13^ -",@"2^ -",@"0v -",@"1v -",@"0^ -",@"1^ -"])], "the dead zone sends nothing");
    // A full push shows the edge glow; the lift (edgeRun off below) releases and hides.
    WalkMove(rig.overlay,t,WalkAt(p,0,40));
    WALK("rule3_stick_appears_under_thumb", rig.ring.layer.shadowOpacity<0.01, "no glow short of the edge");
    WalkMove(rig.overlay,t,WalkAt(p,0,90));
    WALK("rule3_stick_appears_under_thumb", rig.ring.layer.shadowOpacity>0.5 && rig.walk.leftStickVector.y<-0.99, "full speed glows");
    [keyed.sunk removeAllObjects];
    WalkMove(rig.overlay,t,WalkAt(p,0,20));
    WalkEnd(rig.overlay,t);
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:@[@"1^ -"]] && !rig.walk.leftStickVisible && !rig.walk.autoRunning &&
         CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "a lift short of the edge stops and hides");
    WALK("rule3_stick_appears_under_thumb", !rest.hidden, "the rest ring is back");
    // A second thumb in the walk area while the stick is held is swallowed: never a world touch, and it
    // does not move the stick.
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *first=WalkFinger(p), *second=WalkFinger(CGPointMake(size.width*0.15,size.height*0.8));
    WalkBegin(rig.overlay,first); WalkMove(rig.overlay,first,WalkAt(p,0,-50));
    WALK("rule3_stick_appears_under_thumb", [host hitTest:second.point withEvent:nil]==rig.overlay, "the second thumb is not the world's");
    WalkBegin(rig.overlay,second); WalkMove(rig.overlay,second,WalkAt(second.point,60,0)); WalkEnd(rig.overlay,second);
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:@[@"13v -"]] && hypot(rig.ring.center.x-p.x,rig.ring.center.y-p.y)<0.5, "the stick is unchanged");
    [rig.overlay touchesCancelled:[NSSet setWithObject:first] withEvent:nil];
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && !rig.walk.leftStickVisible, "a cancel lets go");
    // A stick finger UIKit never ended (it is not among the event's touches when the next thumb lands)
    // must not keep walking: it is let go, and the new thumb is the stick.
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *lost=WalkFinger(p), *next=WalkFinger(second.point);
    WalkBegin(rig.overlay,lost); WalkMove(rig.overlay,lost,WalkAt(p,0,-50));
    AKWalkFixtureEvent *event=[AKWalkFixtureEvent new];
    event.fixtureTouches=[NSSet setWithObject:next];
    [rig.overlay touchesBegan:[NSSet setWithObject:next] withEvent:event];
    WALK("rule3_stick_appears_under_thumb", [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] &&
         hypot(rig.ring.center.x-next.point.x,rig.ring.center.y-next.point.y)<0.5, "a lost finger is let go");
    WalkEnd(rig.overlay,next);
    WalkRigDone(host,rig);
}

static void rule3_outside_area_no_stick(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    CGFloat u=size.height/1024;
    // The top cards band, a contract area (the quest list, the chat strip), the edge zone, the other half.
    // The quest list spans 200...460 units, so its centre is on the band's line: a point in its lower part.
    // The chat strip runs across the middle: a point in its left end.
    CGRect chatRect=AKTouchAreaRect([contract areaNamed:@"chat"],size);
    CGPoint quest=CGPointMake(AreaCentre(contract,@"quest",size).x,420*u), chat=CGPointMake(CGRectGetMinX(chatRect)+20,CGRectGetMidY(chatRect));
    WALK("rule3_outside_area_no_stick", [rig.areas claimsPoint:quest] && [rig.areas claimsPoint:chat], "both are buttons");
    WALK("rule3_outside_area_no_stick", quest.x<size.width/2 && quest.y>330*u && chat.x<size.width/2, "the quest list and chat sit in the left half: %@ %@ %@", NSStringFromCGPoint(quest), NSStringFromCGPoint(chat), NSStringFromCGSize(size));
    NSDictionary<NSString *,NSValue *> *outside=@{
        @"top band":[NSValue valueWithCGPoint:CGPointMake(size.width*0.25,330*u-4)],
        @"quest list":[NSValue valueWithCGPoint:quest],
        @"chat strip":[NSValue valueWithCGPoint:chat],
        @"left edge":[NSValue valueWithCGPoint:CGPointMake(12,size.height*0.62)],
        @"bottom edge":[NSValue valueWithCGPoint:CGPointMake(size.width*0.12,size.height-8)],
        @"right half":[NSValue valueWithCGPoint:CGPointMake(size.width*0.6,size.height*0.5)],
    };
    for (NSString *name in outside) {
        CGPoint p=outside[name].CGPointValue;
        WALK("rule3_outside_area_no_stick", [host hitTest:p withEvent:nil]==host, "%@ (%@) is not the stick's", name, NSStringFromCGPoint(p));
    }
    // The zone starts 460 units down (the lower 55 %) in the outer third: just under that line is the stick's, just above
    // it and just past the third are not (a device check: a pinch in the middle grabbed the stick).
    CGPoint under=CGPointMake(size.width*0.25,460*u+4);
    WALK("rule3_outside_area_no_stick", ![rig.areas claimsPoint:under] && [host hitTest:under withEvent:nil]==rig.overlay, "just under the zone's top is");
    WALK("rule3_outside_area_no_stick", [host hitTest:CGPointMake(size.width*0.25,460*u-4) withEvent:nil]==host, "just above it is not");
    WALK("rule3_outside_area_no_stick", [host hitTest:CGPointMake(size.width/3+4,size.height*0.62) withEvent:nil]==host, "just past the third is not");
    WALK("rule3_outside_area_no_stick", [host hitTest:CGPointMake(size.width/2,size.height/2) withEvent:nil]==host, "the middle is not");
    // A trackpad or mouse click, or the Pencil, in the walk area is the game's (a click), not the stick's.
    CGPoint inside=CGPointMake(size.width*0.25,size.height*0.62);
    for (NSNumber *type in @[@(UITouchTypeIndirectPointer),@(UITouchTypePencil),@(UITouchTypeIndirect)]) {
        AKWalkPointerTouch *pointer=[AKWalkPointerTouch new]; pointer.fixtureType=type.integerValue;
        AKWalkFixtureEvent *event=[AKWalkFixtureEvent new]; event.fixtureTouches=[NSSet setWithObject:pointer];
        WALK("rule3_outside_area_no_stick", [host hitTest:inside withEvent:event]==host, "touch type %@ is not the stick's", type);
    }
    AKFixtureTouch *finger=WalkFinger(inside);
    AKWalkFixtureEvent *fingerEvent=[AKWalkFixtureEvent new]; fingerEvent.fixtureTouches=[NSSet setWithObject:finger];
    WALK("rule3_outside_area_no_stick", finger.type==UITouchTypeDirect && [host hitTest:inside withEvent:fingerEvent]==rig.overlay, "a finger is");
    // No contract in iPad touch: no stick at all (plain taps).
    rig.areas.contract=nil;
    WALK("rule3_outside_area_no_stick", [host hitTest:CGPointMake(size.width*0.25,size.height*0.62) withEvent:nil]==host, "no contract, no stick");
    rig.areas.contract=contract;
    // The keyboard is up (typing): the stick steps aside.
    rig.walk.keyboardVisible=YES;
    WALK("rule3_outside_area_no_stick", [host hitTest:CGPointMake(size.width*0.25,size.height*0.62) withEvent:nil]==host, "keyboard up, no stick");
    rig.walk.keyboardVisible=NO;
    WALK("rule3_outside_area_no_stick", keyed.sunk.count==0, "nothing sent");
    WalkRigDone(host,rig);
}

// let go after locking on purpose (up onto the lock, 0.25 s), it keeps running - W down, the ring stays
// with the knob at its top, the lock full above it, "Auto-run" - until a new thumb, a tap on the lock, or any way out.
static void rule3_lock_keeps_running(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    UIView *lock=Find(host,@"wolkaraforever.touch.walkStick.lock"), *full=Find(host,@"wolkaraforever.touch.walkStick.lockFill");
    UIView *badge=Find(host,@"wolkaraforever.touch.autorun"), *plate=WalkPlate(host);
    WALK("rule3_lock_keeps_running", lock && full && badge && plate && !Showing(plate) && !Showing(badge), "no lock at rest");
    void (^runForward)(void)=^{ WalkLockRun(rig.overlay,host,p); };
    runForward();
    WALK("rule3_lock_keeps_running", rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]], "locked and let go: keeps running, W only");
    WALK("rule3_lock_keeps_running", rig.walk.leftStickVector.y>0.99 && fabs(rig.walk.leftStickVector.x)<0.01 && rig.walk.leftStickVisible, "straight forward, the ring stays");
    WALK("rule3_lock_keeps_running", Showing(plate) && Showing(lock) && Showing(full) && Showing(badge) && rig.ring.layer.shadowOpacity>0.5, "the full lock above the ring, the glow, Auto-run");
    WALK("rule3_lock_keeps_running", [((UILabel *)badge).text isEqual:AKHostLocalized(@"touch.autorun")], "the badge says %@", ((UILabel *)badge).text);
    WALK("rule3_lock_keeps_running", CGRectGetMaxY([badge.superview convertRect:badge.frame toView:host])<=CGRectGetMinY([plate.superview convertRect:plate.frame toView:host])+0.5,
         "the badge sits above the lock");
    // A new touch in the walk area stops it, and is a new stick under that thumb (its lock an empty target again).
    CGPoint q=CGPointMake(size.width*0.18,size.height*0.75);
    WALK("rule3_lock_keeps_running", [host hitTest:q withEvent:nil]==rig.overlay, "the next thumb is the stick's");
    AKFixtureTouch *stop=WalkFinger(q);
    WalkBegin(rig.overlay,stop);
    WALK("rule3_lock_keeps_running", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])], "stopped");
    WALK("rule3_lock_keeps_running", !Showing(full) && !Showing(badge) && hypot(rig.ring.center.x-q.x,rig.ring.center.y-q.y)<0.5, "the new stick, the lock empty");
    WalkEnd(rig.overlay,stop);
    WALK("rule3_lock_keeps_running", keyed.sunk.count==2 && !rig.walk.leftStickVisible && !Showing(plate), "its lift adds nothing");
    // Every way out of a run lets go of the keys: a resize, a reload with new buttons, leaving the app,
    // the keyboard coming up.
    NSArray<NSString *> *ways=@[@"resize",@"reload",@"resign",@"background",@"release",@"keyboard"];
    for (NSString *way in ways) {
        [keyed.sunk removeAllObjects];
        runForward();
        WALK("rule3_lock_keeps_running", rig.walk.autoRunning, "running before %@", way);
        if ([way isEqual:@"resize"]) {
            CGRect frame=host.frame;
            host.frame=CGRectInset(frame,0,40); [host layoutIfNeeded];
            host.frame=frame; [host layoutIfNeeded];
        } else if ([way isEqual:@"reload"]) {
            [NSNotificationCenter.defaultCenter postNotificationName:AKTouchContractDidChangeNotification object:contract];
        } else if ([way isEqual:@"resign"]) {
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        } else if ([way isEqual:@"background"]) {
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
        } else if ([way isEqual:@"release"]) {
            [rig.walk releaseWalking];      // the app's one release-everything entry point (the input path)
        } else {
            rig.walk.keyboardVisible=YES; rig.walk.keyboardVisible=NO;
        }
        Drain();
        WALK("rule3_lock_keeps_running", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] &&
             !rig.walk.leftStickVisible && !Showing(lock), "%@ stops the run", way);
    }
    // With the add-on's auto-run switched off (edgeRun NO), there is no lock: the same slide just walks, and stops.
    [keyed.sunk removeAllObjects];
    contract.edgeRun=NO;
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t);
    WALK("rule3_lock_keeps_running", !Showing(plate), "edgeRun off: no lock");
    CGPoint lc=WalkLockAt(host);
    WalkMove(rig.overlay,t,lc); WalkWait(rig.overlay,1); WalkEnd(rig.overlay,t);
    WALK("rule3_lock_keeps_running", !rig.walk.autoRunning && !rig.overlay.armed && WalkKeysDown(keyed.sunk)==0 && !rig.walk.leftStickVisible, "edgeRun off: letting go stops");
    WalkRigDone(host,rig);
}

//  pushing to the edge is how everyone runs, so holding there never locks - in any direction, however long.
static void a34_edge_hold_never_locks(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    UIView *lock=Find(host,@"wolkaraforever.touch.walkStick.lock"), *full=Find(host,@"wolkaraforever.touch.walkStick.lockFill"), *plate=WalkPlate(host);
    for (NSValue *push in @[[NSValue valueWithCGPoint:CGPointMake(0,-100)],[NSValue valueWithCGPoint:CGPointMake(100,0)],
                            [NSValue valueWithCGPoint:CGPointMake(0,100)],[NSValue valueWithCGPoint:CGPointMake(-100,0)],
                            [NSValue valueWithCGPoint:CGPointMake(75,-75)],[NSValue valueWithCGPoint:CGPointMake(0,-87)],
                            // A thumb that overshoots the ring's edge by 30 pt while running is still not on the lock.
                            [NSValue valueWithCGPoint:CGPointMake(0,-117.5)],[NSValue valueWithCGPoint:CGPointMake(30,-115)]]) {
        CGPoint d=push.CGPointValue;
        [keyed.sunk removeAllObjects];
        AKFixtureTouch *t=WalkFinger(p);
        WalkBegin(rig.overlay,t);
        WALK("a34_edge_hold_never_locks", Showing(plate) && Showing(lock) && !Showing(full) && fabs(rig.ring.lockFill)<0.01, "held: the lock above the ring is an empty target");
        WalkMove(rig.overlay,t,WalkAt(p,d.x,d.y));
        WALK("a34_edge_hold_never_locks", hypot(rig.walk.leftStickVector.x,rig.walk.leftStickVector.y)>0.95, "at the edge %@", NSStringFromCGPoint(d));
        WalkWait(rig.overlay,0.6); WalkWait(rig.overlay,3);
        WALK("a34_edge_hold_never_locks", !rig.overlay.armed && fabs(rig.ring.lockFill)<0.01 && !Showing(full), "3.6 s at the edge %@: never armed (%.2f)", NSStringFromCGPoint(d), rig.ring.lockFill);
        WALK("a34_edge_hold_never_locks", [rig.overlay valueForKey:@"armTimer"]==nil, "no timer off the lock");
        WalkEnd(rig.overlay,t);
        WALK("a34_edge_hold_never_locks", !rig.walk.autoRunning && !rig.walk.leftStickVisible && WalkKeysDown(keyed.sunk)==0 && keyed.sunk.count>=2,
             "let go at the edge %@: stopped", NSStringFromCGPoint(d));
    }
    WalkRigDone(host,rig);
}

//  up past the top of the ring onto the lock, held there 0.25 s while it fills, then let go: running.
static void a34_slide_up_and_hold_locks(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    UIView *full=Find(host,@"wolkaraforever.touch.walkStick.lockFill"), *badge=Find(host,@"wolkaraforever.touch.autorun"), *plate=WalkPlate(host);
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t); WalkMove(rig.overlay,t,WalkAt(p,0,-60));
    WALK("a34_slide_up_and_hold_locks", [keyed.sunk isEqual:@[@"13v -"]] && !rig.overlay.armed, "walking up in the ring");
    CGPoint lc=WalkLockAt(host);
    WALK("a34_slide_up_and_hold_locks", lc.y<CGRectGetMinY(rig.ring.frame) && fabs(lc.x-rig.ring.center.x)<0.5 && plate.bounds.size.width>=44,
         "the lock sits above the ring: %@ ring %@", NSStringFromCGPoint(lc), NSStringFromCGRect(rig.ring.frame));
    // Just inside the ring's top, and 30 pt past it: not yet on the lock.
    WalkMove(rig.overlay,t,CGPointMake(p.x,CGRectGetMinY(rig.ring.frame)+4));
    WalkWait(rig.overlay,1);
    WALK("a34_slide_up_and_hold_locks", !rig.overlay.armed && fabs(rig.ring.lockFill)<0.01, "the ring's top is not the lock");
    WalkMove(rig.overlay,t,CGPointMake(p.x,CGRectGetMinY(rig.ring.frame)-30));
    WalkWait(rig.overlay,1);
    WALK("a34_slide_up_and_hold_locks", !rig.overlay.armed && fabs(rig.ring.lockFill)<0.01, "30 pt past the ring's top is not the lock either");
    WalkMove(rig.overlay,t,lc);
    WALK("a34_slide_up_and_hold_locks", fabs(rig.ring.lockFill)<0.01 && !rig.overlay.armed, "on the lock: empty (%.2f)", rig.ring.lockFill);
    WALK("a34_slide_up_and_hold_locks", [keyed.sunk isEqual:@[@"13v -"]] && fabs(rig.walk.leftStickVector.x)<0.01 && rig.walk.leftStickVector.y>0.99,
         "on the lock: straight forward, W only");
    WalkWait(rig.overlay,0.125);
    WALK("a34_slide_up_and_hold_locks", fabs(rig.ring.lockFill-0.5)<0.01 && Showing(full) && !rig.overlay.armed, "0.125 s: half full (%.2f)", rig.ring.lockFill);
    WALK("a34_slide_up_and_hold_locks", [[rig.overlay valueForKey:@"armTimer"] isValid], "the overlay's own timer fills it meanwhile");
    WalkWait(rig.overlay,0.124);
    WALK("a34_slide_up_and_hold_locks", !rig.overlay.armed, "0.249 s: not yet");
    WalkWait(rig.overlay,0.001);
    WALK("a34_slide_up_and_hold_locks", rig.overlay.armed && fabs(rig.ring.lockFill-1)<0.01 && Showing(full), "0.25 s: armed, the lock full");
    WALK("a34_slide_up_and_hold_locks", [rig.overlay valueForKey:@"armTimer"]==nil, "the timer stops once full");
    WalkWait(rig.overlay,2);
    WALK("a34_slide_up_and_hold_locks", rig.overlay.armed && !rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]], "held on: armed, still walking by the thumb");
    // Moving about on the lock keeps it (a generous target: beside the icon and a little above it).
    WalkMove(rig.overlay,t,CGPointMake(lc.x+40,lc.y-30));
    WALK("a34_slide_up_and_hold_locks", rig.overlay.armed, "still on the lock");
    WalkEnd(rig.overlay,t);
    WALK("a34_slide_up_and_hold_locks", rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]] && Showing(full) && Showing(badge), "let go on the full lock: running");
    [rig.walk releaseWalking];
    // Let go on the lock before it is full: it just stops.
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *u=WalkFinger(p);
    WalkBegin(rig.overlay,u); WalkMove(rig.overlay,u,WalkAt(p,0,-60)); WalkMove(rig.overlay,u,WalkLockAt(host)); WalkWait(rig.overlay,0.2);
    WalkEnd(rig.overlay,u);
    WALK("a34_slide_up_and_hold_locks", !rig.walk.autoRunning && WalkKeysDown(keyed.sunk)==0 && !rig.walk.leftStickVisible && !Showing(plate) &&
         [rig.overlay valueForKey:@"armTimer"]==nil, "let go at 0.2 s: stopped");
    // Straight onto the lock from the landing point (one quick slide) locks the same way.
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *v=WalkFinger(p);
    WalkBegin(rig.overlay,v); WalkMove(rig.overlay,v,WalkLockAt(host)); WalkWait(rig.overlay,0.3); WalkEnd(rig.overlay,v);
    WALK("a34_slide_up_and_hold_locks", rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]], "one slide up and a hold: running");
    WalkRigDone(host,rig);
}

//  sliding back off the lock before lifting cancels; back on, it fills from empty.
static void a34_slide_back_cancels(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    UIView *full=Find(host,@"wolkaraforever.touch.walkStick.lockFill"), *plate=WalkPlate(host);
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t); WalkMove(rig.overlay,t,WalkAt(p,0,-60));
    CGPoint lc=WalkLockAt(host);
    WalkMove(rig.overlay,t,lc); WalkWait(rig.overlay,0.3);
    WALK("a34_slide_back_cancels", rig.overlay.armed, "armed");
    WalkMove(rig.overlay,t,WalkAt(p,0,-60));
    WALK("a34_slide_back_cancels", !rig.overlay.armed && fabs(rig.ring.lockFill)<0.01 && Showing(plate) && !Showing(full), "back down into the ring: disarmed, the lock empty");
    WalkEnd(rig.overlay,t);
    WALK("a34_slide_back_cancels", !rig.walk.autoRunning && WalkKeysDown(keyed.sunk)==0 && !rig.walk.leftStickVisible, "then let go: stopped");
    // Off to the side, then back: it starts again from empty.
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *u=WalkFinger(p);
    WalkBegin(rig.overlay,u); WalkMove(rig.overlay,u,WalkAt(p,0,-60)); WalkMove(rig.overlay,u,WalkLockAt(host)); WalkWait(rig.overlay,0.3);
    lc=WalkLockAt(host);
    WalkMove(rig.overlay,u,CGPointMake(lc.x+90,lc.y));
    WALK("a34_slide_back_cancels", !rig.overlay.armed, "off to the side: disarmed");
    WalkWait(rig.overlay,1);
    WalkMove(rig.overlay,u,lc);
    WALK("a34_slide_back_cancels", fabs(rig.ring.lockFill)<0.01 && !rig.overlay.armed, "back on: empty again (%.2f)", rig.ring.lockFill);
    WalkWait(rig.overlay,0.1);
    WALK("a34_slide_back_cancels", fabs(rig.ring.lockFill-0.4)<0.01, "0.1 s: 0.4 (%.2f)", rig.ring.lockFill);
    WalkMove(rig.overlay,u,CGPointMake(lc.x+90,lc.y));
    WalkEnd(rig.overlay,u);
    WALK("a34_slide_back_cancels", !rig.walk.autoRunning && WalkKeysDown(keyed.sunk)==0, "let go off the lock: stopped");
    WalkRigDone(host,rig);
}

//  stopping is easy - any new touch in the stick's zone, or a tap on the lock (wherever the lock is drawn,
// even over the top band); the tap is no new stick.
static void a34_new_touch_and_lock_tap_stop(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    CGFloat u=size.height/1024;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    WalkLockRun(rig.overlay,host,p);
    WALK("a34_new_touch_and_lock_tap_stop", rig.walk.autoRunning, "running");
    CGPoint lc=WalkLockAt(host);
    WALK("a34_new_touch_and_lock_tap_stop", [host hitTest:lc withEvent:nil]==rig.overlay, "the lock takes a tap");
    AKFixtureTouch *tap=WalkFinger(lc);
    WalkBegin(rig.overlay,tap);
    WALK("a34_new_touch_and_lock_tap_stop", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && !rig.walk.leftStickVisible,
         "a tap on the lock stops the run, and is no new stick");
    WalkMove(rig.overlay,tap,WalkAt(lc,0,-40)); WalkEnd(rig.overlay,tap);
    WALK("a34_new_touch_and_lock_tap_stop", keyed.sunk.count==2 && !rig.walk.leftStickVisible, "its slide and lift add nothing");
    // A run locked near the top of the zone (460 units) draws its lock above the zone, over the game: that tap is the lock's
    // only while running.
    CGPoint high=CGPointMake(size.width*0.25,460*u+40);
    WALK("a34_new_touch_and_lock_tap_stop", [host hitTest:high withEvent:nil]==rig.overlay, "near the top of the zone");
    [keyed.sunk removeAllObjects];
    WalkLockRun(rig.overlay,host,high);
    lc=WalkLockAt(host);
    WALK("a34_new_touch_and_lock_tap_stop", rig.walk.autoRunning && lc.y<460*u, "running, the lock above the zone at %@", NSStringFromCGPoint(lc));
    WALK("a34_new_touch_and_lock_tap_stop", [host hitTest:lc withEvent:nil]==rig.overlay, "the lock over the band takes the tap while running");
    AKFixtureTouch *tap2=WalkFinger(lc);
    WalkBegin(rig.overlay,tap2); WalkEnd(rig.overlay,tap2);
    WALK("a34_new_touch_and_lock_tap_stop", !rig.walk.autoRunning && WalkKeysDown(keyed.sunk)==0, "stopped by its lock");
    WALK("a34_new_touch_and_lock_tap_stop", [host hitTest:lc withEvent:nil]==host, "not running: the band is the game's again");
    // Any new touch in the zone stops it too (and is the new stick).
    [keyed.sunk removeAllObjects];
    WalkLockRun(rig.overlay,host,p);
    AKFixtureTouch *thumb=WalkFinger(CGPointMake(size.width*0.12,size.height*0.85));
    WalkBegin(rig.overlay,thumb);
    WALK("a34_new_touch_and_lock_tap_stop", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && rig.walk.leftStickVisible, "a new thumb stops it");
    WalkEnd(rig.overlay,thumb);
    WalkRigDone(host,rig);
}

//  replacing "the stick stops with a window open": a window open in the world (three pulses: not live,
// windowOpen) keeps the walk stick live - its zone walks, locks and stops an auto-run - but the zone is only the stick box
// (the rest ring's square and the lock target above it); the rest of the screen stays plain touches. Only
// leaving the world (two pulses) or the background lets go.
static void a34_window_open_keeps_the_stick(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    CGFloat u=size.height/1024;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    UIView *lock=Find(host,@"wolkaraforever.touch.walkStick.lock"), *badge=Find(host,@"wolkaraforever.touch.autorun");
    UIView *rest=Find(host,@"wolkaraforever.touch.walkStick.rest");
    WalkLockRun(rig.overlay,host,p);
    WALK("a34_window_open_keeps_the_stick", rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]], "running");
    [rig.areas setLive:NO windowOpen:YES];
    WALK("a34_window_open_keeps_the_stick", rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]] && Showing(lock) && Showing(badge),
         "a window open: still running, W still down, the lock and the badge shown");
    // with a window open the stick's zone shrinks to the stick box - the rest ring's square and the lock target
    // above it. The game's character pane, spellbook, quest log and talents open on the left half: everywhere else there,
    // and on the buttons, the other half, the top band and the edge, every touch is plain.
    NSMutableArray<NSValue *> *rects=[NSMutableArray new];
    for (AKTouchArea *area in contract.areas) [rects addObject:[NSValue valueWithCGRect:AKTouchAreaRect(area,size)]];
    CGRect box=AKTouchWalkRestRing(size,NO,rects);
    CGPoint boxCentre=CGPointMake(CGRectGetMidX(box),CGRectGetMidY(box));
    CGPoint boxLock=CGPointMake(boxCentre.x,CGRectGetMinY(box)-28-24);
    WALK("window_zone_is_the_stick_box", !CGRectIsNull(box) && !CGRectContainsPoint(box,p), "the box %@ (p %@ is outside it)", NSStringFromCGRect(box), NSStringFromCGPoint(p));
    for (NSValue *v in @[[NSValue valueWithCGPoint:boxCentre],[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(box)+6,CGRectGetMaxY(box)-6)],
                         [NSValue valueWithCGPoint:boxLock]])
        WALK("window_zone_is_the_stick_box", [host hitTest:v.CGPointValue withEvent:nil]==rig.overlay, "a window open: %@ in the stick box is the stick's", NSStringFromCGPoint(v.CGPointValue));
    CGRect chatRect=AKTouchAreaRect([contract areaNamed:@"chat"],size);
    CGPoint quest=CGPointMake(AreaCentre(contract,@"quest",size).x,420*u), chat=CGPointMake(CGRectGetMinX(chatRect)+20,CGRectGetMidY(chatRect));
    for (NSValue *v in @[[NSValue valueWithCGPoint:p],[NSValue valueWithCGPoint:CGPointMake(size.width*0.45,size.height*0.6)],
                         [NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(box)+12,CGRectGetMidY(box))],
                         [NSValue valueWithCGPoint:CGPointMake(boxCentre.x,CGRectGetMinY(box)-28-48-56-10)],
                         [NSValue valueWithCGPoint:quest],[NSValue valueWithCGPoint:chat],[NSValue valueWithCGPoint:CGPointMake(size.width*0.6,size.height*0.5)],
                         [NSValue valueWithCGPoint:CGPointMake(size.width*0.25,330*u-4)],[NSValue valueWithCGPoint:CGPointMake(12,size.height*0.62)]]) {
        CGPoint q=v.CGPointValue;
        WALK("window_zone_is_the_stick_box", [host hitTest:q withEvent:nil]==host, "a window open: %@ (outside the box) is a plain touch", NSStringFromCGPoint(q));
    }
    WALK("window_zone_is_the_stick_box", rig.walk.autoRunning, "a plain touch outside the box does not stop the run");
    // A tap on the lock (the running ring's, wherever it was locked) stops it.
    CGPoint lc=WalkLockAt(host);
    AKFixtureTouch *tap=WalkFinger(lc);
    WALK("a34_window_open_keeps_the_stick", [host hitTest:lc withEvent:nil]==rig.overlay, "the lock takes the tap");
    WalkBegin(rig.overlay,tap); WalkEnd(rig.overlay,tap);
    WALK("a34_window_open_keeps_the_stick", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])], "a window open: the lock stops the run");
    WALK("a34_window_open_keeps_the_stick", !rest.hidden && CGRectEqualToRect(rest.frame,box), "a window open: the rest ring is drawn, and is the box");
    // It locks from the box with a window open too, and a new thumb in the box stops it and walks.
    [keyed.sunk removeAllObjects];
    WalkLockRun(rig.overlay,host,boxCentre);
    WALK("a34_window_open_keeps_the_stick", rig.walk.autoRunning && [keyed.sunk isEqual:@[@"13v -"]], "a window open: locked from the box");
    WALK("window_zone_is_the_stick_box", [host hitTest:p withEvent:nil]==host, "running: outside the box is still plain");
    CGPoint q=CGPointMake(boxCentre.x+30,boxCentre.y+30);
    WALK("window_zone_is_the_stick_box", [host hitTest:q withEvent:nil]==rig.overlay, "running: inside the box is the stick's");
    AKFixtureTouch *thumb=WalkFinger(q);
    WalkBegin(rig.overlay,thumb);
    WALK("a34_window_open_keeps_the_stick", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])], "a window open: a new thumb in the box stops it");
    WalkMove(rig.overlay,thumb,WalkAt(q,0,-50));
    WALK("a34_window_open_keeps_the_stick", [keyed.sunk isEqual:(@[@"13v -",@"13^ -",@"13v -"])], "and walks");
    // Back in the world with the thumb down: it keeps walking.
    rig.areas.live=YES;
    WALK("a34_window_open_keeps_the_stick", [keyed.sunk isEqual:(@[@"13v -",@"13^ -",@"13v -"])] && rig.walk.leftStickVisible, "the window closed: still walking");
    // A window opening under a walking thumb: it keeps walking; its lift lets go.
    [rig.areas setLive:NO windowOpen:YES];
    WALK("a34_window_open_keeps_the_stick", [keyed.sunk isEqual:(@[@"13v -",@"13^ -",@"13v -"])] && rig.walk.leftStickVisible, "a window opened under a walking thumb: still walking");
    WalkEnd(rig.overlay,thumb);
    WALK("a34_window_open_keeps_the_stick", WalkKeysDown(keyed.sunk)==0 && !rig.walk.leftStickVisible, "its lift lets go");
    // Two pulses (out of the world) let go of everything, from the window state or a walk; and there is no stick then.
    [keyed.sunk removeAllObjects];
    WalkLockRun(rig.overlay,host,p);
    [rig.areas setLive:NO windowOpen:NO];
    WALK("a34_window_open_keeps_the_stick", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && !Showing(lock) && !Showing(badge),
         "left the world from the window state: stopped");
    WALK("a34_window_open_keeps_the_stick", [host hitTest:p withEvent:nil]==host && rest.hidden, "out of the world: no stick, no rest ring");
    rig.areas.live=YES;
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *walking=WalkFinger(p);
    WalkBegin(rig.overlay,walking); WalkMove(rig.overlay,walking,WalkAt(p,0,-50));
    [rig.areas setLive:NO windowOpen:YES];
    [rig.areas setLive:NO windowOpen:NO];
    WALK("a34_window_open_keeps_the_stick", [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && !rig.walk.leftStickVisible, "a walking thumb lets go when the player leaves the world");
    WalkEnd(rig.overlay,walking);
    WALK("a34_window_open_keeps_the_stick", keyed.sunk.count==2, "its lift adds nothing");
    // The background with a window open: let go.
    [rig.areas setLive:NO windowOpen:YES];
    [keyed.sunk removeAllObjects];
    WalkLockRun(rig.overlay,host,boxCentre);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    Drain();
    WALK("a34_window_open_keeps_the_stick", !rig.walk.autoRunning && [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])], "a window open, then the background: stopped");
    rig.areas.live=YES;
    WalkRigDone(host,rig);
}

//  a floating stick - where the thumb lands in the zone is the centre (no key at the landing), and at rest a
// faint ring is drawn at its usual place: the add-on's stick box (the lower part of the hand-away third).
static void a34_floating_centre_and_rest_ring(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    UIView *rest=Find(host,@"wolkaraforever.touch.walkStick.rest");
    CGRect zone=AKTouchWalkArea(size,NO);
    WALK("a34_floating_centre_and_rest_ring", rest && !rest.hidden && rest.alpha>0.1 && rest.alpha<0.8 && rest.userInteractionEnabled==NO, "a faint rest ring");
    WALK("a34_floating_centre_and_rest_ring", CGRectContainsRect(zone,rest.frame) && rest.frame.size.width<=175.5 && rest.frame.size.width>=140,
         "the rest ring in the zone: %@ (zone %@)", NSStringFromCGRect(rest.frame), NSStringFromCGRect(zone));
    WALK("a34_floating_centre_and_rest_ring", CGRectGetMidX(rest.frame)<size.width/3 && CGRectGetMidY(rest.frame)>470*size.height/1024,
         "in the add-on's stick box: %@", NSStringFromCGRect(rest.frame));
    for (AKTouchArea *area in contract.areas)
        WALK("a34_floating_centre_and_rest_ring", !CGRectIntersectsRect(AKTouchAreaRect(area,size),rest.frame), "the rest ring is off %@", area.name);
    for (NSValue *v in @[[NSValue valueWithCGPoint:CGPointMake(size.width*0.1,size.height*0.5)],[NSValue valueWithCGPoint:CGPointMake(size.width*0.3,size.height*0.85)],
                         [NSValue valueWithCGPoint:CGPointMake(size.width*0.28,size.height*0.55)]]) {
        CGPoint q=v.CGPointValue;
        [keyed.sunk removeAllObjects];
        WALK("a34_floating_centre_and_rest_ring", ![rig.areas claimsPoint:q] && [host hitTest:q withEvent:nil]==rig.overlay, "%@ is the stick's", NSStringFromCGPoint(q));
        AKFixtureTouch *t=WalkFinger(q);
        WalkBegin(rig.overlay,t);
        WALK("a34_floating_centre_and_rest_ring", hypot(rig.ring.center.x-q.x,rig.ring.center.y-q.y)<0.5 && rest.hidden && keyed.sunk.count==0 &&
             CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "the ring centred where the thumb landed at %@, no key", NSStringFromCGPoint(q));
        WalkMove(rig.overlay,t,WalkAt(q,0,-30));
        WALK("a34_floating_centre_and_rest_ring", [keyed.sunk isEqual:@[@"13v -"]], "measured from the landing: W");
        WalkEnd(rig.overlay,t);
        WALK("a34_floating_centre_and_rest_ring", !rest.hidden && WalkKeysDown(keyed.sunk)==0, "lifted: the rest ring again");
    }
    // Running: the running ring is drawn, not the rest one. The keyboard and leaving the world hide it.
    WalkLockRun(rig.overlay,host,CGPointMake(size.width*0.25,size.height*0.62));
    WALK("a34_floating_centre_and_rest_ring", rig.walk.autoRunning && rest.hidden, "running: no rest ring");
    [rig.walk releaseWalking];
    WALK("a34_floating_centre_and_rest_ring", !rest.hidden, "stopped: the rest ring");
    rig.walk.keyboardVisible=YES;
    WALK("a34_floating_centre_and_rest_ring", rest.hidden, "the keyboard up: no rest ring");
    rig.walk.keyboardVisible=NO;
    WALK("a34_floating_centre_and_rest_ring", !rest.hidden, "the keyboard down: back");
    rig.areas.live=NO;
    WALK("a34_floating_centre_and_rest_ring", rest.hidden, "out of the world: no rest ring");
    rig.areas.live=YES;
    WALK("a34_floating_centre_and_rest_ring", !rest.hidden, "in the world: back");
    WalkRigDone(host,rig);
}

//  the rest ring clears the contract's areas at every layout the add-on can send - the iPad sizes, either
// hand, the pet classes' rows (pet row and Leave under the chat strip, Feed pet above slot 5) and larger buttons - and
// stays in the walk area; where 175 pt does not fit, it is made smaller (clamped), never laid over a button.
static AKTouchArea *WalkArea(NSString *name, NSString *anchor, NSInteger dx, NSInteger dy, NSInteger w, NSInteger h) {
    AKTouchArea *a=[AKTouchArea new]; a.name=name; a.anchor=anchor; a.dx=dx; a.dy=dy; a.w=w; a.h=h; a.tapKey=a.holdKey=a.pressKey=@""; return a;
}
static void a34_rest_ring_clears_areas(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *v1=WalkContract();
    // The pet classes' areas (add-on ClassBars.lua / Units.lua, 16 Nov), as the contract writes them: the pet row of 10 at
    // x 275 (centre 580), y 820..872, Leave over it, Feed pet above slot 5, the pet card under the player card.
    NSMutableArray *pets=[v1.areas mutableCopy];
    for (NSInteger i=0; i<10; i++) [pets addObject:WalkArea([NSString stringWithFormat:@"pet%ld",(long)i+1],@"BL",275+i*62,152,52,52)];
    [pets addObject:WalkArea(@"leave",@"BL",495,152,170,52)];
    [pets addObject:WalkArea(@"petfeed",@"BL",523,214,52,52)];
    [pets addObject:WalkArea(@"petcard",@"TL",73,108,200,60)];
    // Larger buttons: every area 1.3 times, from its corner.
    NSMutableArray *large=[NSMutableArray new];
    for (AKTouchArea *a in pets) [large addObject:WalkArea(a.name,a.anchor,a.dx,a.dy,(NSInteger)lround(a.w*1.3),(NSInteger)lround(a.h*1.3))];
    NSDictionary<NSString *,NSArray *> *layouts=@{@"v1":v1.areas,@"pets":pets,@"large":large};
    NSArray<NSValue *> *sizes=@[[NSValue valueWithCGSize:CGSizeMake(1376,1032)],[NSValue valueWithCGSize:CGSizeMake(1366,1024)],
                                [NSValue valueWithCGSize:CGSizeMake(1210,834)],[NSValue valueWithCGSize:CGSizeMake(1180,820)],
                                [NSValue valueWithCGSize:CGSizeMake(1194,834)],[NSValue valueWithCGSize:CGSizeMake(1133,744)],
                                [NSValue valueWithCGSize:CGSizeMake(1024,768)],[NSValue valueWithCGSize:CGSizeMake(1080,810)]];
    for (NSString *name in layouts) for (NSValue *sv in sizes) for (NSNumber *hand in @[@NO,@YES]) {
        CGSize size=sv.CGSizeValue;
        BOOL left=hand.boolValue;
        NSMutableArray<NSValue *> *rects=[NSMutableArray new];
        for (AKTouchArea *a in layouts[name]) {
            AKTouchArea *m=a;
            // Left-handed, the add-on mirrors the thumb side: the corners swap left and right.
            if (left) m=WalkArea(a.name,[a.anchor stringByReplacingOccurrencesOfString:@"L" withString:@"x"],a.dx,a.dy,a.w,a.h);
            if (left) m.anchor=[[m.anchor stringByReplacingOccurrencesOfString:@"R" withString:@"L"] stringByReplacingOccurrencesOfString:@"x" withString:@"R"];
            [rects addObject:[NSValue valueWithCGRect:AKTouchAreaRect(m,size)]];
        }
        CGRect ring=AKTouchWalkRestRing(size,left,rects);
        NSString *what=[NSString stringWithFormat:@"%@ %@ %@",name,NSStringFromCGSize(size),left?@"L":@"R"];
        WALK("a34_rest_ring_clears_areas", !CGRectIsNull(ring) && ring.size.width>=120 && ring.size.width<=175.5 && fabs(ring.size.width-ring.size.height)<0.01,
             "%@: a ring %@", what, NSStringFromCGRect(ring));
        WALK("a34_rest_ring_clears_areas", CGRectContainsRect(AKTouchWalkArea(size,left),ring), "%@: in the walk area %@", what, NSStringFromCGRect(ring));
        CGPoint c=CGPointMake(CGRectGetMidX(ring),CGRectGetMidY(ring));
        for (NSValue *rv in rects) {
            CGRect r=rv.CGRectValue;
            CGFloat dx=MAX(MAX(CGRectGetMinX(r)-c.x,0),c.x-CGRectGetMaxX(r)), dy=MAX(MAX(CGRectGetMinY(r)-c.y,0),c.y-CGRectGetMaxY(r));
            WALK("a34_rest_ring_clears_areas", hypot(dx,dy)>=ring.size.width/2+8-0.01, "%@: the ring %@ clears %@ by 8 pt", what, NSStringFromCGRect(ring), NSStringFromCGRect(r));
        }
    }
    // Nothing to stand on: no ring.
    WALK("a34_rest_ring_clears_areas", CGRectIsNull(AKTouchWalkRestRing(CGSizeZero,NO,@[])), "no size, no ring");
    CGSize size=CGSizeMake(1366,1024);
    WALK("a34_rest_ring_clears_areas", CGRectIsNull(AKTouchWalkRestRing(size,NO,@[[NSValue valueWithCGRect:CGRectMake(0,300,700,724)]])), "a button over the whole zone: no ring");
    WALK("a34_rest_ring_clears_areas", CGRectGetWidth(AKTouchWalkRestRing(size,NO,@[]))==175, "nothing in the way: 175 pt");
    (void)keyed;
}

//  a dead zone of 12% of the radius (10.5 pt of the 87.5): nothing inside it, a key just past it.
static void a34_dead_zone(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t);
    WalkMove(rig.overlay,t,WalkAt(p,0,-9));
    WALK("a34_dead_zone", keyed.sunk.count==0 && CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "9 pt: nothing");
    WalkMove(rig.overlay,t,WalkAt(p,-7,7));
    WALK("a34_dead_zone", keyed.sunk.count==0, "10 pt down-left: nothing");
    WalkMove(rig.overlay,t,WalkAt(p,0,-14));
    WALK("a34_dead_zone", [keyed.sunk isEqual:@[@"13v -"]] && rig.walk.leftStickVector.y>0 && rig.walk.leftStickVector.y<0.1, "14 pt: W, slowly (%.3f)", rig.walk.leftStickVector.y);
    WalkMove(rig.overlay,t,WalkAt(p,0,-10));
    WALK("a34_dead_zone", [keyed.sunk isEqual:(@[@"13v -",@"13^ -"])] && CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "back to 10 pt: W up");
    WalkMove(rig.overlay,t,WalkAt(p,0,-87.5));
    WALK("a34_dead_zone", rig.walk.leftStickVector.y>0.999, "87.5 pt: full");
    WalkEnd(rig.overlay,t);
    WalkRigDone(host,rig);
}

//  direction hysteresis of 8 degrees: a key comes on 8 degrees inside its 67.5-degree sector (59.5) and goes
// off 8 degrees outside it (75.5), so W, W+D, D... never flicker at a sector border. The keys stay plain W/A/S/D.
static void a34_direction_hysteresis(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t);
    WalkMove(rig.overlay,t,WalkAngle(p,60,0));
    WALK("a34_direction_hysteresis", [keyed.sunk isEqual:@[@"13v -"]], "straight up: W");
    WalkMove(rig.overlay,t,WalkAngle(p,60,25));
    WalkMove(rig.overlay,t,WalkAngle(p,60,29));
    WALK("a34_direction_hysteresis", [keyed.sunk isEqual:@[@"13v -"]], "29 degrees (past the 22.5 border): still W alone");
    WalkMove(rig.overlay,t,WalkAngle(p,60,32));
    WALK("a34_direction_hysteresis", [keyed.sunk isEqual:(@[@"13v -",@"2v -"])], "32 degrees: W and D");
    // Wobbling across the border changes nothing.
    for (int i=0; i<5; i++) { WalkMove(rig.overlay,t,WalkAngle(p,60,20)); WalkMove(rig.overlay,t,WalkAngle(p,60,26)); WalkMove(rig.overlay,t,WalkAngle(p,60,16)); }
    WALK("a34_direction_hysteresis", [keyed.sunk isEqual:(@[@"13v -",@"2v -"])], "wobbling between 16 and 26 degrees: no flicker");
    WalkMove(rig.overlay,t,WalkAngle(p,60,13));
    WALK("a34_direction_hysteresis", [keyed.sunk isEqual:(@[@"13v -",@"2v -",@"2^ -"])], "13 degrees: D up");
    WalkMove(rig.overlay,t,WalkAngle(p,60,-29));
    WALK("a34_direction_hysteresis", keyed.sunk.count==3, "-29 degrees: W alone");
    WalkMove(rig.overlay,t,WalkAngle(p,60,-32));
    WALK("a34_direction_hysteresis", [keyed.sunk.lastObject isEqual:@"0v -"], "-32 degrees: A");
    // Round to the right: D on at 59.5 degrees from it, W off 75.5 degrees from W.
    [keyed.sunk removeAllObjects];
    WalkMove(rig.overlay,t,WalkAngle(p,60,45));
    WALK("a34_direction_hysteresis", [keyed.sunk isEqual:(@[@"0^ -",@"2v -"])], "45 degrees: W and D (%@)", keyed.sunk);
    WalkMove(rig.overlay,t,WalkAngle(p,60,74));
    WALK("a34_direction_hysteresis", keyed.sunk.count==2, "74 degrees: W still held");
    WalkMove(rig.overlay,t,WalkAngle(p,60,77));
    WALK("a34_direction_hysteresis", [keyed.sunk.lastObject isEqual:@"13^ -"], "77 degrees: W up, D alone");
    WalkEnd(rig.overlay,t);
    WALK("a34_direction_hysteresis", WalkKeysDown(keyed.sunk)==0, "the lift lets go");
    WalkRigDone(host,rig);
}

// The whole 175 pt ring stays on screen: a thumb near an edge gets the ring clamped in, no key at the
// touch, and full push still in every direction (toward the near edge too).
static void rule3_ring_stays_on_screen(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    CGRect screen=host.bounds;
    // Bottom-left of the walk area: 22 pt from the left edge and from the bottom.
    CGPoint p=CGPointMake(22,size.height-22);
    WALK("rule3_ring_stays_on_screen", [host hitTest:p withEvent:nil]==rig.overlay && ![rig.areas claimsPoint:p], "the corner of the walk area is the stick's");
    AKFixtureTouch *t=WalkFinger(p);
    WalkBegin(rig.overlay,t);
    WALK("rule3_ring_stays_on_screen", CGRectContainsRect(screen,rig.ring.frame), "the ring is on screen: %@", NSStringFromCGRect(rig.ring.frame));
    WALK("rule3_ring_stays_on_screen", fabs(rig.ring.center.x-87.5)<0.5 && fabs(rig.ring.center.y-(size.height-87.5))<0.5, "clamped: %@", NSStringFromCGPoint(rig.ring.center));
    WALK("rule3_ring_stays_on_screen", keyed.sunk.count==0 && CGPointEqualToPoint(rig.walk.leftStickVector,CGPointZero), "no key at the touch");
    // Toward the near edges: to the screen's edge is a full push.
    WalkMove(rig.overlay,t,CGPointMake(0,size.height-22));
    WALK("rule3_ring_stays_on_screen", rig.walk.leftStickVector.x<-0.95 && [keyed.sunk isEqual:@[@"0v -"]] && rig.ring.layer.shadowOpacity>0.5, "full left: %@", NSStringFromCGPoint(rig.walk.leftStickVector));
    WalkMove(rig.overlay,t,CGPointMake(22,size.height));
    WALK("rule3_ring_stays_on_screen", rig.walk.leftStickVector.y<-0.95 && [keyed.sunk isEqual:(@[@"0v -",@"0^ -",@"1v -"])], "full back");
    // Away from them: 87.5 pt is a full push, as anywhere.
    WalkMove(rig.overlay,t,CGPointMake(110,size.height-22));
    WALK("rule3_ring_stays_on_screen", rig.walk.leftStickVector.x>0.95, "full right: %@", NSStringFromCGPoint(rig.walk.leftStickVector));
    WalkMove(rig.overlay,t,CGPointMake(22,size.height-110));
    WALK("rule3_ring_stays_on_screen", rig.walk.leftStickVector.y>0.95, "full forward");
    // The lock is above the ring as drawn (moved in), and locks there.
    CGPoint lc=WalkLockAt(host);
    WALK("rule3_ring_stays_on_screen", fabs(lc.x-87.5)<0.5 && lc.y<CGRectGetMinY(rig.ring.frame), "the lock above the clamped ring: %@", NSStringFromCGPoint(lc));
    WalkMove(rig.overlay,t,lc);
    WalkWait(rig.overlay,0.25);
    WalkEnd(rig.overlay,t);
    WALK("rule3_ring_stays_on_screen", rig.walk.autoRunning && CGRectContainsRect(screen,rig.ring.frame), "locked: running, ring on screen");
    [rig.walk invalidate];
    WALK("rule3_ring_stays_on_screen", [keyed.sunk.lastObject isEqual:@"13^ -"], "invalidate lets go");
    // Left-handed: the right edge clamps the same way.
    rig.areas.contract=nil;
    AKTouchContract *left=WalkContract(); left.leftHanded=YES;
    rig=WalkRig(host,left);
    CGPoint q=CGPointMake(size.width-22,size.height*0.5);
    WALK("rule3_ring_stays_on_screen", ![rig.areas claimsPoint:q] && [host hitTest:q withEvent:nil]==rig.overlay, "the right edge of the walk area");
    AKFixtureTouch *u=WalkFinger(q);
    WalkBegin(rig.overlay,u);
    WALK("rule3_ring_stays_on_screen", fabs(rig.ring.center.x-(size.width-87.5))<0.5 && CGRectContainsRect(screen,rig.ring.frame) && keyed.sunk.count==0, "clamped from the right");
    WalkMove(rig.overlay,u,CGPointMake(size.width,q.y));
    WALK("rule3_ring_stays_on_screen", rig.walk.leftStickVector.x>0.95 && [keyed.sunk isEqual:@[@"2v -"]], "full right to the edge");
    WalkEnd(rig.overlay,u);
    WalkRigDone(host,rig);
}
static void rule3_left_handed_right_half(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchContract *contract=WalkContract();
    contract.leftHanded=YES;
    AKWalkRig rig=WalkRig(host,contract);
    CGSize size=host.bounds.size;
    CGPoint left=CGPointMake(size.width*0.25,size.height*0.62), right=CGPointMake(size.width*0.8,size.height*0.62);
    WALK("rule3_left_handed_right_half", ![rig.areas claimsPoint:right], "no area at the right-half point");
    WALK("rule3_left_handed_right_half", [host hitTest:left withEvent:nil]==host, "hand L: the left half is not the stick's");
    WALK("rule3_left_handed_right_half", [host hitTest:right withEvent:nil]==rig.overlay, "hand L: the right half is");
    // ...but the contract's buttons there still are the buttons'.
    CGPoint spell1=AreaCentre(contract,@"spell1",size);
    WALK("rule3_left_handed_right_half", spell1.x>size.width/2 && CGRectContainsPoint(AKTouchWalkArea(size,YES),spell1), "spell1 is inside the right walk half");
    WALK("rule3_left_handed_right_half", [host hitTest:spell1 withEvent:nil]==host, "spell1 stays a button");
    WALK("rule3_left_handed_right_half", [host hitTest:CGPointMake(size.width-10,size.height*0.5) withEvent:nil]==host, "the right edge zone");
    AKFixtureTouch *t=WalkFinger(right);
    WalkBegin(rig.overlay,t); WalkMove(rig.overlay,t,WalkAt(right,-50,0)); WalkEnd(rig.overlay,t);
    WALK("rule3_left_handed_right_half", [keyed.sunk isEqual:(@[@"0v -",@"0^ -"])], "the left-handed stick walks the same way");
    WalkRigDone(host,rig);
}

// Review Focus 1: the stick's thumb and a spell's finger are independent. First with the add-on's current
// keys (none on W, A, S or D), then with the older file's (spell1 held on D).
static void stick_and_spell_together(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    NSString *current=[NSBundle.mainBundle pathForResource:@"TouchPlay-v1-a22" ofType:@"lua"];
    AKTouchContract *contract=AKTouchContractParse([NSString stringWithContentsOfFile:current encoding:NSUTF8StringEncoding error:NULL]);
    assert(contract.areas.count==26);
    AKWalkRig rig=WalkRig(host,contract);
    __block NSTimeInterval now=10;
    rig.areas.clock=^NSTimeInterval { return now; };
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    AKFixtureTouch *stick=WalkFinger(p);
    WalkBegin(rig.overlay,stick); WalkMove(rig.overlay,stick,WalkAt(p,0,-50));
    CGPoint vector=rig.walk.leftStickVector;
    CGPoint spellPoint=AreaCentre(contract,@"spell1",size);
    WALK("stick_and_spell_together", [host hitTest:spellPoint withEvent:nil]==host, "spell1 is not the stick's");
    UITouch *spell=[UITouch new];
    WALK("stick_and_spell_together", [rig.areas touchBegan:spell at:spellPoint], "spell1 takes the second finger");
    now+=0.1; [rig.areas tick];
    WALK("stick_and_spell_together", [keyed.sunk isEqual:@[@"13v -"]] && CGPointEqualToPoint(rig.walk.leftStickVector,vector), "the stick is unchanged");
    [rig.areas touchEnded:spell at:spellPoint];
    WALK("stick_and_spell_together", [keyed.sunk isEqual:(@[@"13v -",@"120v COS",@"120^ COS"])], "spell1's tap key on the lift, W still down");
    WALK("stick_and_spell_together", CGPointEqualToPoint(rig.walk.leftStickVector,vector) && rig.walk.leftStickVisible, "still walking");
    WalkEnd(rig.overlay,stick);
    WALK("stick_and_spell_together", [keyed.sunk.lastObject isEqual:@"13^ -"] && keyed.sunk.count==4, "W up at the stick's lift");
    rig.areas.contract=WalkContract();   // the older add-on's file
    // the iPad's v1 file holds spell1 on CTRL-ALT-SHIFT-D, the code of the stick's D. Walking
    // right (D held), a held spell1 sends no chord on D - it has no hold key now, so it taps F2 at the lift
    // - and D stays down until the stick lets go (nothing sends it again: no chord ever shares its code).
    [keyed.sunk removeAllObjects];
    AKFixtureTouch *right=WalkFinger(p);
    WalkBegin(rig.overlay,right); WalkMove(rig.overlay,right,WalkAt(p,50,0));
    UITouch *held=[UITouch new];
    [rig.areas touchBegan:held at:spellPoint];
    now+=1.0; [rig.areas tick];
    [rig.areas touchEnded:held at:spellPoint];
    WALK("stick_and_spell_together", [keyed.sunk isEqual:(@[@"2v -",@"120v COS",@"120^ COS"])], "no chord on D, D still down");
    WalkEnd(rig.overlay,right);
    WALK("stick_and_spell_together", [keyed.sunk.lastObject isEqual:@"2^ -"] && keyed.sunk.count==4, "D up at the lift");
    WalkRigDone(host,rig);
}

// iPad touch: only the walk stick. No A/B/X/Y, shoulders, right stick or menu; no 1.0.8 jump (Jump is the
// add-on's `jump` area); no virtual controller is ever made.
static void no_1_0_8_jump_drawn(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKTouchAreas *areas=[[AKTouchAreas alloc] initWithView:host];
    areas.contract=WalkContract();
    AKFixtureGamepad *walk=[[AKFixtureGamepad alloc] initWalkStickWithHostView:host below:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [walk refresh]; walk.enabled=YES; [walk refresh]; Drain();
    WALK("no_1_0_8_jump_drawn", walk.connections==0 && !walk.visible, "no virtual controller (%lu)", (unsigned long)walk.connections);
    for (NSString *name in @[GCInputButtonA,GCInputButtonB,GCInputButtonX,GCInputButtonY,GCInputLeftShoulder,GCInputRightShoulder,
                             GCInputLeftTrigger,GCInputRightTrigger,GCInputButtonMenu,@"leftStick",@"rightStick"])
        WALK("no_1_0_8_jump_drawn", Find(host,[@"tolkara.gamepad." stringByAppendingString:name])==nil, "no %@", name);
    WALK("no_1_0_8_jump_drawn", Find(host,@"wolkaraforever.touch.walkStick")!=nil, "only the walk stick");
    CGSize size=host.bounds.size;
    CGPoint corner=CGPointMake(size.width-0.05*size.height,size.height-0.05*size.height);
    WALK("no_1_0_8_jump_drawn", [host hitTest:corner withEvent:nil]==host, "the corner is not a jump");
    [walk toggleSettings];
    WALK("no_1_0_8_jump_drawn", !walk.configuring && Find(host,@"wolkaraforever.controls.settings")==nil, "no settings sheet");
    [walk invalidate];
    areas.contract=nil;
}

// Every other mode: the walk stick never takes a touch, and the gamepad is what it was.
static void ipados_gamepad_unchanged(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    for (NSString *mode in @[AKInterfaceModeIPadOS,AKInterfaceModeIOS,AKInterfaceModeIOSDuo,@"duo"]) {
        WalkMode(mode);
        AKWalkRig rig=WalkRig(host,WalkContract());
        CGSize size=host.bounds.size;
        WALK("ipados_gamepad_unchanged", [host hitTest:CGPointMake(size.width*0.25,size.height*0.62) withEvent:nil]==host, "%@: no walk stick", mode);
        WalkRigDone(host,rig);
        AKFixtureGamepad *pad=[[AKFixtureGamepad alloc] initWithHostView:host];
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        [pad refresh];
        WALK("ipados_gamepad_unchanged", WaitUntil(^{ return (BOOL)(pad.connections==1); }), "%@: the virtual controller connects", mode);
        [pad.lastConnection finish:nil];
        WALK("ipados_gamepad_unchanged", pad.visible && Find(host,@"tolkara.gamepad.leftStick") && Find(host,@"tolkara.gamepad.rightStick") &&
             Find(host,[@"tolkara.gamepad." stringByAppendingString:GCInputButtonA]), "%@: both sticks and A", mode);
        [pad invalidate];
        WALK("ipados_gamepad_unchanged", keyed.sunk.count==0, "%@: no key", mode);
    }
}

// Two fingers are a pinch (a player, a device check): a second finger within 0.15 s of the thumb, or while the thumb has not
// walked past the dead zone, lets the host's pinch begin and the stick let go (no key left down, none sent after); a
// walking thumb and a later look finger are a walk and a look, never a pinch.
// The faint rest ring is drawn at alpha 0.4: shown is not hidden, faint but visible, in a window.
static BOOL RestShowing(UIView *rest) { return rest && !rest.hidden && rest.alpha>0.1 && rest.window; }
static void a37_two_fingers_are_a_pinch(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    [rig.areas setLive:YES windowOpen:NO];
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62), mid=CGPointMake(size.width*0.5,size.height*0.5);
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchMayBegin(host), "no thumb: the pinch is the host's");
    // A thumb that has not walked, a second finger soon: a pinch, nothing sent.
    AKFixtureTouch *thumb=WalkFinger(p); thumb.fixtureView=rig.overlay;
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchOffer(host,thumb)==1, "the first thumb may be a pinch's finger");
    WalkBegin(rig.overlay,thumb);
    AKFixtureTouch *other=WalkFinger(mid); other.fixtureView=host;
    gWalkNow+=0.05;
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchOffer(host,other)==-1, "a finger on the game is the host's to decide");
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchMayBegin(host), "soon after the thumb: a pinch");
    WALK("a37_two_fingers_are_a_pinch", keyed.sunk.count==0 && !Showing(rig.ring), "no key, no ring: %@", keyed.sunk);
    WalkMove(rig.overlay,thumb,WalkAt(p,0,-80)); WalkEnd(rig.overlay,thumb);
    WALK("a37_two_fingers_are_a_pinch", keyed.sunk.count==0, "the pinch's thumb walks nothing after: %@", keyed.sunk);
    // A thumb that walked at once, a second finger within 0.15 s: a pinch; W up again.
    thumb=WalkFinger(p); thumb.fixtureView=rig.overlay;
    WalkBegin(rig.overlay,thumb); WalkMove(rig.overlay,thumb,WalkAt(p,0,-60));
    WALK("a37_two_fingers_are_a_pinch", WalkKeysDown(keyed.sunk)==1, "walking: %@", keyed.sunk);
    gWalkNow+=0.1;
    other=WalkFinger(mid); other.fixtureView=host; (void)AKWalkStickPinchOffer(host,other);
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchMayBegin(host), "within 0.15 s: a pinch");
    WALK("a37_two_fingers_are_a_pinch", WalkKeysDown(keyed.sunk)==0, "the walk lets go: %@", keyed.sunk);
    WalkEnd(rig.overlay,thumb);
    [keyed.sunk removeAllObjects];
    // Walking, a look finger later: a walk and a look; W stays down and the walk goes on.
    thumb=WalkFinger(p); thumb.fixtureView=rig.overlay;
    WalkBegin(rig.overlay,thumb); WalkMove(rig.overlay,thumb,WalkAt(p,0,-60));
    gWalkNow+=0.4;
    other=WalkFinger(mid); other.fixtureView=host; (void)AKWalkStickPinchOffer(host,other);
    WALK("a37_two_fingers_are_a_pinch", !AKWalkStickPinchMayBegin(host), "a walking thumb and a later finger are no pinch");
    WALK("a37_two_fingers_are_a_pinch", WalkKeysDown(keyed.sunk)==1 && Showing(rig.ring), "still walking: %@", keyed.sunk);
    AKFixtureTouch *second=WalkFinger(WalkAt(p,-40,60)); second.fixtureView=rig.overlay;
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchOffer(host,second)==0, "a late second thumb on the stick is not the pinch's");
    WalkEnd(rig.overlay,thumb);
    WALK("a37_two_fingers_are_a_pinch", WalkKeysDown(keyed.sunk)==0, "lifted: %@", keyed.sunk);
    // A thumb resting inside the dead zone, a finger a second later: a pinch (it never walked).
    thumb=WalkFinger(p); thumb.fixtureView=rig.overlay;
    WalkBegin(rig.overlay,thumb); WalkMove(rig.overlay,thumb,WalkAt(p,3,-3));
    gWalkNow+=1;
    other=WalkFinger(mid); other.fixtureView=host; (void)AKWalkStickPinchOffer(host,other);
    second=WalkFinger(WalkAt(p,-40,60)); second.fixtureView=rig.overlay;
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchOffer(host,second)==1, "a second finger on a resting stick may pinch");
    WALK("a37_two_fingers_are_a_pinch", AKWalkStickPinchMayBegin(host), "a resting thumb: a pinch");
    WalkEnd(rig.overlay,thumb);
    // After the pinch the stick is a stick again.
    thumb=WalkFinger(p); WalkBegin(rig.overlay,thumb); WalkMove(rig.overlay,thumb,WalkAt(p,0,-60));
    WALK("a37_two_fingers_are_a_pinch", WalkKeysDown(keyed.sunk)==1, "a new thumb walks: %@", keyed.sunk);
    WalkEnd(rig.overlay,thumb);
    WalkRigDone(host,rig);
}
// TouchPlay's own full-screen sheets send two pulses ("left the world"). Then the stick, its rest ring and the
// lock are hidden and take no touch, and a walk or a run stops.
static void a37_two_pulses_hide_the_stick(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    [rig.areas setLive:YES windowOpen:NO];
    CGSize size=host.bounds.size;
    CGPoint p=CGPointMake(size.width*0.25,size.height*0.62);
    UIView *rest=Find(host,@"wolkaraforever.touch.walkStick.rest");
    WALK("a37_two_pulses_hide_the_stick", RestShowing(rest), "in the world: the rest ring shows");
    AKFixtureTouch *t=WalkFinger(p); WalkBegin(rig.overlay,t); WalkMove(rig.overlay,t,WalkAt(p,0,-60));
    [rig.areas setLive:NO windowOpen:NO];
    WALK("a37_two_pulses_hide_the_stick", WalkKeysDown(keyed.sunk)==0, "the walk stops: %@", keyed.sunk);
    WALK("a37_two_pulses_hide_the_stick", !RestShowing(rest) && !Showing(rig.ring) && !Showing(WalkPlate(host)), "ring, rest ring and lock hidden");
    CGRect box=rest.frame;
    for (NSValue *v in @[[NSValue valueWithCGPoint:p],[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(box),CGRectGetMidY(box))],
                         [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(box),CGRectGetMinY(box)-40)]])
        WALK("a37_two_pulses_hide_the_stick", [host hitTest:v.CGPointValue withEvent:nil]==host, "no touch is the stick's: %@", NSStringFromCGPoint(v.CGPointValue));
    WalkEnd(rig.overlay,t);
    // An auto-run under a sheet: stopped, the lock and the badge hidden.
    [rig.areas setLive:YES windowOpen:NO];
    WalkLockRun(rig.overlay,host,p);
    WALK("a37_two_pulses_hide_the_stick", rig.walk.autoRunning, "running");
    [rig.areas setLive:NO windowOpen:NO];
    WALK("a37_two_pulses_hide_the_stick", !rig.walk.autoRunning && WalkKeysDown(keyed.sunk)==0, "stopped: %@", keyed.sunk);
    WALK("a37_two_pulses_hide_the_stick", !Showing(WalkPlate(host)) && !Showing(Find(host,@"wolkaraforever.touch.autorun")) && !RestShowing(rest), "nothing drawn");
    WalkRigDone(host,rig);
}
// Left-handed (contract hand=L): the stick's whole side mirrors - the floating zone, the rest ring and the lock above it -
// and it follows the contract when a reload brings a new one.
static void a37_left_handed_mirrors_and_follows_reload(UIView *host) {
    AKFixtureHostView *keyed=(id)host;
    AKWalkRig rig=WalkRig(host,WalkContract());
    [rig.areas setLive:YES windowOpen:NO];
    CGSize size=host.bounds.size;
    UIView *rest=Find(host,@"wolkaraforever.touch.walkStick.rest");
    WALK("a37_left_handed_mirrors", RestShowing(rest) && CGRectGetMaxX(rest.frame)<=size.width/3, "hand R: the rest ring on the left: %@", NSStringFromCGRect(rest.frame));
    AKTouchContract *left=WalkContract(); left.leftHanded=YES;
    rig.areas.contract=left;
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchContractDidChangeNotification object:left];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.05,false);
    WALK("a37_left_handed_mirrors", RestShowing(rest) && CGRectGetMinX(rest.frame)>=size.width*2/3, "the reload's hand L: the rest ring on the right: %@", NSStringFromCGRect(rest.frame));
    CGPoint ringCentre=CGPointMake(CGRectGetMidX(rest.frame),CGRectGetMidY(rest.frame));
    WALK("a37_left_handed_mirrors", [host hitTest:ringCentre withEvent:nil]==rig.overlay, "its centre is the stick's");
    WALK("a37_left_handed_mirrors", [host hitTest:CGPointMake(size.width*0.25,size.height*0.62) withEvent:nil]==host, "the left third is not");
    // The lock above a ring on the right, and an auto-run locked there.
    WalkLockRun(rig.overlay,host,ringCentre);
    WALK("a37_left_handed_mirrors", rig.walk.autoRunning && WalkLockAt(host).x>size.width*2/3, "locked on the right: %@", NSStringFromCGPoint(WalkLockAt(host)));
    AKFixtureTouch *tap=WalkFinger(WalkLockAt(host)); WalkBegin(rig.overlay,tap); WalkEnd(rig.overlay,tap);
    WALK("a37_left_handed_mirrors", !rig.walk.autoRunning && WalkKeysDown(keyed.sunk)==0, "a tap on the lock stops it");
    // With a window open the stick box is on the right too.
    [rig.areas setLive:NO windowOpen:YES];
    WALK("a37_left_handed_mirrors", [host hitTest:ringCentre withEvent:nil]==rig.overlay, "window open: the right stick box");
    [rig.areas setLive:YES windowOpen:NO];
    // Back to hand R at the next reload.
    AKTouchContract *right=WalkContract();
    rig.areas.contract=right;
    [NSNotificationCenter.defaultCenter postNotificationName:AKTouchContractDidChangeNotification object:right];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.05,false);
    WALK("a37_left_handed_mirrors", CGRectGetMaxX(rest.frame)<=size.width/3, "hand R again: left: %@", NSStringFromCGRect(rest.frame));
    WalkRigDone(host,rig);
}

static void TestWalkStick(UIView *host) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    id original=[[defaults volatileDomainForName:NSArgumentDomain] objectForKey:AKInterfaceModeDefaultsKey];
    WalkMode(AKInterfaceModeIPadTouch);
    walk_area_follows_size(host);
    rule3_stick_appears_under_thumb(host);
    rule3_outside_area_no_stick(host);
    rule3_lock_keeps_running(host);
    a34_edge_hold_never_locks(host);
    a34_slide_up_and_hold_locks(host);
    a34_slide_back_cancels(host);
    a34_new_touch_and_lock_tap_stop(host);
    a34_window_open_keeps_the_stick(host);
    a34_floating_centre_and_rest_ring(host);
    a34_rest_ring_clears_areas(host);
    a34_dead_zone(host);
    a34_direction_hysteresis(host);
    rule3_left_handed_right_half(host);
    a37_two_fingers_are_a_pinch(host);
    a37_two_pulses_hide_the_stick(host);
    a37_left_handed_mirrors_and_follows_reload(host);
    rule3_ring_stays_on_screen(host);
    stick_and_spell_together(host);
    no_1_0_8_jump_drawn(host);
    ipados_gamepad_unchanged(host);
    WalkMode(original);
    puts("TOUCH_WALK_STICK_PASS: iPad touch with TouchPlay's buttons: the walk stick appears under the thumb in the outer third away from the hand, lower 55 % (never the middle; minus the buttons and the edge zone), two fingers soon or on a resting thumb are a pinch (the stick lets go, nothing sent), two pulses hide it all, left-handed mirrors it and a reload follows, walks with W/S/A/D in eight directions (12% dead zone, 8-degree hysteresis), a 175 pt floating ring with a faint rest ring off every button, locks an auto-run only up on the lock above the ring for 0.25 s (edgeRun; the edge never locks and sliding back cancels), stays live with a window open, stops on the next thumb, a tap on the lock, a cancel, a resize, a reload, leaving the app or the keyboard, plays beside a spell, draws no 1.0.8 jump or controller; every other mode unchanged.");
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
    TestControllerPointer();
    TestCrashGuard();
    TestWalkStick(host);
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
    NSArray<NSString *> *launchArguments=NSProcessInfo.processInfo.arguments;
    NSUInteger mobileFlag=[launchArguments indexOfObject:@"--mobile-interface"];
    if (mobileFlag!=NSNotFound) {
        // "--mobile-interface" alone is iOS; a value after it ("ipadtouch", "iosduo") is that mode.
        NSString *named=mobileFlag+1<launchArguments.count ? launchArguments[mobileFlag+1] : nil;
        if (!named || [named hasPrefix:@"-"]) named=@"ios";
        NSMutableDictionary *modes=[[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
        modes[@"WolkaraForeverInterfaceModeV1"]=named;
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
    if (test) { TestLifecycle(self.window.rootViewController.view); TestCrashGuardRealExit(); fflush(stdout); exit(0); }
    // A look at the walk stick for comparison with mockup 10 ("Walk stick (app)"): with --walk-preview
    // and an argument of "under", "edge" or "run", the stick is left in that state for a screenshot.
    NSUInteger preview=[NSProcessInfo.processInfo.arguments indexOfObject:@"--walk-preview"];
    if (preview!=NSNotFound) {
        UIView *host=self.window.rootViewController.view;
        NSString *state=preview+1<NSProcessInfo.processInfo.arguments.count ? NSProcessInfo.processInfo.arguments[preview+1] : @"run";
        WalkMode(AKInterfaceModeIPadTouch);
        static AKWalkRig rig;
        rig=WalkRig(host,WalkContract());
        CGPoint p=CGPointMake(host.bounds.size.width*0.25,host.bounds.size.height*0.62);
        AKFixtureTouch *t=WalkFinger(p);
        WalkBegin(rig.overlay,t);
        if ([state isEqual:@"under"]) WalkMove(rig.overlay,t,WalkAt(p,0,-20));
        else WalkMove(rig.overlay,t,WalkAt(p,0,-100));
        if ([state isEqual:@"run"]) WalkEnd(rig.overlay,t);
        NSLog(@"WALK_PREVIEW_READY %@",state);
        return;
    }
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
