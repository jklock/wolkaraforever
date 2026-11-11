#import "DownloadStatus.h"

#import <string.h>

// Past this a day of transfer is expressed in two digits of minutes nobody acts on, and the number
// would run to "168h" at the end of a week. The byte counts above still say what remains.
static const double DownloadRemainingCeiling = 24 * 60 * 60;

// Below this the one-decimal rate in the status line would read "0.0 MB/s", the same words a stall
// would print. The counts still move; the rate stays unspoken until it can be read.
static const double DownloadMinimumMBps = 0.05;

double TKDownloadWindowSpeedMBps(TKDownloadWindow *window, double now, uint64_t bytes) {
    if (!window) return -1;
    unsigned count = window->count;
    // A count that cannot have come from this window is not a full window: it is a corrupt one.
    // Dropping it keeps every index below inside the array instead of trusting the number.
    if (count > TKDownloadWindowCapacity) count = 0;
    unsigned first = 0;
    // Keep the newest sample that is already thirty seconds old, so the average spans about thirty
    // seconds rather than jumping to whatever the last second or two happened to be.
    while (first + 1 < count && window->samples[first + 1].time <= now - TKDownloadWindowSeconds) first++;
    if (first) {
        count -= first;
        memmove(window->samples, window->samples + first, count * sizeof(TKDownloadSample));
    }
    if (!count || now - window->samples[count - 1].time >= 1) {
        // One sample per second at most. The updater reports progress far more often than that, and
        // a window full of those reports would average a fraction of a second and call it throughput.
        if (count == TKDownloadWindowCapacity) {
            // Full and still spanning less than the period: the oldest sample goes. This is the
            // bound the first version of this code was missing - it appended at index 31 of a
            // 31-element array, which the compiler cannot complain about and the stack cannot
            // survive; measured in this suite, the write lands on the window's own count field
            // and the next report reads and copies past the end of the struct.
            memmove(window->samples, window->samples + 1, (count - 1) * sizeof(TKDownloadSample));
            count--;
        }
        window->samples[count++] = (TKDownloadSample){now, bytes};
    }
    window->count = count;
    TKDownloadSample start = window->samples[0];
    // A second of transfer or nothing: a rate over a shorter span is the interval timer, not the
    // network. Fewer verified bytes than the window already saw means the attempt restarted.
    if (now - start.time < 1 || bytes < start.bytes) return -1;
    return (bytes - start.bytes) / (now - start.time) / 1e6;
}

static NSNumberFormatter *DownloadDecimal(NSLocale *locale) {
    NSNumberFormatter *number = [NSNumberFormatter new];
    number.locale = locale ?: NSLocale.currentLocale;
    number.numberStyle = NSNumberFormatterDecimalStyle;
    number.minimumFractionDigits = 1;
    number.maximumFractionDigits = 1;
    return number;
}

NSString *TKDownloadSpeedText(double megabytesPerSecond, NSLocale *locale) {
    if (!isfinite(megabytesPerSecond) || megabytesPerSecond < DownloadMinimumMBps) return nil;
    // "MB/s" is the same word in both languages this app ships, exactly like the byte counts'
    // "MB"; only the decimal separator and the grouping follow the app language.
    return [NSString stringWithFormat:@"%@ MB/s",
            [DownloadDecimal(locale) stringFromNumber:@(megabytesPerSecond)]];
}

NSString *TKDownloadRemainingText(double megabytesPerSecond, uint64_t done, uint64_t total,
                                  NSLocale *locale, NSString *pattern) {
    if (!isfinite(megabytesPerSecond) || megabytesPerSecond < DownloadMinimumMBps) return nil;
    if (total <= done || !pattern.length) return nil;
    double seconds = (double)(total - done) / (megabytesPerSecond * 1e6);
    if (!isfinite(seconds) || seconds <= 0 || seconds > DownloadRemainingCeiling) return nil;
    NSDateComponentsFormatter *duration = [NSDateComponentsFormatter new];
    duration.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
    // Minutes below an hour, hours and minutes above it: at four megabytes a second a second count
    // would change on every draw and mean nothing.
    duration.allowedUnits = seconds >= 60 ? (NSCalendarUnitHour | NSCalendarUnitMinute) : NSCalendarUnitSecond;
    NSCalendar *calendar = [NSCalendar.currentCalendar copy];
    calendar.locale = locale ?: NSLocale.currentLocale;
    duration.calendar = calendar;
    // Rounded up: work that is still running has at least a second left, and "~0s left" is not a
    // thing anyone wants to read.
    NSString *estimate = [duration stringFromTimeInterval:ceil(MAX(seconds, 1))];
    if (!estimate.length) return nil;
    return [NSString stringWithFormat:pattern, estimate];
}
