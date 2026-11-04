#import <UIKit/UIKit.h>

// A desktop loop can own the main thread indefinitely. While our native controls
// are being configured, give UIKit complete turns in both modes: sliders and
// scroll views route tracking work outside the default mode. Zero-duration turns
// alone also skip the before-waiting observers used to finish deferred UI work.
// Keep the existing nonblocking path when the panel/editor is closed.
static inline void AKPumpTouchEvents(BOOL configuring) {
    CFTimeInterval duration = configuring ? .001 : 0;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, duration, false);
    if (configuring)
        CFRunLoopRunInMode((__bridge CFStringRef)UITrackingRunLoopMode, duration, false);
}
