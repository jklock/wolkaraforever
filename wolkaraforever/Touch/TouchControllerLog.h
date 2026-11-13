#import <Foundation/Foundation.h>

// The touch controller's own log: one tag, a closed set of events, a closed set of keys, and
// values that cannot carry anything but a word.
//
// It exists because this feature adds states nobody can see on a screenshot - a layout that
// migrated, a gesture that was recognised or refused, a press and its release - and a device
// log is where those are read back. It is deliberately narrow: there is no key a coordinate, a
// touch trail, a path, a name the player typed, or any description of what the game did could
// travel in. A value that is not a short word becomes "-".
//
// Nothing here reaches the guest, and nothing here inspects it.

NS_ASSUME_NONNULL_BEGIN

/// The tag every line carries: `[touch-controller]`.
FOUNDATION_EXPORT NSString *const AKTouchControllerLogTag;

typedef NS_ENUM(NSInteger, AKTouchControllerEvent) {
    /// A layout migration, a mode change, a zone added or cleared.
    AKTouchControllerEventLayout = 0,
    /// A gesture recognised or refused (the L3/R3 double tap).
    AKTouchControllerEventGesture,
    /// A virtual press either went out or was refused before it did.
    AKTouchControllerEventPress,
    /// The release that goes with a press.
    AKTouchControllerEventRelease,
    /// The drag threshold: a tap became motion, or a centroid jump was rebased.
    AKTouchControllerEventThreshold,
    /// A cancellation, with the reason it happened.
    AKTouchControllerEventCancel,
    /// Lifecycle cleanup: background, resize, teardown, a controller arriving.
    AKTouchControllerEventLifecycle,
};

/// The event's spelling in the line ("layout", "gesture", "press", "release", "threshold",
/// "cancel", "lifecycle").
FOUNDATION_EXPORT NSString *AKTouchControllerEventName(AKTouchControllerEvent event);

/// The keys a line may carry. Anything else is dropped: a new key is a decision, not an
/// accident, and the fixture proves a hostile one never reaches the line.
///
/// `mode` `control` `element` `reason` `outcome` `from` `to` `count` `version` `source` `zone` `ms`
FOUNDATION_EXPORT NSArray<NSString *> *AKTouchControllerLogKeys(void);

/// The line, built and bounded, so a fixture can read it without a device log. Keys are emitted
/// in the fixed order `AKTouchControllerLogKeys()` returns; a key with no value is omitted; a
/// value that is not 1-24 characters of `[A-Za-z0-9._-]` becomes "-".
FOUNDATION_EXPORT NSString *AKTouchControllerLogLine(AKTouchControllerEvent event,
                                                    NSString *outcome,
                                                    NSDictionary<NSString *, NSString *> * _Nullable values);

/// Where lines go. Nil - the app's own case - means they are written to the log. A fixture sets
/// it to collect them and assert on what a press and a cancellation actually emitted.
FOUNDATION_EXPORT void (*_Nullable AKTouchControllerLogSink)(NSString *line);

/// Emits one line through the sink, or the log when there is no sink.
FOUNDATION_EXPORT void AKTouchControllerLog(AKTouchControllerEvent event,
                                            NSString *outcome,
                                            NSDictionary<NSString *, NSString *> * _Nullable values);

NS_ASSUME_NONNULL_END
