#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WKGuestLogKeep) { WKGuestLogKeepFailed = -1, WKGuestLogKeepNothing = 0, WKGuestLogKeepMoved = 1 };
FOUNDATION_EXPORT WKGuestLogKeep WKGuestLogKeepPrevious(NSString *log, NSString *previous, NSString *_Nullable *_Nullable problem);
NS_ASSUME_NONNULL_END
