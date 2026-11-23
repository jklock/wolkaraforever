// WolkaraForever: the Battery Saver options, as a page of their own.
//
// The switch that applies them lives on the home page, but this page is reachable whether that
// switch is on or off: the two choices are remembered independently, they are what the switch
// turns on, and a person setting them up should not have to turn the feature on first. Every
// tap writes the stored choice through BatterySaverPolicy, which validates it, and only the
// next launch is affected.

#import <UIKit/UIKit.h>

@interface AKBatterySaverOptionsViewController : UIViewController
@end
