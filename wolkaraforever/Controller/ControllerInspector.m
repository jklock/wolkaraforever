// WolkaraForever layer: the controller inspector, in full.
//
// Why this exists: two buttons on the pad do nothing in this app — Share, and
// the extra top button — and we cannot tell whether the pad never sends them,
// whether iPadOS takes them for itself, or whether the game ignores them. Every
// decision we plan on top of pad input depends on which, so this reports what
// the pad has and what it does, rather than guessing.
//
// It reads. It never consumes an input, never writes to a pad, and changes
// nothing about how input reaches the game.
//
// Since the Controller Manager it no longer installs a single GameController handler:
// AKControllerManager owns discovery and every handler, and this is a subscriber. That is
// what stops two consumers in one process fighting over the same element, and it is why a
// press that is being routed into the virtual pad is still reported here - the manager
// reports it once, to everybody who asked.

#import "ControllerInspector.h"

#import "ControllerManager.h"

#import "../App/WolkaraForeverLog.h"

// Both channels: the platform's line, which is what a console run and a guest run
// show, and the layer's file, which is what is left afterwards. What the pad
// actually reports is the whole subject of this file, so it belongs in the file that
// is still readable a minute later.
#if __has_include("AKSupport.h")
#import "AKSupport.h"
#define AKCILog(...) do { AKLog(__VA_ARGS__); WKLog("input", __VA_ARGS__); } while (0)
#else
#define AKCILog(...) do { NSLog(@"[ak] %@", [NSString stringWithFormat:__VA_ARGS__]); WKLog("input", __VA_ARGS__); } while (0)
#endif

#import <UIKit/UIKit.h>

#import "../Input/InputElement.h"

// How many events the on-screen panel keeps. The log itself is not limited.
static NSUInteger const AKCIHistoryLimit = 12;

// Stick axes stream continuously; without a threshold the log becomes unreadable
// and the game pays for it. Values are logged when they cross into a different
// half-unit, so a stick reads as -2, -1, 0, 1, 2 rather than a river of floats.
static double const AKCIAxisBucket = 2.0;

@implementation AKControllerInspector {
    NSMutableArray<NSString *> *_history;
    NSMutableDictionary<NSString *, NSNumber *> *_axisBuckets;
    UILabel *_panel;
    BOOL _began;
    NSString *_currentDevice;
    NSString *_currentDeviceName;
    NSString *_currentSourceName;
}

- (NSString *)currentDevice { return _currentDevice; }
- (NSString *)currentDeviceName { return _currentDeviceName; }
- (NSString *)currentSourceName { return _currentSourceName; }

+ (instancetype)shared {
    static AKControllerInspector *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKControllerInspector new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _history = [NSMutableArray array];
        _axisBuckets = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Start

- (void)begin {
    AKControllerManager *manager = AKControllerManager.shared;
    if (_began) { [manager begin]; [manager logInventories]; return; }
    _began = YES;

    // The manager installs the handlers and publishes one normalized stream. This block
    // replaces exactly the two things the old handler installation did afterwards: name
    // the event, then hand it on. Nothing downstream of -onInput: changed when the
    // handlers moved, which is what keeps the voice trigger byte-for-byte the same.
    __weak AKControllerInspector *weakSelf = self;
    manager.onEvent = ^(NSString *element, double value, BOOL pressed,
                        NSString *device, NSString *deviceName, NSString *source) {
        AKControllerInspector *inspector = weakSelf;
        if (!inspector) return;
        // Set before -onInput: below, because that block reads them.
        inspector->_currentDevice = device;
        inspector->_currentDeviceName = deviceName;
        inspector->_currentSourceName = source;
        if ([element hasPrefix:@"controller.axis."]) [inspector noteAxis:element value:value];
        else [inspector noteElement:element value:value pressed:pressed detail:nil];
    };
    [manager begin];

    // The pad's Share button is a Print Screen key, and iPadOS spends that key on
    // the screenshot gesture before any app is offered it. The screenshot itself
    // is announced to the app, though, so Share is reachable after all: this is
    // the only route to it that the system provides.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(screenshotTaken:) name:UIApplicationUserDidTakeScreenshotNotification object:nil];
    // And the hold gesture, which the system spends on screen recording.
    [center addObserver:self selector:@selector(screenCaptureChanged:) name:UIScreenCapturedDidChangeNotification object:nil];

    AKCILog(@"inspector: watching for controller input");
    [manager logInventories];
}

- (void)screenshotTaken:(NSNotification *)notification {
    (void)notification;
    // The pad's Share button is a Print Screen key, and iPadOS spends that key on the
    // screenshot gesture before any app is offered it - so a screenshot is as close to
    // "the pad's Share was pressed" as the system gets.
    //
    // It is recorded and **not** reported as input. The first version offered it as
    // `system.screenshot` for the user to map, and the remediation review is right that
    // this is not enough: nothing in the notification says whether a pad or a thumb on
    // the screen produced it, so mapping it only moves the guess to the user. A button
    // that can start the microphone has to be one we know was pressed.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self markSystemDevice];
        [self recordLine:@"system.screenshot (recorded; not an input)"];
    });
}

- (void)screenCaptureChanged:(NSNotification *)notification {
    (void)notification;
    BOOL captured = UIScreen.mainScreen.isCaptured;
    [self markSystemDevice];
    AKCILog(@"inspector: screen capture changed, captured=%d", captured);
    // Recorded, never reported as input.
    //
    // This used to go through reportLine: as "Share held", on the reasoning that
    // iPadOS spends the pad's Share hold on screen recording, so seeing a capture
    // start meant Share was held. That is only true when the pad started it, and this
    // notification cannot tell us who did. Measured on 2026-10-16: with the iPad being
    // captured from a Mac, `isCaptured` was already 1, the change fired about a tenth
    // of a second after every launch, and the launcher started dictating by itself -
    // six times in one log, with nobody touching anything.
    [self recordLine:captured ? @"system.capture on" : @"system.capture off"];
}

// A system signal belongs to no controller, but it is still attributed to the pad
// when there is one, so a per-controller choice applies to it.
- (void)markSystemDevice {
    AKControllerManager *manager = AKControllerManager.shared;
    NSString *device = manager.currentDevice;
    _currentDevice = device.length ? device : @"system";
    _currentDeviceName = device.length ? (manager.currentDeviceName ?: @"Controller") : @"System";
    _currentSourceName = @"system";
}

#pragma mark - The system's gestures, released only on request
//
// The manager holds the pads and remembers which *reason* wants which gesture released, so
// these are forwards and there is deliberately no second copy of the bookkeeping here. A
// second copy is how a gesture ends up disabled on a pad the user never mapped.

- (BOOL)currentControllerDeclaresShare {
    return AKControllerManager.shared.currentControllerDeclaresShare;
}

- (BOOL)releaseSystemGestureForElement:(NSString *)element device:(nullable NSString *)device {
    return [AKControllerManager.shared releaseSystemGestureForElement:element device:device];
}

- (void)restoreSystemGestureForElement:(NSString *)element device:(nullable NSString *)device {
    [AKControllerManager.shared restoreSystemGestureForElement:element device:device];
}

- (void)restoreAllSystemGestures {
    [AKControllerManager.shared restoreAllSystemGestures];
}

- (void)beginReleasingForLearning {
    [AKControllerManager.shared beginReleasingForLearning];
}

- (void)endReleasingForLearning {
    [AKControllerManager.shared endReleasingForLearning];
}

#pragma mark - Inventories: what does this pad actually have?

- (void)logInventories {
    [AKControllerManager.shared logInventories];
}

#pragma mark - Reporting

- (void)noteElement:(NSString *)element value:(double)value pressed:(BOOL)pressed detail:(nullable NSString *)detail {
    NSString *line = [NSString stringWithFormat:@"%@ %@=%.2f", element, pressed ? @"pressed" : @"value", value];
    if (detail.length) line = [line stringByAppendingFormat:@" %@", detail];
    [self reportLine:line element:element value:value pressed:pressed];
}

- (void)noteAxis:(NSString *)element value:(double)value {
    NSInteger bucket = (NSInteger)lround(value * AKCIAxisBucket);
    NSNumber *last = _axisBuckets[element];
    if (last && last.integerValue == bucket) return;
    _axisBuckets[element] = @(bucket);
    [self reportLine:[NSString stringWithFormat:@"%@=%.2f", element, value]
              element:element value:value pressed:(bucket != 0)];
}

- (void)reportLine:(NSString *)line element:(NSString *)element value:(double)value pressed:(BOOL)pressed {
    [self recordLine:line];
    if (self.onInput) self.onInput(element, value, pressed);
}

// The panel's own history and the log, without pretending to be an input. Some of
// what the inspector sees is a fact about the system rather than a button, and a
// fact must not start dictation.
- (void)recordLine:(NSString *)line {
    AKCILog(@"input: %@", line);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_history addObject:line];
        while (self->_history.count > AKCIHistoryLimit) [self->_history removeObjectAtIndex:0];
        self->_panel.text = [self->_history componentsJoinedByString:@"\n"];
        [self->_panel sizeToFit];
    });
}

#pragma mark - On-screen panel

- (void)showPanel:(BOOL)visible {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!visible) { [self->_panel removeFromSuperview]; self->_panel = nil; return; }
        if (self->_panel) return;
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        UILabel *label = [UILabel new];
        label.numberOfLines = AKCIHistoryLimit;
        label.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        label.userInteractionEnabled = NO;
        label.text = @"controller inspector: waiting for input";
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [window addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:8],
            [label.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-8],
        ]];
        self->_panel = label;
    });
}

@end
