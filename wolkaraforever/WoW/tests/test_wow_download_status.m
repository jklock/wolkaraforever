// The download speed and the estimate beside the byte counts, resolved without UIKit so it can run
// on this Mac.
//
// What is checked is the part that has a right answer: the throughput a given sequence of verified
// byte counts produces, the window that produces it, the cases where no estimate may be shown, and
// the words both fragments are written in. The transfer itself is not measured here - that is what
// the simulator matrix and the iPad in COMPATIBILITY.md record.
//
// Every assertion below is a value, not a range, because the two things a status line must never do
// are invent a rate and disagree with itself twice about the same input.

#import <Foundation/Foundation.h>
#import "../launcher/WoW/DownloadStatus.h"

static NSUInteger checks;

static void Check(BOOL condition, NSString *what) {
    checks++;
    if (condition) return;
    fprintf(stderr, "FAIL %s\n", what.UTF8String);
    abort();
}

static void CheckEqual(NSString *actual, NSString *expected, NSString *what) {
    Check(actual == expected || [actual isEqual:expected],
          [NSString stringWithFormat:@"%@: expected %@, got %@", what,
           expected ?: @"(nil)", actual ?: @"(nil)"]);
}

// A window fed one report per second, the way the updater reports a transfer that is keeping up.
// `bytes` carries the cumulative count across calls, because that is what the updater reports: a
// restarted attempt is the only thing that ever makes it go backwards.
static double Feed(TKDownloadWindow *window, double from, double to, double megabytesPerSecond,
                   uint64_t *bytes) {
    double rate = -1;
    for (double now = from; now <= to + 0.5; now += 1) {
        rate = TKDownloadWindowSpeedMBps(window, now, *bytes);
        *bytes += (uint64_t)(megabytesPerSecond * 1e6);
    }
    return rate;
}

// The verified bytes a transfer of `seconds` at `megabytesPerSecond` would have moved.
static uint64_t Bytes(double seconds, double megabytesPerSecond) {
    return (uint64_t)(seconds * megabytesPerSecond * 1e6);
}

int main(void) {
    @autoreleasepool {
        NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        NSLocale *german = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
        const uint64_t megabyte = 1000000;

        // --- the first second is unknown, not zero: there is no rate yet
        {
            TKDownloadWindow window = {0};
            Check(TKDownloadWindowSpeedMBps(&window, 100, 0) < 0, @"no samples at all is unknown");
            Check(TKDownloadWindowSpeedMBps(&window, 100.5, 2 * megabyte) < 0,
                  @"half a second of transfer is not a rate");
            Check(window.count == 1, @"a second report inside the first second added no sample");
        }

        // --- a steady 4 MB/s is reported as 4 MB/s, and stays there
        {
            TKDownloadWindow window = {0};
            uint64_t bytes = 0;
            Feed(&window, 0, 1, 4, &bytes);
            double rate = Feed(&window, 2, 30, 4, &bytes);
            Check(rate > 3.99 && rate < 4.01,
                  [NSString stringWithFormat:@"a steady transfer reads as 4 MB/s, got %f", rate]);
            rate = Feed(&window, 31, 300, 4, &bytes);
            Check(rate > 3.99 && rate < 4.01,
                  [NSString stringWithFormat:@"five minutes of the same transfer read the same, got %f", rate]);
        }

        // --- the window is a window: a fast start stops colouring the number once it leaves
        {
            TKDownloadWindow window = {0};
            uint64_t bytes = 0;
            Feed(&window, 0, 5, 20, &bytes);        // 20 MB/s for five seconds
            double rate = Feed(&window, 6, 29, 1, &bytes);
            Check(rate > 1.0 && rate < 20,
                  [NSString stringWithFormat:@"a burst inside the window is averaged, got %f", rate]);
            rate = Feed(&window, 30, 45, 1, &bytes);
            Check(rate > 0.99 && rate < 1.01,
                  [NSString stringWithFormat:@"once the burst leaves, the rate is the transfer, got %f", rate]);
        }

        // --- a report burst measures the whole window, not its last half second
        {
            TKDownloadWindow window = {0};
            for (int i = 0; i < 500; i++) TKDownloadWindowSpeedMBps(&window, 10 + i * 0.001, (uint64_t)i * 1000);
            Check(window.count == 1,
                  [NSString stringWithFormat:@"five hundred reports inside one second are one sample, got %u",
                   window.count]);
        }

        // --- a restarted attempt reports fewer bytes than the window saw: unknown, not negative
        {
            TKDownloadWindow window = {0};
            uint64_t bytes = 0;
            Feed(&window, 0, 60, 4, &bytes);        // the window now starts thirty seconds in
            Check(TKDownloadWindowSpeedMBps(&window, 61, 5 * megabyte) < 0,
                  @"fewer verified bytes than the window already saw is unknown");
            window.count = 0;                       // the caller resets the window with the attempt
            uint64_t restarted = 0;
            double rate = Feed(&window, 62, 72, 2, &restarted);
            Check(rate > 1.99 && rate < 2.01,
                  [NSString stringWithFormat:@"a new attempt measures from its own start, got %f", rate]);
        }

        // --- the array is never written past its end, however long the download runs
        {
            TKDownloadWindow window = {0};
            double rate = 0;
            for (unsigned second = 0; second < 10000; second++)
                rate = TKDownloadWindowSpeedMBps(&window, second, Bytes(second, 4));
            Check(window.count > 1 && window.count <= TKDownloadWindowCapacity,
                  [NSString stringWithFormat:@"ten thousand reports fit the window, got %u", window.count]);
            Check(rate > 3.99 && rate < 4.01,
                  [NSString stringWithFormat:@"ten thousand reports still read 4 MB/s, got %f", rate]);
            // The corrupt count the first version of this code could produce - one entry past the
            // array - must be dropped rather than trusted as an index.
            window.count = TKDownloadWindowCapacity + 1;
            Check(TKDownloadWindowSpeedMBps(&window, 10000, Bytes(10000, 4)) < 0,
                  @"a count past the array is dropped instead of read");
            Check(window.count == 1,
                  [NSString stringWithFormat:@"the dropped window starts again, got %u", window.count]);
        }

        // --- a full window still inside the thirty seconds drops its oldest sample
        {
            TKDownloadWindow window = {0};
            for (unsigned index = 0; index < TKDownloadWindowCapacity; index++)
                window.samples[index] = (TKDownloadSample){index * 0.5, (uint64_t)index * 1000};
            window.count = TKDownloadWindowCapacity;   // fifteen and a half seconds, all inside
            double rate = TKDownloadWindowSpeedMBps(&window, 16, 32000);
            Check(window.count == TKDownloadWindowCapacity,
                  [NSString stringWithFormat:@"the window stays full, got %u", window.count]);
            Check(rate > 0, [NSString stringWithFormat:@"the oldest sample went and the rest measured, got %f", rate]);
        }

        // --- the same reports always produce the same numbers
        {
            TKDownloadWindow one = {0}, two = {0};
            uint64_t firstBytes = 0, secondBytes = 0;
            double first = Feed(&one, 0, 45, 7, &firstBytes), second = Feed(&two, 0, 45, 7, &secondBytes);
            Check(first == second, @"two runs over the same reports agree exactly");
        }

        // --- the speed fragment, in the app language's own decimal separator
        CheckEqual(TKDownloadSpeedText(4.0, english), @"4.0 MB/s", @"4 MB/s in English");
        CheckEqual(TKDownloadSpeedText(4.0, german), @"4,0 MB/s", @"4 MB/s in German");
        CheckEqual(TKDownloadSpeedText(1234.56, english), @"1,234.6 MB/s", @"a fast transfer groups thousands");
        CheckEqual(TKDownloadSpeedText(1234.56, german), @"1.234,6 MB/s",
                   @"a fast transfer groups thousands the German way");
        Check(TKDownloadSpeedText(-1, english) == nil, @"an unknown rate writes nothing");
        Check(TKDownloadSpeedText(0, english) == nil, @"a stall is not 0.0 MB/s");
        Check(TKDownloadSpeedText(0.04, english) == nil, @"a rate that would round to 0.0 writes nothing");
        Check(TKDownloadSpeedText(0.05, english) != nil, @"the smallest rate that reads above 0.0 is written");
        Check(TKDownloadSpeedText(NAN, english) == nil, @"not a number writes nothing");
        Check(TKDownloadSpeedText(INFINITY, english) == nil, @"an infinite rate writes nothing");

        // --- the estimate, and the cases where there is none
        NSString *englishPattern = @"~%@ left", *germanPattern = @"noch ca. %@";
        CheckEqual(TKDownloadRemainingText(4, 0, Bytes(7740, 4), english, englishPattern),
                   @"~2h 9m left", @"7740 seconds at 4 MB/s is two hours nine minutes");
        CheckEqual(TKDownloadRemainingText(4, 0, Bytes(7740, 4), german, germanPattern),
                   @"noch ca. 2h 9min", @"the same estimate in German");
        CheckEqual(TKDownloadRemainingText(4, 0, Bytes(30, 4), english, englishPattern),
                   @"~30s left", @"under a minute is counted in seconds");
        CheckEqual(TKDownloadRemainingText(4, 0, Bytes(60, 4), english, englishPattern),
                   @"~1m left", @"a minute stops using seconds");
        Check(TKDownloadRemainingText(-1, 0, Bytes(600, 4), english, englishPattern) == nil,
              @"no rate, no estimate");
        Check(TKDownloadRemainingText(0, 0, Bytes(600, 4), english, englishPattern) == nil,
              @"a stall has no estimate");
        Check(TKDownloadRemainingText(4, 100, 100, english, englishPattern) == nil,
              @"nothing left to fetch has no estimate");
        Check(TKDownloadRemainingText(4, 200, 100, english, englishPattern) == nil,
              @"a total below the count has no estimate");
        // The ceiling: a day of remaining transfer is the last estimate worth writing.
        Check(TKDownloadRemainingText(1, 0, Bytes(24 * 3600, 1), english, englishPattern) != nil,
              @"exactly a day is still an estimate");
        Check(TKDownloadRemainingText(1, 0, Bytes(24 * 3600 + 1, 1), english, englishPattern) == nil,
              @"past a day the estimate is withheld");
        Check(TKDownloadRemainingText(1, 0, Bytes(100 * 24 * 3600, 1), english, englishPattern) == nil,
              @"a hundred days of transfer is not an estimate anyone can use");
        Check(TKDownloadRemainingText(4, 0, Bytes(600, 4), english, @"") == nil,
              @"an empty pattern writes nothing rather than a bare number");

        // --- the two fragments together are the tail of the status line
        {
            NSString *speed = TKDownloadSpeedText(4.0, english);
            NSString *remaining = TKDownloadRemainingText(4.0, 0, Bytes(7740, 4), english, englishPattern);
            CheckEqual([NSString stringWithFormat:@" · %@ · %@", speed, remaining],
                       @" · 4.0 MB/s · ~2h 9m left", @"the fragment the page appends to the byte counts");
        }

        printf("DOWNLOAD_STATUS_PASS: %lu checks: the throughput window, the estimate, and the words "
               "both are written in - a steady transfer reads its own rate, a burst is averaged until "
               "it leaves the window, a restarted attempt is unknown rather than negative, the array is "
               "never written past its end, and an unknown, zero or day-long estimate is withheld in "
               "both languages.\n", (unsigned long)checks);
    }
    return 0;
}
