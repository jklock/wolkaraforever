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
#import <QuartzCore/CAMetalLayer.h>
#include <assert.h>
#include <stdio.h>
#include <unistd.h>

static NSUInteger LayerIndex(CALayer *parent, CALayer *child) {
    return [parent.sublayers indexOfObjectIdenticalTo:child];
}

static NSUInteger Occurrences(NSString *text, NSString *needle) {
    NSUInteger count = 0;
    NSRange rest = NSMakeRange(0, text.length);
    while (rest.length) {
        NSRange found = [text rangeOfString:needle options:0 range:rest];
        if (found.location == NSNotFound) break;
        count++;
        rest = NSMakeRange(NSMaxRange(found), text.length - NSMaxRange(found));
    }
    return count;
}

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
    // AKHostView adds overlays after attachment; they must remain above the game.
    UIView *overlay = [UIView new];
    [host addSubview:overlay];
    assert(overlay.layer.superlayer == host.layer);
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

    // L1: the guest rebuilds its renderer while its content view is hosted.
    CALayer *oldHostedLayer = hostedView.layer;
    NSUInteger hostedIndex = LayerIndex(host.layer, oldHostedLayer);
    assert(hostedIndex != NSNotFound);
    FILE *captured = tmpfile();
    assert(captured != NULL);
    int savedStderr = dup(STDERR_FILENO);
    assert(savedStderr >= 0);
    fflush(stderr);
    assert(dup2(fileno(captured), STDERR_FILENO) >= 0);
    CAMetalLayer *metal = [CAMetalLayer layer];
    metal.contentsScale = 3;
    hostedView.layer = metal;
    assert(hostedView.layer == metal);
    assert(metal.superlayer == host.layer);
    assert(LayerIndex(host.layer, metal) == hostedIndex);
    assert(LayerIndex(host.layer, overlay.layer) > LayerIndex(host.layer, metal));
    assert(oldHostedLayer.superlayer == nil);

    // L8 and L6: layer properties are preserved; setting the same layer again
    // neither moves it nor emits another replacement log.
    assert(CGPointEqualToPoint(metal.anchorPoint, CGPointZero));
    assert(CGRectEqualToRect(metal.frame, hostedView.frame));
    assert(metal.delegate == nil);
    assert(metal.hidden == hostedView.hidden);
    hostedView.layer = metal;
    assert(LayerIndex(host.layer, metal) == hostedIndex);
    assert(metal.superlayer == host.layer);

    // L9: host geometry and scale continue to reach the replacement layer.
    metal.contentsScale = 3;
    host.frame = CGRectMake(0, 0, 800, 600);
    [hosted ak_hostBoundsChanged:host.bounds];
    assert(CGRectEqualToRect(metal.frame, CGRectMake(0, 0, 800, 600)));
    assert(metal.contentsScale == hosted.backingScaleFactor);

    // L10: a hosted nil layer can be replaced later without losing the host.
    hostedView.layer = nil;
    assert(metal.superlayer == nil);
    CAMetalLayer *afterHostedNil = [CAMetalLayer layer];
    afterHostedNil.contentsScale = 3;
    hostedView.layer = afterHostedNil;
    assert(afterHostedNil.superlayer == host.layer);
    assert(LayerIndex(host.layer, afterHostedNil) == hostedIndex);
    assert(LayerIndex(host.layer, overlay.layer) > LayerIndex(host.layer, afterHostedNil));
    assert(CGRectEqualToRect(afterHostedNil.frame, hostedView.frame));

    // L12: replacement takes the window scale immediately, before host layout.
    assert(afterHostedNil.contentsScale == hosted.backingScaleFactor);

    // Without a remembered index, the content-view fallback still finds the host.
    [afterHostedNil removeFromSuperlayer];
    CAMetalLayer *withoutHostedMemory = [CAMetalLayer layer];
    hostedView.layer = withoutHostedMemory;
    assert(withoutHostedMemory.superlayer == host.layer);

    // L2: replacing a middle sibling keeps its exact stacking position.
    NSView *parent = [[NSView alloc] initWithFrame:CGRectMake(0, 0, 300, 200)];
    NSView *first = [NSView new], *middle = [NSView new], *last = [NSView new];
    [parent addSubview:first];
    [parent addSubview:middle];
    [parent addSubview:last];
    CALayer *oldMiddle = middle.layer;
    NSUInteger middleIndex = LayerIndex(parent.layer, oldMiddle);
    assert(middleIndex == 1);
    CALayer *newMiddle = [CALayer layer];
    middle.layer = newMiddle;
    assert(newMiddle.superlayer == parent.layer);
    assert(LayerIndex(parent.layer, newMiddle) == middleIndex);
    assert(oldMiddle.superlayer == nil);
    assert(parent.layer.sublayers.count == 3);
    assert(parent.layer.sublayers[0] == first.layer);
    assert(parent.layer.sublayers[2] == last.layer);

    // L6: a repeated assignment must not move a middle sibling to the top.
    middle.layer = newMiddle;
    assert(parent.layer.sublayers.count == 3);
    assert(LayerIndex(parent.layer, newMiddle) == 1);
    assert(parent.layer.sublayers[2] == last.layer);

    // L11: a replacement already below the old layer keeps the old view index.
    CALayer *siblingBelow = [CALayer layer];
    [parent.layer insertSublayer:siblingBelow atIndex:0];
    middle.layer = siblingBelow;
    assert(siblingBelow.superlayer == parent.layer);
    assert(LayerIndex(parent.layer, siblingBelow) == middleIndex);
    assert(newMiddle.superlayer == nil);
    assert(parent.layer.sublayers[0] == first.layer);
    assert(parent.layer.sublayers[2] == last.layer);

    // L3: children move in view order, rather than remaining in the orphan.
    NSView *childA = [NSView new], *childB = [NSView new];
    [middle addSubview:childA];
    [middle addSubview:childB];
    CALayer *withChildren = [CALayer layer];
    middle.layer = withChildren;
    assert(withChildren.sublayers.count == 2);
    assert(withChildren.sublayers[0] == childA.layer);
    assert(withChildren.sublayers[1] == childB.layer);
    assert(oldMiddle.sublayers.count == 0);
    assert(newMiddle.sublayers.count == 0);

    // L4: nil removes the old layer; a later assignment rejoins the parent.
    middle.layer = nil;
    assert(withChildren.superlayer == nil);
    CALayer *afterNil = [CALayer layer];
    middle.layer = afterNil;
    assert(afterNil.superlayer == parent.layer);
    assert(LayerIndex(parent.layer, afterNil) == middleIndex);

    // Without remembered placement, the superview fallback restores view order.
    [afterNil removeFromSuperlayer];
    CALayer *withoutSubviewMemory = [CALayer layer];
    middle.layer = withoutSubviewMemory;
    assert(withoutSubviewMemory.superlayer == parent.layer);
    assert(LayerIndex(parent.layer, withoutSubviewMemory) == middleIndex);

    // L5: an unattached view still accepts a layer and sets its geometry.
    NSView *detached = [[NSView alloc] initWithFrame:CGRectMake(7, 8, 90, 60)];
    CALayer *loose = [CALayer layer];
    detached.layer = loose;
    assert(detached.layer == loose && loose.superlayer == nil);
    assert(CGPointEqualToPoint(loose.anchorPoint, CGPointZero));
    assert(CGRectEqualToRect(loose.frame, detached.frame));

    // L7: only the hosted, on-screen replacement was logged, exactly once.
    fflush(stderr);
    assert(dup2(savedStderr, STDERR_FILENO) >= 0);
    close(savedStderr);
    assert(fseek(captured, 0, SEEK_END) == 0);
    long logSize = ftell(captured);
    assert(logSize >= 0);
    rewind(captured);
    NSMutableData *logData = [NSMutableData dataWithLength:(NSUInteger)logSize];
    assert(fread(logData.mutableBytes, 1, (NSUInteger)logSize, captured) == (NSUInteger)logSize);
    fclose(captured);
    NSString *log = [[NSString alloc] initWithData:logData encoding:NSUTF8StringEncoding];
    assert(log != nil);
    NSString *replacementLine = @"[ak] view layer replaced on screen: CALayer -> CAMetalLayer (main thread=1)\n";
    assert(Occurrences(log, replacementLine) == 1);
    assert(Occurrences(log, @"view layer replaced on screen:") == 1);

    puts("content view sizing: pre-host content area, backing conversion, fixed point, hosted bounds and no zero-size target: PASS");
} }
