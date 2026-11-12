#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The verified-transfer window behind "4.0 MB/s · ~2h 9m left".
//
// Both numbers are computed, never sampled from the network stack: the updater reports how many
// bytes it has verified, this turns that into a rate over a moving window, and the page writes the
// rate and the estimate that follows from it. Nothing here reads a clock of its own - the caller
// passes the time - so the same reports always produce the same two numbers. That is what makes
// the states testable on this Mac and the screenshot pinnable.
//
// It is deliberately Foundation-only: the arithmetic and both fragments are checked by a suite
// that runs without a simulator (wolkaraforever/WoW/tests/test_wow_download_status.m).

typedef struct {
    double time;        // seconds on a monotonic clock chosen by the caller
    uint64_t bytes;     // verified bytes at that time
} TKDownloadSample;

// Roughly thirty seconds at no more than one sample per second, plus the ends of the window.
enum {
    TKDownloadWindowSeconds = 30,
    TKDownloadWindowCapacity = 32,
};

typedef struct {
    TKDownloadSample samples[TKDownloadWindowCapacity];
    unsigned count;
} TKDownloadWindow;

// Records a verified-bytes report and returns the throughput across the window in MB/s, or a
// negative value while less than a second of transfer is known. A window that goes backwards - a
// restarted or retried attempt reports fewer bytes than before - is unknown rather than a negative
// rate. The window is never written outside its array, however many reports arrive.
double TKDownloadWindowSpeedMBps(TKDownloadWindow *window, double now, uint64_t bytes);

// The throughput fragment, "4.0 MB/s", written with the app language's own decimal separator, or
// nil when there is no rate worth writing. Unknown, negative, zero, non-finite, and a rate that
// would round to 0.0 all read as no rate: "0.0 MB/s" is a stall described as progress.
NSString * _Nullable TKDownloadSpeedText(double megabytesPerSecond, NSLocale *locale);

// The time-left fragment, the estimate filled into `pattern` ("~%@ left"), or nil when the estimate
// is unknown, zero, or further away than a day - a day of remaining time is already "48h", which
// tells nobody anything the byte counts above it did not.
NSString * _Nullable TKDownloadRemainingText(double megabytesPerSecond, uint64_t done, uint64_t total,
                                             NSLocale *locale, NSString *pattern);

NS_ASSUME_NONNULL_END
