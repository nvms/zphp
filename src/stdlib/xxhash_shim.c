// the xxhash streaming states php's xxh32, xxh64, xxh3 and xxh128 contexts
// hold (hash.zig keeps them in context buffers laid out as php's are).
// XXH_IMPLEMENTATION inlines the entire xxhash header into this TU
#define XXH_IMPLEMENTATION
#define XXH_STATIC_LINKING_ONLY
#include "xxhash.h"

// hash.zig sizes its contexts by these, and php serializes the xxh32 and
// xxh64 states field by field
_Static_assert(sizeof(XXH32_state_t) == 48, "XXH32_state_t layout");
_Static_assert(sizeof(XXH64_state_t) == 88, "XXH64_state_t layout");
_Static_assert(sizeof(XXH3_state_t) == 576, "XXH3_state_t layout");

void zphp_xxh32_reset(XXH32_state_t *s, unsigned int seed) { XXH32_reset(s, seed); }
void zphp_xxh32_update(XXH32_state_t *s, const void *data, size_t len) { XXH32_update(s, data, len); }
unsigned int zphp_xxh32_digest(const XXH32_state_t *s) { return XXH32_digest(s); }

void zphp_xxh64_reset(XXH64_state_t *s, unsigned long long seed) { XXH64_reset(s, seed); }
void zphp_xxh64_update(XXH64_state_t *s, const void *data, size_t len) { XXH64_update(s, data, len); }
unsigned long long zphp_xxh64_digest(const XXH64_state_t *s) { return XXH64_digest(s); }

void zphp_xxh3_64_reset_seed(XXH3_state_t *s, unsigned long long seed) { XXH3_64bits_reset_withSeed(s, seed); }
void zphp_xxh3_64_reset_secret(XXH3_state_t *s, const void *secret, size_t len) { XXH3_64bits_reset_withSecret(s, secret, len); }
void zphp_xxh3_64_update(XXH3_state_t *s, const void *data, size_t len) { XXH3_64bits_update(s, data, len); }
unsigned long long zphp_xxh3_64_digest(const XXH3_state_t *s) { return XXH3_64bits_digest(s); }

void zphp_xxh3_128_reset_seed(XXH3_state_t *s, unsigned long long seed) { XXH3_128bits_reset_withSeed(s, seed); }
void zphp_xxh3_128_reset_secret(XXH3_state_t *s, const void *secret, size_t len) { XXH3_128bits_reset_withSecret(s, secret, len); }
void zphp_xxh3_128_update(XXH3_state_t *s, const void *data, size_t len) { XXH3_128bits_update(s, data, len); }

// the 128-bit digest in php's byte order: the high half big-endian, then the
// low half
void zphp_xxh3_128_digest(const XXH3_state_t *s, unsigned char out[16]) {
    XXH128_canonical_t c;
    XXH128_canonicalFromHash(&c, XXH3_128bits_digest(s));
    for (int i = 0; i < 16; i++) out[i] = c.digest[i];
}

// the secret pointer inside a state, so a copied context can point at its
// own copy of the secret
const void *zphp_xxh3_ext_secret(const XXH3_state_t *s) { return s->extSecret; }
void zphp_xxh3_set_ext_secret(XXH3_state_t *s, const void *secret) { s->extSecret = secret; }
