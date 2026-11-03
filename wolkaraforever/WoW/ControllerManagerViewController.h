#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The Controller Manager page: the one place a person switches physical-controller
// routing on and edits what each control drives.
//
// It is presented from Performance & UI Manager, and it is launcher-only in this version -
// the page changes preferences; the manager applies them to the running session. Nothing
// here reads or writes a WoW binding, GamePadConfig_*.json or Config.wtf: the game's own
// GamePadEnable switch stays a separate row with a separate owner.
@interface TKWoWControllerManagerViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
