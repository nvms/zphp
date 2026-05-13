// XXH3-128 wrapper - returns the 128-bit digest packed big-endian to match
// PHP's hash('xxh128', ...) output (low64 first as the upper 8 bytes, then
// high64). XXH_IMPLEMENTATION inlines the entire xxhash header into this TU
#define XXH_IMPLEMENTATION
#define XXH_STATIC_LINKING_ONLY
#include "xxhash.h"

void zphp_xxh3_128(const void *data, size_t len, unsigned char out[16]) {
    XXH128_hash_t h = XXH3_128bits(data, len);
    // PHP serializes xxh128 as big-endian high64 followed by big-endian low64
    // (high half is the most significant). hash('xxh128', 'hello') yields
    // 'b5e9c1ad071b3e7fc779cfaa5e523818' where high64 = 0xb5e9c1ad071b3e7f
    XXH64_hash_t hi = h.high64;
    XXH64_hash_t lo = h.low64;
    for (int i = 0; i < 8; i++) out[i] = (unsigned char)((hi >> ((7 - i) * 8)) & 0xff);
    for (int i = 0; i < 8; i++) out[8 + i] = (unsigned char)((lo >> ((7 - i) * 8)) & 0xff);
}
