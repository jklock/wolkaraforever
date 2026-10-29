#import "WolkaraForeverTheme.h"
#import "WolkaraForeverLog.h"

UIColor *WKInk(void)   { return [UIColor colorWithRed:0.015 green:0.025 blue:0.045 alpha:1]; }
UIColor *WKGold(void)  { return [UIColor colorWithRed:0.90  green:0.72  blue:0.35  alpha:1]; }
UIColor *WKMuted(void) { return [UIColor colorWithRed:0.62  green:0.68  blue:0.75  alpha:1]; }
UIColor *WKPanel(void) { return [UIColor colorWithWhite:1 alpha:0.08]; }
UIColor *WKOnGold(void){ return [UIColor colorWithRed:0.08  green:0.065 blue:0.035 alpha:1]; }

UILabel *WKLabel(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label=[UILabel new];
    label.numberOfLines=0;
    label.textColor=color;
    label.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
    label.adjustsFontForContentSizeCategory=YES;
    // Rows below a wrapping label must not squeeze it, or the explanation is the
    // first thing to disappear on a short window.
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    return label;
}

UILabel *WKHeading(NSString *text) {
    UILabel *label=WKLabel(12,UIFontWeightSemibold,WKGold());
    label.text=text.uppercaseString;
    return label;
}

UILabel *WKNote(NSString *text) {
    UILabel *label=WKLabel(13,UIFontWeightRegular,WKMuted());
    label.text=text;
    return label;
}

UIView *WKCard(void) {
    UIView *panel=[UIView new];
    panel.backgroundColor=WKPanel();
    panel.layer.cornerRadius=14;
    panel.layer.masksToBounds=YES;
    return panel;
}

UIButton *WKRowButton(NSString *identifier) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityIdentifier=identifier;
    button.tintColor=WKGold();
    UIButtonConfiguration *configuration=UIButtonConfiguration.plainButtonConfiguration;
    configuration.title=@"";
    configuration.baseForegroundColor=WKGold();
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(6,0,6,0);
    configuration.titleAlignment=UIButtonConfigurationTitleAlignmentLeading;
    button.configuration=configuration;
    button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    return button;
}

// Twenty attempts of a tenth of a second is several times the longest dismissal UIKit has; a
// page still up after that is one the person opened, and putting ours over it would be the wrong
// answer anyway.
static void WKPresentWhenFreeAfter(UIViewController *controller, void (^presentation)(void),
                                   NSInteger attempts) {
    if (!controller) return;
    if (!controller.presentedViewController) { presentation(); return; }
    if (attempts<=0) {
        WKLog("ui", @"not presenting over %@: it is still presented",
              NSStringFromClass(controller.presentedViewController.class));
        return;
    }
    __weak UIViewController *weakController=controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        WKPresentWhenFreeAfter(weakController, presentation, attempts-1);
    });
}

void WKPresentWhenFree(UIViewController *controller, void (^presentation)(void)) {
    WKPresentWhenFreeAfter(controller, presentation, 20);
}

void WKDismissPage(UIViewController *page) {
    UINavigationController *frame=page.navigationController;
    WKLog("ui", @"closing %@ (frame=%@ presenter=%@)", NSStringFromClass(page.class),
          frame ? @"nav" : @"none",
          (frame ? frame.presentingViewController : page.presentingViewController) ? @"yes" : @"no");
    // Dismiss is sent to the page's own navigation controller, because that is the
    // thing that was presented. UIKit forwards a dismissal from a presented
    // controller to whoever presented it, which is the route that does not depend on
    // reading the presenter back - and reading it back was wrong here: measured in
    // the fixture on 2026-10-16, it came back nil for the voice page, the call fell
    // through to a pop that the root cannot do, and the sheet simply stayed open.
    if ((frame ? frame.presentingViewController : page.presentingViewController) || frame.isBeingPresented) {
        [frame dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    // Pushed: the launcher's own navigation stack. Kept for any path that still
    // pushes, so a page can never be left with no way out.
    if (frame.viewControllers.count > 1) [frame popViewControllerAnimated:YES];
}
