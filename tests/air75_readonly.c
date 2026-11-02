/* Exercise the same native allowlist used immediately before HID output. */
#include "../native/air75_readonly.h"
#include "../native/air75_main.h"
#include <assert.h>
#include <string.h>
static void seal(unsigned char frame[64]) {
    unsigned sum = 0;
    for (int i = 4; i < 64; i++) sum += frame[i];
    frame[3] = (unsigned char)sum;
}
static void query(unsigned char frame[64], unsigned char command, unsigned char length,
                  unsigned char profile, unsigned char key) {
    memset(frame, 0, 64);
    frame[0] = 0x55; frame[1] = command; frame[4] = length ^ key;
    frame[5] = key; frame[6] = key; frame[7] = profile ^ key;
    seal(frame);
}
int main(void) {
    unsigned char frame[64];
    for (unsigned command = 0; command < 256; command++) {
        unsigned char length = command == 0xd1 ? 1 : command == 0xd5 ? 22 : 8;
        query(frame, command, length, 0, 0);
        int expected = command == 0xa1 || command == 0xa0 || command == 0xd1 || command == 0xd5;
        assert(kf_air75_read_request_allowed(frame, 0) == expected);
    }
    query(frame, 0xd5, 22, 1, 0x80);
    assert(kf_air75_read_request_allowed(frame, 0x80));
    frame[8] = 1; seal(frame);
    assert(!kf_air75_read_request_allowed(frame, 0x80));
    for (unsigned length = 0; length < 256; length++) {
        query(frame, 0xd5, length, 0, 0x80);
        assert(kf_air75_read_request_allowed(frame, 0x80) == (length == 22));
    }
    query(frame, 0xa1, 8, 0, 0x80);
    assert(!kf_air75_read_request_allowed(frame, 0x80));
    query(frame, 0xd1, 2, 0, 0);
    assert(!kf_air75_read_request_allowed(frame, 0));
    query(frame, 0xa0, 8, 1, 0);
    assert(!kf_air75_read_request_allowed(frame, 0));
    query(frame, 0xd5, 22, 2, 0);
    assert(!kf_air75_read_request_allowed(frame, 0));
    query(frame, 0xd5, 22, 0, 0);
    frame[5] = 1; seal(frame);
    assert(!kf_air75_read_request_allowed(frame, 0));
    query(frame, 0xa0, 8, 0, 0);
    frame[3] ^= 1;
    assert(!kf_air75_read_request_allowed(frame, 0));
    /* Main setters have their own allowlist; the read path still rejects D6. */
    query(frame, 0xd6, 9, 0, 0x80);
    unsigned char payload[9] = {3,15,2,0,0,4,128,0,255};
    for (int i = 0; i < 9; i++) frame[8+i] = payload[i] ^ 0x80;
    seal(frame);
    assert(kf_air75_main_request_allowed(frame, 0x80));
    assert(!kf_air75_read_request_allowed(frame, 0x80));
    for (unsigned command = 0; command < 256; command++) {
        frame[1] = command;
        assert(kf_air75_main_request_allowed(frame, 0x80) == (command == 0xd6));
    }
    frame[1] = 0xd6; frame[17] = 1; seal(frame);
    assert(!kf_air75_main_request_allowed(frame, 0x80));
    frame[17] = 0; frame[7] = 1 ^ 0x80; seal(frame);
    assert(!kf_air75_main_request_allowed(frame, 0x80));
    frame[7] = 0x80; frame[4] = 17 ^ 0x80; seal(frame);
    assert(!kf_air75_main_request_allowed(frame, 0x80));
    frame[4] = 9 ^ 0x80; frame[8] = 21 ^ 0x80; seal(frame);
    assert(!kf_air75_main_request_allowed(frame, 0x80));
    return 0;
}
