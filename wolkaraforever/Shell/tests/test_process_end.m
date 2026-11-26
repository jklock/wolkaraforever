#import <Foundation/Foundation.h>
#import "ProcessEnd.h"
#include <spawn.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
extern char **environ;

static void abort_on_exit(void) { abort(); }
static void note_end(NSNotification *unused) {
    (void)unused;
    const char *path = getenv("WK_END_MARKER");
    [@"observed" writeToFile:@(path) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
static int child(const char *kind) {
    if (!strcmp(kind, "abort")) atexit(abort_on_exit);
    if (!strcmp(kind, "notify"))
        [NSNotificationCenter.defaultCenter addObserverForName:WKHostWillEndProcessNotification object:nil queue:nil
            usingBlock:^(NSNotification *note) { note_end(note); }];
    if (!strcmp(kind, "flush")) {
        FILE *out = fopen(getenv("WK_END_MARKER"), "w");
        if (!out) return 90;
        if (dup2(fileno(out), STDOUT_FILENO) < 0) return 91;
        fclose(out);
        setvbuf(stdout, NULL, _IOFBF, 4096);
        fputs("buffered text", stdout);
    }
    WKEndProcess(!strcmp(kind, "status") ? 3 : 0);
}
static int run(const char *self, const char *kind, NSString *marker) {
    setenv("WK_END_MARKER", marker.fileSystemRepresentation, 1);
    char *argv[] = {(char *)self, (char *)kind, NULL};
    pid_t pid;
    if (posix_spawn(&pid, self, NULL, NULL, argv, environ)) return -1;
    int status = 0;
    if (waitpid(pid, &status, 0) != pid) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2) return child(argv[1]);
        NSString *marker = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"process-end-%d", getpid()]];
        int failures = 0;
#define CHECK(value, name) do { if (!(value)) { fprintf(stderr, "FAIL %s\n", name); failures++; } } while (0)
        CHECK(run(argv[0], "abort", marker) == 0, "E1 skips atexit abort");
        CHECK(run(argv[0], "status", marker) == 3, "E2 preserves exit status");
        [NSFileManager.defaultManager removeItemAtPath:marker error:NULL];
        CHECK(run(argv[0], "notify", marker) == 0 &&
              [[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL] isEqual:@"observed"],
              "E3 notification runs synchronously");
        [NSFileManager.defaultManager removeItemAtPath:marker error:NULL];
        CHECK(run(argv[0], "flush", marker) == 0 &&
              [[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL] isEqual:@"buffered text"],
              "E4 fully buffered stdout is flushed");
        [NSFileManager.defaultManager removeItemAtPath:marker error:NULL];
        return failures ? 1 : 0;
    }
}
