/* Air75 V3 one-shot query transport. No lighting/keymap/firmware setters. */
#define _DARWIN_C_SOURCE 1
#include "hidapi.h"
#include "air75_readonly.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef __APPLE__
#include "hidapi_darwin.h"
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
static int air75_lock = -1;
#endif
static hid_device *air75;
extern uint64_t kf_monotonic_ns(void);

void kf_air75_close(void) {
    if (air75)
        hid_close(air75);
    air75 = NULL;
    hid_exit();
#ifdef __APPLE__
    if (air75_lock >= 0)
        close(air75_lock);
    air75_lock = -1;
#endif
}

int kf_air75_open(void) {
#ifndef __APPLE__
    return -5;
#else
    if (air75)
        return -1;
    char path[160];
    snprintf(path, sizeof(path), "/private/tmp/keyflux-air75-%u.lock", getuid());
    air75_lock = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    if (air75_lock < 0 || flock(air75_lock, LOCK_EX | LOCK_NB)) {
        kf_air75_close();
        return -2;
    }
    if (hid_init()) {
        kf_air75_close();
        return -1;
    }
    hid_darwin_set_open_exclusive(0);
    struct hid_device_info *head = hid_enumerate(0x19f5, 0x1028), *chosen = NULL;
    int count = 0;
    for (struct hid_device_info *p = head; p; p = p->next) {
        if (p->usage_page == 1 && p->usage == 0 && p->interface_number == 3 &&
            p->bus_type == HID_API_BUS_USB) {
            chosen = p;
            count++;
        }
    }
    if (count != 1) {
        hid_free_enumeration(head);
        kf_air75_close();
        return count ? -4 : -3;
    }
    air75 = hid_open_path(chosen->path);
    hid_free_enumeration(head);
    if (!air75) {
        kf_air75_close();
        return -1;
    }
    return 0;
#endif
}

int kf_air75_descriptor(unsigned char *out, size_t capacity) {
    return air75 ? hid_get_report_descriptor(air75, out, capacity) : -1;
}

int kf_air75_exchange(const unsigned char frame[64], unsigned char reply[64], unsigned char key) {
    /* Check before touching HID; no caller can broaden the query allowlist. */
    if (!kf_air75_read_request_allowed(frame, key))
        return -7;
    if (!air75)
        return -1;
    unsigned char discarded[128];
    for (int i = 0; i < 16; i++)
        if (hid_read_timeout(air75, discarded, sizeof(discarded), 0) <= 0)
            break;
    unsigned char output[65];
    output[0] = 0;
    memcpy(output + 1, frame, 64);
    if (hid_write(air75, output, sizeof(output)) != (int)sizeof(output))
        return -8;
    uint64_t deadline = kf_monotonic_ns() + 700000000ULL;
    while (kf_monotonic_ns() < deadline) {
        int n = hid_read_timeout(air75, discarded, sizeof(discarded), 50);
        if (n < 0)
            return -9;
        if (n == 64 && discarded[0] == 0xaa && discarded[1] == frame[1]) {
            memcpy(reply, discarded, 64);
            return 0;
        }
    }
    return -10;
}
