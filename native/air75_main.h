/* A separate narrow setter entry; the phase 1 read allowlist is unchanged. */
#ifndef KEYFLUX_AIR75_MAIN_H
#define KEYFLUX_AIR75_MAIN_H
static int kf_air75_main_request_allowed(const unsigned char frame[64], unsigned char key) {
    if (frame[0] != 0x55 || frame[1] != 0xd6 || frame[2] ||
        (frame[4] ^ key) != 9 || (frame[5] ^ key) ||
        (frame[6] ^ key) || (frame[7] ^ key)) return 0;
    unsigned sum = 0;
    for (int i = 4; i < 64; i++) sum += frame[i];
    if ((unsigned char)sum != frame[3]) return 0;
    unsigned mode = frame[8] ^ key;
    if (mode < 1 || mode > 20 || (frame[9] ^ key) > 100 ||
        (frame[10] ^ key) > 4 || (frame[11] ^ key) > 3 ||
        (frame[12] ^ key) > 1 || (frame[13] ^ key) > 7) return 0;
    for (int i = 17; i < 64; i++) if (frame[i]) return 0;
    return 1;
}
#endif
