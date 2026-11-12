// The AppKit adapter sizes a window's content view before the window is on
// screen, as AppKit documents: "The view object is resized to fit precisely
// within the content area of the window" (patch 0054). A guest sizes its window
// right after setContentView: and before showing it; a view left at 0x0 made
// Forever read convertSizeToBacking:{0, 0}, clamp the window to its 320x240
// minimum and then grow the height for seconds, so its CAMetalLayer got a
// 320-wide frame and the render target was 320 pixels wide.
//
// Run in the simulator, with no app and no scene - the pre-host path is the one
// a bare process takes: wolkaraforever/tools/test_appkit_content_view.sh
#import "AppKit.h"
#include <assert.h>

int main(void) { @autoreleasepool {
    // The client's own sequence: a window at its minimum, a content view made
    // with no frame, setContentView: before the window is shown.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:CGRectMake(0, 0, 320, 240)
                                                   styleMask:0 backing:2 defer:NO];
    NSView *view = [NSView new];
    // What the adapter used to leave: a made view has no size of its own.
    assert(CGSizeEqualToSize(view.frame.size, CGSizeZero));
    window.contentView = view;
    // Pre-host: setContentView: gives the view the content area.
    assert(window.contentView == view);
    assert(CGPointEqualToPoint(view.frame.origin, CGPointZero));
    assert(CGSizeEqualToSize(view.frame.size, CGSizeMake(320, 240)));
    assert(CGRectEqualToRect(window.contentLayoutRect, CGRectMake(0, 0, 320, 240)));

    // A window whose content area is larger than the minimum, and a view that
    // came with a frame of its own: the content area wins, as AppKit's does.
    NSWindow *big = [[NSWindow alloc] initWithContentRect:CGRectMake(0, 0, 912, 420)
                                                styleMask:0 backing:2 defer:NO];
    NSView *made = [[NSView alloc] initWithFrame:CGRectMake(5, 6, 7, 8)];
    big.contentView = made;
    assert(CGRectEqualToRect(made.frame, CGRectMake(0, 0, 912, 420)));

    // Backing conversion right after setContentView: is never {0, 0}: this is
    // the size the client reads to place its window, and {0, 0} is what clamped
    // it to 320x240 in the first place.
    CGFloat scale = big.backingScaleFactor;
    assert(scale >= 1);
    NSSize points = made.frame.size;
    NSSize pixels = [made convertSizeToBacking:points];
    assert(pixels.width == points.width * scale && pixels.height == points.height * scale);
    assert(pixels.width > 0 && pixels.height > 0);
    assert(CGSizeEqualToSize([made convertSizeFromBacking:pixels], points));

    // The client's sizing pass is a fixed point, so the window cannot crawl
    // upward: it used to grow 0.5 pt per pass for about 9.4 million passes.
    for (int pass = 0; pass < 8; pass++) {
        NSSize content = big.frame.size;
        NSSize back = [made convertSizeToBacking:content];
        NSSize forth = [made convertSizeFromBacking:back];
        [big setContentSize:content];
        assert(CGSizeEqualToSize(forth, content));
        assert(CGSizeEqualToSize(big.frame.size, CGSizeMake(912, 420)));
        assert(CGSizeEqualToSize(made.frame.size, CGSizeMake(912, 420)));
        assert([made convertSizeToBacking:made.frame.size].width == pixels.width);
    }

    // Hosted: the view follows the host view's bounds at the window's scale,
    // and the drawable the guest would make from it is the host's, not 320.
    NSWindow *hosted = [[NSWindow alloc] initWithContentRect:CGRectMake(0, 0, 320, 240)
                                                   styleMask:0 backing:2 defer:NO];
    NSView *hostedView = [NSView new];
    UIView *host = (UIView *)[NSClassFromString(@"AKHostView") new];
    assert(host != nil);
    host.frame = CGRectMake(0, 0, 912, 420);   // the scene's geometry, as UIKit reports it
    [hosted setValue:host forKey:@"host"];     // attached as ak_orderFront: attaches it
    hosted.contentView = hostedView;           // the host is there already: ak_attach
    assert(CGSizeEqualToSize(hostedView.frame.size, CGSizeMake(912, 420)));
    assert(CGRectEqualToRect(hostedView.layer.frame, CGRectMake(0, 0, 912, 420)));
    assert(hostedView.layer.contentsScale == hosted.backingScaleFactor);
    NSSize drawable = [hostedView convertSizeToBacking:hostedView.layer.bounds.size];
    assert(drawable.width == 912 * scale && drawable.height == 420 * scale);
    assert(drawable.width > 0 && drawable.height > 0);

    // A zero-size host bounds is never adopted: the last real size stays, so no
    // zero-size render target can appear from a layout pass before the host has
    // a size.
    [hosted ak_hostBoundsChanged:CGRectZero];
    assert(CGSizeEqualToSize(hostedView.frame.size, CGSizeMake(912, 420)));
    assert(CGSizeEqualToSize(hostedView.layer.bounds.size, CGSizeMake(912, 420)));

    // With a host attached, setContentView: takes the host's bounds rather than
    // the window's own content rect - three sizes, three answers.
    NSWindow *both = [[NSWindow alloc] initWithContentRect:CGRectMake(0, 0, 320, 240)
                                                 styleMask:0 backing:2 defer:NO];
    NSSize ownContent = both.frame.size;   // 320x240, before it has a host
    UIView *bothHost = (UIView *)[NSClassFromString(@"AKHostView") new];
    bothHost.frame = CGRectMake(0, 0, 1024, 768);
    [both setValue:bothHost forKey:@"host"];
    NSView *bothView = [NSView new];
    both.contentView = bothView;
    assert(CGSizeEqualToSize(bothView.frame.size, CGSizeMake(1024, 768)));
    assert(!CGSizeEqualToSize(bothView.frame.size, ownContent));

    puts("content view sizing: pre-host content area, backing conversion, fixed point, hosted bounds and no zero-size target: PASS");
} }
