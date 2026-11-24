#import "UpdateLock.h"
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

int TKWoWAcquireUpdateLock(NSString *installationRoot, NSError **error) {
    NSString *parent=installationRoot.stringByDeletingLastPathComponent;
    NSString *work=[parent stringByAppendingPathComponent:@".tolkara-updates"];
    NSFileManager *manager=NSFileManager.defaultManager;
    if (![manager createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:error]) return -1;
    // The work directory itself must be a real directory, not a link placed in its stead. This
    // is asked of that one path, with lstat: comparing a fully resolved path also rejected
    // every container whose ancestors are reachable through the usual /var → /private/var
    // alias, so on the installed build no add-on could be imported, disabled, removed or
    // grouped at all (`createGroupNamed:` reported "Update directory must not be a symlink.",
    // `addons-page` self-test, 2026-11-23). The lock file itself is still opened O_NOFOLLOW.
    struct stat workInformation;
    if (lstat(work.fileSystemRepresentation,&workInformation)!=0 ||
        !S_ISDIR(workInformation.st_mode)) {
        if (error) *error=[NSError errorWithDomain:@"WolkaraForever.UpdateLock" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Update directory must not be a symlink."}];
        return -1;
    }
    int descriptor=open([[work stringByAppendingPathComponent:@"update.lock"] fileSystemRepresentation],O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if (descriptor<0 || flock(descriptor,LOCK_EX|LOCK_NB)) {
        if (descriptor>=0) close(descriptor);
        if (error) *error=[NSError errorWithDomain:@"WolkaraForever.UpdateLock" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Another game or add-on update is finishing. Try again shortly."}];
        return -1;
    }
    return descriptor;
}

void TKWoWReleaseUpdateLock(int descriptor) {
    if (descriptor>=0) { flock(descriptor,LOCK_UN); close(descriptor); }
}
