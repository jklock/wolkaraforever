#import "ProcessEnd.h"
#import <stdio.h>
#import <unistd.h>

NSNotificationName const WKHostWillEndProcessNotification = @"WolkaraForeverHostWillEndProcess";

void WKEndProcess(int code) {
    [NSNotificationCenter.defaultCenter postNotificationName:WKHostWillEndProcessNotification object:nil];
    [NSUserDefaults.standardUserDefaults synchronize];
    fflush(NULL);
    _exit(code);
}
