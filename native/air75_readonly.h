/* Phase 1 permits query reports only, independently of the Zig codec. */
#ifndef KEYFLUX_AIR75_READONLY_H
#define KEYFLUX_AIR75_READONLY_H
static int kf_air75_read_request_allowed(const unsigned char frame[64], unsigned char key) {
    if (frame[0] != 0x55 || frame[2] != 0)
        return 0;
    unsigned checksum = 0;
    for (int i = 4; i < 64; i++)
        checksum += frame[i];
    if ((unsigned char)checksum != frame[3])
        return 0;
    unsigned length = frame[4] ^ key;
    unsigned offset = (frame[5] ^ key) | ((frame[6] ^ key) << 8);
    unsigned profile = frame[7] ^ key;
    if (offset)
        return 0;
    switch (frame[1]) {
    case 0xa1:
        if (key || length != 8 || profile)
            return 0;
        break;
    case 0xa0:
        if (length != 8 || profile)
            return 0;
        break;
    case 0xd1:
        if (length != 1 || profile)
            return 0;
        break;
    case 0xd5:
        if (length != 22 || profile > 1)
            return 0;
        break;
    default:
        return 0;
    }
    for (int i = 8; i < 64; i++)
        if (frame[i])
            return 0;
    return 1;
}
#endif
