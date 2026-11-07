// Original fixture: tests our lifecycle with fake transports, then permits
// manual testing of Apple's real virtual controller. No game or network.
#import <UIKit/UIKit.h>
#import "../translation/AppKit/TouchGamepad.h"
#import "../translation/AppKit/TouchGamepadLayout.h"
#import "../translation/AppKit/TouchHaptics.h"
#include <assert.h>
#include <math.h>
#include <unistd.h>
#import "../translation/AppKit/AKTouchEventPump.h"

@interface AKTouchGamepad (FixtureSeams)
- (NSArray<GCController *> *)connectedControllers;
- (GCVirtualController *)makeController;
- (AKTouchHaptics *)makeHaptics;
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
@end
@implementation AKPreviewGamepad
- (AKTouchHaptics *)makeHaptics { self.feedback=[AKFixtureHaptics new]; return self.feedback; }
- (GCVirtualController *)makeController { self.created=[super makeController]; return self.created; }
- (NSArray<GCController *> *)connectedControllers {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ignore-other-controllers"] ||
        [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"]) return @[];
    return [super connectedControllers];
}
@end


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

static UIView *Find(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) { UIView *found=Find(child,identifier); if (found) return found; }
    return nil;
}
static UIControl *Button(UIView *host, NSString *name) {
    UIControl *control=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:name]);
    assert(control && !control.hidden); return control;
}
static void Drain(void) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false); }
@interface AKFixtureTouch : UITouch
@property CGPoint point;
@end
@implementation AKFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
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
static void TestNativeInput(UIView *host, AKPreviewGamepad *manager) {
    GCExtendedGamepad *pad=manager.created.controller.extendedGamepad;
    assert(pad && manager.visible);
    [host layoutIfNeeded];
    // Ring sectors own their visible area and leave the stick and separator gaps untouched.
    // + used to share the bottom labels' row; the app's toolbar now has the bottom centre
    // (44 pt tall, 8 pt up), so + is centred just above it.
    UIButton *top=(id)Button(host,@"dpad.up");
    CALayer *guestSurface=[CALayer layer];
    guestSurface.frame=host.bounds; [host.layer addSublayer:guestSurface];
    assert(top.superview.superview.layer.zPosition > guestSurface.zPosition);
    [guestSurface removeFromSuperlayer];
    assert([top pointInside:CGPointMake(108,26) withEvent:nil]);
    assert(![top pointInside:CGPointMake(108,108) withEvent:nil]);
    assert(![top pointInside:CGPointMake(26,108) withEvent:nil]);
    assert(![top pointInside:CGPointMake(166,50) withEvent:nil]);
    UIButton *a=(id)Button(host,GCInputButtonA), *plus=(id)Button(host,GCInputButtonMenu);
    CGRect plusFrame=[plus convertRect:plus.bounds toView:host];
    assert(a && fabs(CGRectGetMidX(plusFrame)-CGRectGetMidX(host.bounds))<1);
    assert(CGRectGetMaxY(plusFrame)<=CGRectGetMaxY(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets))-8-44-4);
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
    // The app's toolbar sits at the bottom centre, 44 pt tall and 8 pt up: the sheet hangs from
    // the top and leaves that strip free.
    CGFloat toolbarTop=CGRectGetMaxY(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets))-8-44;
    assert(CGRectGetMaxY([panel convertRect:panel.bounds toView:host])<=toolbarTop+0.5);
    CGRect normalBounds=host.bounds;
    host.bounds=CGRectMake(0,0,390,600); [host layoutIfNeeded];
    assert(CGRectContainsRect(host.bounds,[panel convertRect:panel.bounds toView:host]));
    UIView *done=Find(host,@"wolkaraforever.controls.done");
    assert(done && CGRectContainsRect(panel.bounds,[done convertRect:done.bounds toView:panel]));
    host.bounds=normalBounds; [host layoutIfNeeded];
    UISwitch *outer=(id)Find(host,@"wolkaraforever.controls.swapShoulders");
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
    UISwitch *sticksOnly=(id)Find(host,@"wolkaraforever.controls.sticksOnly");
    assert(sticksOnly.on);
    sticksOnly.on=NO; [sticksOnly sendActionsForControlEvents:UIControlEventValueChanged];
    [manager toggleSettings]; [host layoutIfNeeded];
    // The full layout's menu button waits above the app's toolbar, not under it.
    UIControl *menu=Button(host,GCInputButtonMenu);
    assert(!menu.hidden && CGRectGetMaxY([menu convertRect:menu.bounds toView:host])<=
        CGRectGetMaxY(UIEdgeInsetsInsetRect(host.bounds,host.safeAreaInsets))-8-44-4);
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchDown];
    [Button(host,GCInputButtonA) sendActionsForControlEvents:UIControlEventTouchUpInside];
    assert(manager.feedback.buttons==silentButtons+1 && manager.feedback.enabled);
    assert(fabs(cluster.frame.size.width-216)<.01);
    assert(CGRectGetMidX(Button(host,GCInputLeftTrigger).frame)>CGRectGetMidX(Button(host,GCInputLeftShoulder).frame));
    assert(CGRectGetMidX(Button(host,GCInputRightTrigger).frame)<CGRectGetMidX(Button(host,GCInputRightShoulder).frame));
    TestPreferences();
    TestJumpReach(host,manager);
    manager.keyboardVisible=YES; Drain();
    assert(!manager.visible && !pad.leftShoulder.pressed && !pad.buttonA.pressed);
    assert(!manager.feedback.enabled);
    assert(pad.leftThumbstick.xAxis.value==0 && pad.rightThumbstick.yAxis.value==0);
    [leftStick cancelTrackingWithEvent:nil]; [rightStick cancelTrackingWithEvent:nil];
    [manager invalidate];
    puts("TOUCH_GAMEPAD_INPUT_PASS: all nine buttons, D-pad diagonals/opposition/cancel, both sticks, held modifiers, neutral reset and trackpad passthrough.");
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
    __block BOOL trackingTimer=NO, defaultCompletion=NO, trackingCompletion=NO;
    CFRunLoopTimerRef timer=CFRunLoopTimerCreateWithHandler(NULL,CFAbsoluteTimeGetCurrent(),0,0,0,
        ^(__unused CFRunLoopTimerRef t) { trackingTimer=YES; });
    CFRunLoopAddTimer(loop,timer,(__bridge CFStringRef)UITrackingRunLoopMode);
    CFRunLoopObserverRef observer=CFRunLoopObserverCreateWithHandler(NULL,kCFRunLoopBeforeWaiting,true,0,
        ^(__unused CFRunLoopObserverRef o,__unused CFRunLoopActivity a) {
            CFStringRef mode=CFRunLoopCopyCurrentMode(loop);
            if (CFEqual(mode,kCFRunLoopDefaultMode)) defaultCompletion=YES;
            if (CFEqual(mode,(__bridge CFStringRef)UITrackingRunLoopMode)) trackingCompletion=YES;
            CFRelease(mode);
        });
    CFRunLoopAddObserver(loop,observer,kCFRunLoopCommonModes);
    AKPumpTouchEvents(NO);
    assert(!trackingTimer && !defaultCompletion && !trackingCompletion);
    // What this checks is that a turn in each mode reaches the work queued for it: the timer
    // in UITrackingRunLoopMode, and the before-waiting observers in both modes. A turn that
    // finds a ready source fires it and returns without ever sleeping, so before-waiting is
    // not guaranteed by a single call on a loaded machine - this assertion failed twice under
    // load and passed five times when idle before it was bounded. The pump is called
    // repeatedly in production for the same reason, so pump until the loop has slept in both
    // modes, with a ceiling so a genuine hang fails here rather than sitting in the run loop.
    for (int turn = 0; turn < 200 && !(trackingTimer && defaultCompletion && trackingCompletion); turn++)
        AKPumpTouchEvents(YES);
    // Said out loud, as the insert check in the touch-controls fixture is: which of the three
    // the loop never reached is the whole diagnosis.
    if (!(trackingTimer && defaultCompletion && trackingCompletion))
        fprintf(stderr, "TOUCH_TRACKING_PUMP_MISSING: timer=%d default=%d tracking=%d\n",
                (int)trackingTimer, (int)defaultCompletion, (int)trackingCompletion);
    assert(trackingTimer && defaultCompletion && trackingCompletion);
    CFRunLoopTimerInvalidate(timer); CFRelease(timer);
    CFRunLoopObserverInvalidate(observer); CFRelease(observer);
    puts("TOUCH_TRACKING_PUMP_PASS: deferred UI and tracking timers progress; closed-panel pump remains nonblocking.");
}

static void TestLifecycle(UIView *host) {
    TestTrackingPump();
    TestStickMapping();
    TestHaptics();
    AKFixtureGamepad *pad=[[AKFixtureGamepad alloc] initWithHostView:host];
    [pad refresh]; assert(pad.connections==1 && !pad.visible);
    AKFixtureController *physical=[AKFixtureController new]; physical.extendedGamepad=@YES;
    pad.devices=@[(id)physical]; [pad refresh];
    [pad.lastConnection finish:nil]; assert(!pad.visible && pad.lastConnection.disconnects);
    pad.devices=@[]; [pad refresh]; [pad.lastConnection finish:nil]; assert(pad.visible);
    // Our own connect event must never be mistaken for physical hardware.
    pad.devices=@[pad.lastConnection.controller];
    [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:pad.lastConnection.controller];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,false);
    assert(pad.visible && pad.connections==2);
    pad.devices=@[]; pad.keyboardVisible=YES; assert(!pad.visible && pad.lastConnection.disconnects);
    pad.keyboardVisible=NO; [pad.lastConnection finish:nil]; assert(pad.visible);
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
    pad.enabled=NO; pad.enabled=YES; [pad.lastConnection finish:nil]; assert(pad.visible);
    [pad toggleSettings]; assert(pad.configuring);
    pad.devices=@[(id)physical]; [pad refresh]; assert(!pad.visible && !pad.configuring);
    assert(!Find(host,@"wolkaraforever.controls.settings"));
    pad.devices=@[]; [pad refresh]; [pad.lastConnection finish:nil]; assert(pad.visible);
    [pad toggleSettings];
    UISwitch *edit=(id)Find(host,@"wolkaraforever.controls.edit");
    edit.on=YES; [edit sendActionsForControlEvents:UIControlEventValueChanged]; assert(pad.configuring);
    pad.devices=@[(id)physical]; [pad refresh]; assert(!pad.visible && !pad.configuring);
    physical.isSnapshot=YES; [pad refresh]; [pad.lastConnection finish:nil]; assert(pad.visible);
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
    if (test || [NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraForeverTouchLayoutV1"];
    // Sticks only is the default layout; the input checks below are about every button, so
    // they start from the full gamepad, with the shoulders where an empty layout puts them.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test-input"])
        [NSUserDefaults.standardUserDefaults setObject:@{@"sticksOnly":@NO,@"swapShoulders":@YES}
            forKey:@"WolkaraForeverTouchLayoutV1"];
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
    [self.gamepad refresh];
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
                fputs("TOUCH_GAMEPAD_LIFECYCLE_TIMEOUT\n",stderr); _Exit(1);
            });
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(AKGamepadFixtureApp.class));
    }
}
