#import <Foundation/Foundation.h>

// Ends the host process after a game has run, without exit()'s teardown. exit() runs atexit handlers
// and C++ static destructors, the game's among them, while the game's threads are still alive; one of
// those destructors calls abort(), so every close through the closing page ended in a crash report.
// WKEndProcess posts WKHostWillEndProcessNotification (synchronously, for the host's own last
// writes), synchronizes NSUserDefaults, flushes stdio and calls _exit(code).
// atexit handlers do not run on this path: host code that must run at the end observes the notification.

FOUNDATION_EXPORT NSNotificationName const WKHostWillEndProcessNotification;
FOUNDATION_EXPORT void WKEndProcess(int code) __attribute__((noreturn));
