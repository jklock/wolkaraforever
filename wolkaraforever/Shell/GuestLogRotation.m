#import "GuestLogRotation.h"
#import <errno.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>

WKGuestLogKeep WKGuestLogKeepPrevious(NSString *log, NSString *previous, NSString **problem) {
    if (problem) *problem = nil;
    if (access(log.fileSystemRepresentation, F_OK) != 0) {
        if (errno == ENOENT) return WKGuestLogKeepNothing;
        if (problem) *problem = [NSString stringWithUTF8String:strerror(errno)];
        return WKGuestLogKeepFailed;
    }
    if (rename(log.fileSystemRepresentation, previous.fileSystemRepresentation) == 0) return WKGuestLogKeepMoved;
    if (problem) *problem = [NSString stringWithUTF8String:strerror(errno)];
    return WKGuestLogKeepFailed;
}
