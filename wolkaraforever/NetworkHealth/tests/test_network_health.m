#import <Foundation/Foundation.h>
#include "NetworkHealth.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static int failures;
#define CHECK(condition, message) do { if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } } while (0)

int main(void) {
    char path[] = "/tmp/wolkaraforever-network-health.XXXXXX";
    int log_fd = mkstemp(path);
    FILE *log = fdopen(log_fd, "w+");
    CHECK(log != NULL, "open a private log");
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = { .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK), .sin_port = 0 };
    CHECK(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0, "bind a local listener");
    CHECK(listen(listener, 1) == 0, "listen locally");
    socklen_t address_size = sizeof(address);
    CHECK(getsockname(listener, (struct sockaddr *)&address, &address_size) == 0, "read local listener address");
    nh_start(log, 1);
    int client = nh_socket(AF_INET, SOCK_STREAM, 0);
    CHECK(client >= 0, "create a tracked TCP socket");
    CHECK(connect(client, (struct sockaddr *)&address, sizeof(address)) == 0, "connect tracked socket");
    int accepted = accept(listener, NULL, NULL);
    CHECK(accepted >= 0, "accept local connection");
    nh_sample_now();
    nh_close(client);
    close(accepted);
    close(listener);
    nh_stop();
    fflush(log);
    fseek(log, 0, SEEK_END);
    long size = ftell(log);
    rewind(log);
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)size];
    fread(data.mutableBytes, 1, (size_t)size, log);
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    CHECK([output containsString:@"[network-health] tcp id=1"], "records anonymous TCP counters");
    CHECK(![output containsString:@"127.0.0.1"] && ![output containsString:@"localhost"], "does not record a peer address");
    CHECK(![output containsString:@"payload"], "does not record payloads");
    fclose(log);
    unlink(path);
    return failures ? 1 : 0;
}
