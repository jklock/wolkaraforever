#import <UIKit/UIKit.h>

// A desktop loop can own the main thread indefinitely. While a mouse button is held
// or native controls are being configured, give UIKit complete turns in both modes.
// Pointer drags, sliders and scroll views route work outside the default mode. Zero-duration turns
// alone also skip the before-waiting observers used to finish deferred UI work.
// Keep the existing nonblocking path when the panel/editor is closed.
static inline void AKPumpTouchEvents(BOOL tracking) {
    CFTimeInterval duration = tracking ? .001 : 0;
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, duration, false);
    if (tracking)
        CFRunLoopRunInMode((__bridge CFStringRef)UITrackingRunLoopMode, duration, false);
}
