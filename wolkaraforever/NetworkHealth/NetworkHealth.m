#include "NetworkHealth.h"

#include <dispatch/dispatch.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <os/lock.h>
#include <stdatomic.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

enum { NHMaximumSockets = 32, NHMaximumSeconds = 15 * 60 };
static int sockets[NHMaximumSockets];
static FILE *health_log;
static dispatch_source_t timer;
static os_unfair_lock health_lock = OS_UNFAIR_LOCK_INIT;
static atomic_bool active;

static void clear_sockets(void) {
    for (unsigned i = 0; i < NHMaximumSockets; i++) sockets[i] = -1;
}

static void write_sample(unsigned identifier, int fd) {
    struct tcp_connection_info info = {0};
    socklen_t size = sizeof(info);
    int queued = 0;
    if (getsockopt(fd, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &size) != 0) return;
    (void)ioctl(fd, FIONREAD, &queued);
    FILE *log = health_log;
    if (!log) return;
    flockfile(log);
    fprintf(log, "[network-health] tcp id=%u state=%u rtt_ms=%u cwnd=%u queued=%d tx_bytes=%llu rx_bytes=%llu retransmit_bytes=%llu\n",
            identifier, (unsigned)info.tcpi_state, (unsigned)info.tcpi_srtt,
            (unsigned)info.tcpi_snd_cwnd, queued, (unsigned long long)info.tcpi_txbytes,
            (unsigned long long)info.tcpi_rxbytes, (unsigned long long)info.tcpi_txretransmitbytes);
    funlockfile(log);
}

void nh_sample_now(void) {
    if (!atomic_load(&active)) return;
    os_unfair_lock_lock(&health_lock);
    // Keep a descriptor recorded until its counter read completes. Without this lock a close on
    // another guest thread could let the kernel reuse its number for an unrelated connection.
    for (unsigned i = 0; i < NHMaximumSockets; i++) if (sockets[i] >= 0) write_sample(i + 1, sockets[i]);
    os_unfair_lock_unlock(&health_lock);
}

void nh_start(FILE *log, unsigned maximum_seconds) {
    if (!log || atomic_exchange(&active, true)) return;
    health_log = log;
    os_unfair_lock_lock(&health_lock);
    clear_sockets();
    os_unfair_lock_unlock(&health_lock);
    unsigned seconds = maximum_seconds ? (maximum_seconds < NHMaximumSeconds ? maximum_seconds : NHMaximumSeconds) : NHMaximumSeconds;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_MSEC * 250);
    dispatch_source_set_event_handler(timer, ^{ nh_sample_now(); });
    dispatch_resume(timer);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ nh_stop(); });
    fprintf(log, "[network-health] enabled: anonymous TCP health counters for at most %u seconds\n", seconds);
}

void nh_stop(void) {
    if (!atomic_exchange(&active, false)) return;
    dispatch_source_t old_timer = timer;
    timer = nil;
    if (old_timer) dispatch_source_cancel(old_timer);
    os_unfair_lock_lock(&health_lock);
    clear_sockets();
    os_unfair_lock_unlock(&health_lock);
    if (health_log) fprintf(health_log, "[network-health] stopped\n");
    health_log = NULL;
}

int nh_socket(int domain, int type, int protocol) {
    int fd = socket(domain, type, protocol);
    int saved_errno = errno;
    if (fd >= 0 && atomic_load(&active) && (domain == AF_INET || domain == AF_INET6) && (type & SOCK_STREAM)) {
        os_unfair_lock_lock(&health_lock);
        for (unsigned i = 0; i < NHMaximumSockets; i++) if (sockets[i] < 0) { sockets[i] = fd; break; }
        os_unfair_lock_unlock(&health_lock);
    }
    errno = saved_errno;
    return fd;
}

int nh_close(int fd) {
    os_unfair_lock_lock(&health_lock);
    for (unsigned i = 0; i < NHMaximumSockets; i++) if (sockets[i] == fd) sockets[i] = -1;
    os_unfair_lock_unlock(&health_lock);
    int result = close(fd);
    int saved_errno = errno;
    errno = saved_errno;
    return result;
}
