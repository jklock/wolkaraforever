// WolkaraForever: the bounded command path from a physical controller to the Composer.
//
// Why this exists. The inspector used to hand every interesting event to the main queue as its
// own block, and that block did everything in one go: the handoff counter, the device mark, the
// readable line, the panel redraw and - last - the call the router makes a trigger out of. Any
// work in front of it was work in front of a mapped button, and the diagnostic path is exactly
// the work that can be plentiful (the 2026-11-04 device log held 25,316 controller lines from one
// five-minute run). The reported lag was plausible; nothing had measured it, and nothing had put
// the two paths in an order.
//
// So there are now two paths, and only one of them is a command:
//
//   * This class. It is handed *mapped button edges only*, assigns each a sequence number, holds
//     them in a bounded FIFO and schedules exactly one main-queue drain for the whole batch. The
//     drain delivers to `AKInputRouter`, which stays the single owner of trigger semantics. An
//     axis, a d-pad position, a touch-pad sample or a repeated sample never enters the FIFO: none
//     of them is a press, and a queue that accepts them is a queue that delays presses with
//     samples.
//   * The inspector's diagnostics. Independent, bounded, and after the enqueue, so a log line or
//     a panel redraw can no longer stand between the pad and the trigger it fires.
//
// Turning `enabled` off restores the pre-feature path exactly: the inspector keeps the edge and
// hands it to the router on the main queue the way it always did. Saved mappings are untouched,
// because the ingress contains no mapping state at all.

#import <Foundation/Foundation.h>

#import "InputInterest.h"

NS_ASSUME_NONNULL_BEGIN

/// Why an edge was not turned into a command. Every value except `None` is counted, and the ones
/// the ingress deliberately swallowed are also traced when tracing is on.
typedef NS_ENUM(NSInteger, AKControllerCommandRejection) {
    AKControllerCommandRejectionNone = 0,
    /// Not a controller button: an axis, a d-pad position, a touch-pad sample, a key, a click.
    AKControllerCommandRejectionNotAPress,
    /// The same element in the same state as the sample before it: a held press, not another one.
    AKControllerCommandRejectionRepeat,
    /// The bounded FIFO was full. A non-zero count is a failed run, per the performance contract.
    AKControllerCommandRejectionOverflow,
    /// The router has not published a destination yet, so nothing could be delivered.
    AKControllerCommandRejectionNoRoute,
};

/// One admitted edge, in the order the pad produced it. Immutable: the drain must deliver what
/// was admitted, not what some later sample says.
@interface AKControllerCommand : NSObject
/// Monotonic over the life of the process, starting at 1.
@property (nonatomic, readonly) uint64_t sequence;
@property (nonatomic, copy, readonly) NSString *element;
@property (nonatomic, readonly) BOOL pressed;
@property (nonatomic, readonly) double value;
/// The pad's model identity. Logged nowhere: it is not a serial number, but it is not the
/// command either, and the log lines this class writes must never carry a device identifier.
@property (nonatomic, copy, readonly) NSString *device;
/// Seconds, monotonic, taken the moment the pad's callback reached us.
@property (nonatomic, readonly) NSTimeInterval admitted;
@end

@interface AKControllerCommandIngress : NSObject

+ (instancetype)shared;

/// The feature flag the completion gate names. Stored, default YES; turning it off makes the
/// inspector behave exactly as it did before this class existed.
@property (atomic) BOOL enabled;

/// Where the drain delivers. `AKInputRouter` sets this when it starts. While it is nil nothing is
/// admitted - a command with nowhere to go is an input the user made and the app silently lost.
@property (atomic, copy, nullable) void (^deliver)(AKControllerCommand *command);

/// Called from GameController's own thread, inside the pad's button handler. Cheap on purpose:
/// one immutable snapshot read, one dictionary test and one array append before it returns.
///
/// YES means the ingress has taken responsibility for the edge - it was enqueued, or it was
/// deliberately dropped as a repeat or an overflow - and the caller must not deliver it again.
/// NO means it could not take it (not a controller button, no route, feature off), and the
/// caller must use the ordinary path.
- (BOOL)submitElement:(NSString *)element
                value:(double)value
              pressed:(BOOL)pressed
               device:(nullable NSString *)device
            rejection:(nullable AKControllerCommandRejection *)rejection;

/// Aggregation only. These are not logs and reading them clears nothing; `-resetCounters` is
/// what a fixture calls between runs, and it also forgets the held state, so one case cannot
/// make the next one look like a repeat.
@property (atomic, readonly) NSUInteger admittedCount;
@property (atomic, readonly) NSUInteger deliveredCount;
@property (atomic, readonly) NSUInteger rejectedCount;
@property (atomic, readonly) NSUInteger overflowCount;
@property (atomic, readonly) NSUInteger drainCount;
/// Admitted to delivered, in milliseconds. The first half of the performance contract's
/// "physical button callback to native Composer state update" boundary; the Composer adds its
/// own measurement for the second half.
@property (nonatomic, readonly) AKTimingSamples *latency;
/// The monotonic time of the most recently admitted edge, so the caller that opens the Composer
/// can report the whole interval from the pad rather than from the trigger.
@property (atomic, readonly) NSTimeInterval lastAdmitted;
- (void)resetCounters;

#pragma mark - Bounded tracing

/// One structured `controller-input` line, from anywhere in this feature. The budget is shared,
/// not per caller: a long session must not be able to turn this channel into the flood the
/// 2026-11-04 log was, and a single note says when the budget ran out.
///
/// Never pass text, speech, a controller serial or any user identifier. Element ids, sequence
/// numbers, counts and milliseconds only.
///
/// `trace:` is for the events a support log has to contain whether or not anyone was watching:
/// an overflow, a claim being given back, the outcome of opening the Composer. `traceSequence:`
/// is the per-edge trail - admission and drain - which follows the inspector's diagnostics
/// switch, so ordinary play writes one line per rare event and not one per press.
+ (void)trace:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)traceSequence:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
/// Whether anything is being traced at all. Off is the same switch as the shell's diagnostics.
@property (class, atomic) BOOL tracingEnabled;
/// Give the budget back. A fixture calls this between runs; the app calls it when diagnostics are
/// switched on, so a fresh investigation starts with lines available.
+ (void)resetTrace;

/// `AKChatComposerSourceController`: the entry point the adapter calls a mapped button's. Spelled
/// here because the shell names the notification by hand (it does not link the adapter), and the
/// two sides must not drift apart.
extern NSInteger const AKControllerCommandComposerSourceController;

/// Log the answer to a Composer open, which the adapter reports before the press handler returns.
/// `source` is the `AKChatComposerSource` that asked: the toolbar and the keyboard are the
/// adapter's own entry points and produce nothing here, because they are not this feature's to
/// report. Milliseconds are measured from the pad's admitted stamp to now, which is the whole
/// boundary the performance contract names - and a stale stamp is reported as `n/a`, not as a
/// slow press.
+ (void)traceComposerOpenOutcome:(NSString *)outcome source:(NSInteger)source;

@end

NS_ASSUME_NONNULL_END
