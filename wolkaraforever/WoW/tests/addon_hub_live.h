#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The Add-on Hub's live run, in the simulator, against the real thing.
//
// This is not a mock of the page: it fabricates the installation the way a player's own folder
// looks - every directory the client and the launcher use, with the game's binaries replaced by
// a placeholder file - so the production `TKAppLibrary` discovers it, the production
// `TKWoWViewController` opens the hub through its own `manageAddons` route, and everything the
// page then does is the shipped code against the real CurseForge API, the real CDN and a real
// `WKWebView`.
//
// Passed the API key in `WK_LIVE_API_KEY`, it exercises the API half too. Without a key the API
// steps report NOT RUN rather than pretending, and every other step still runs.
BOOL TKAddonHubLiveRequested(void);

// Returns YES when every step that could run passed. `capture` writes one screenshot by name.
BOOL TKAddonHubLiveRun(UIWindow *window, void (^capture)(NSString *name));

NS_ASSUME_NONNULL_END
