#pragma once

#include <stdbool.h>
#include <stdio.h>

// A deliberately small, host-only TCP diagnostic. It records no peer address, port, payload,
// DNS name, or guest data. Callers enable it for one launch before guest entry.
void nh_start(FILE *log, unsigned maximum_seconds);
void nh_stop(void);
int nh_socket(int domain, int type, int protocol);
int nh_close(int fd);
void nh_sample_now(void);
