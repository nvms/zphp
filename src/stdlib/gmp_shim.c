/*
 * GMP shim for zphp. libgmp uses `mpz_init`->`__gmpz_init` style macros for
 * its public API. zig's @cImport doesn't always apply these renames, so this
 * shim provides unversioned zphp_* wrappers compiled by the C preprocessor.
 *
 * each wrapper takes plain pointers + ints. mpz_t values are heap-allocated
 * by zphp_mpz_create() and freed by zphp_mpz_destroy().
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <gmp.h>

typedef struct {
    mpz_t v;
} zphp_mpz;

zphp_mpz* zphp_mpz_create(void) {
    zphp_mpz* p = (zphp_mpz*)malloc(sizeof(zphp_mpz));
    if (!p) return NULL;
    mpz_init(p->v);
    return p;
}

void zphp_mpz_destroy(zphp_mpz* p) {
    if (!p) return;
    mpz_clear(p->v);
    free(p);
}

void zphp_mpz_set(zphp_mpz* r, const zphp_mpz* a) {
    mpz_set(r->v, a->v);
}

int zphp_mpz_set_str(zphp_mpz* p, const char* s, int base) {
    return mpz_set_str(p->v, s, base);
}

/* php integers are 64-bit everywhere, but gmp's *_si functions take a C long,
   which is 32 bits on windows; these go through the magnitude instead */
int64_t zphp_mpz_set_si(zphp_mpz* p, int64_t v) {
    if (sizeof(long) == sizeof(int64_t)) {
        mpz_set_si(p->v, (long)v);
        return 0;
    }
    uint64_t magnitude = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
    mpz_import(p->v, 1, -1, sizeof magnitude, 0, 0, &magnitude);
    if (v < 0) mpz_neg(p->v, p->v);
    return 0;
}

/* mpz_get_si as on a platform with a 64-bit long: the low 63 bits of the
   magnitude, carrying the sign, when the value does not fit */
int64_t zphp_mpz_get_si(const zphp_mpz* p) {
    if (sizeof(long) == sizeof(int64_t)) return (int64_t)mpz_get_si(p->v);
    mpz_t low;
    mpz_init(low);
    mpz_abs(low, p->v);
    mpz_tdiv_r_2exp(low, low, 64);
    uint64_t limb = 0;
    mpz_export(&limb, NULL, -1, sizeof limb, 0, 0, low);
    mpz_clear(low);
    if (mpz_sgn(p->v) >= 0) return (int64_t)(limb & (uint64_t)INT64_MAX);
    return -1 - (int64_t)((limb - 1) & (uint64_t)INT64_MAX);
}

char* zphp_mpz_get_str(int base, const zphp_mpz* p) {
    return mpz_get_str(NULL, base, p->v);
}

void zphp_gmp_free(void* p) {
    if (!p) return;
    void (*free_fn)(void*, size_t);
    mp_get_memory_functions(NULL, NULL, &free_fn);
    /* mpz_get_str uses gmp's allocator. compute length to free */
    free_fn(p, strlen((const char*)p) + 1);
}

void zphp_mpz_add(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_add(r->v, a->v, b->v); }
void zphp_mpz_sub(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_sub(r->v, a->v, b->v); }
void zphp_mpz_mul(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_mul(r->v, a->v, b->v); }
void zphp_mpz_tdiv_q(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_tdiv_q(r->v, a->v, b->v); }
void zphp_mpz_tdiv_r(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_tdiv_r(r->v, a->v, b->v); }
void zphp_mpz_mod(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_mod(r->v, a->v, b->v); }
void zphp_mpz_pow_ui(zphp_mpz* r, const zphp_mpz* a, unsigned long e) { mpz_pow_ui(r->v, a->v, e); }
void zphp_mpz_powm(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* e, const zphp_mpz* m) {
    mpz_powm(r->v, a->v, e->v, m->v);
}
void zphp_mpz_sqrt(zphp_mpz* r, const zphp_mpz* a) { mpz_sqrt(r->v, a->v); }
void zphp_mpz_root(zphp_mpz* r, const zphp_mpz* a, unsigned long n) { mpz_root(r->v, a->v, n); }
void zphp_mpz_neg(zphp_mpz* r, const zphp_mpz* a) { mpz_neg(r->v, a->v); }
void zphp_mpz_abs(zphp_mpz* r, const zphp_mpz* a) { mpz_abs(r->v, a->v); }
int zphp_mpz_cmp(const zphp_mpz* a, const zphp_mpz* b) { return mpz_cmp(a->v, b->v); }
int zphp_mpz_sgn(const zphp_mpz* a) { return mpz_sgn(a->v); }
void zphp_mpz_and(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_and(r->v, a->v, b->v); }
void zphp_mpz_ior(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_ior(r->v, a->v, b->v); }
void zphp_mpz_xor(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_xor(r->v, a->v, b->v); }
void zphp_mpz_com(zphp_mpz* r, const zphp_mpz* a) { mpz_com(r->v, a->v); }
void zphp_mpz_gcd(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_gcd(r->v, a->v, b->v); }
void zphp_mpz_lcm(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* b) { mpz_lcm(r->v, a->v, b->v); }
int zphp_mpz_invert(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* m) { return mpz_invert(r->v, a->v, m->v); }
void zphp_mpz_mul_2exp(zphp_mpz* r, const zphp_mpz* a, unsigned long e) { mpz_mul_2exp(r->v, a->v, e); }
void zphp_mpz_tdiv_q_2exp(zphp_mpz* r, const zphp_mpz* a, unsigned long e) { mpz_tdiv_q_2exp(r->v, a->v, e); }
double zphp_mpz_get_d(const zphp_mpz* a) { return mpz_get_d(a->v); }
int zphp_mpz_fits_i64(const zphp_mpz* a) {
    if (sizeof(long) == sizeof(int64_t)) return mpz_fits_slong_p(a->v);
    size_t bits = mpz_sizeinbase(a->v, 2);
    if (bits <= 63) return 1;
    if (bits != 64 || mpz_sgn(a->v) >= 0) return 0;
    /* only -2^63 fits in 64 bits */
    return mpz_scan1(a->v, 0) == 63;
}
void zphp_mpz_fdiv_q_2exp(zphp_mpz* r, const zphp_mpz* a, unsigned long e) { mpz_fdiv_q_2exp(r->v, a->v, e); }
int zphp_mpz_probab_prime_p(const zphp_mpz* a, int reps) { return mpz_probab_prime_p(a->v, reps); }
void zphp_mpz_nextprime(zphp_mpz* r, const zphp_mpz* a) { mpz_nextprime(r->v, a->v); }
size_t zphp_mpz_sizeinbase(const zphp_mpz* a, int base) { return mpz_sizeinbase(a->v, base); }
int zphp_mpz_testbit(const zphp_mpz* a, unsigned long bit) { return mpz_tstbit(a->v, bit); }
void zphp_mpz_setbit(zphp_mpz* a, unsigned long bit) { mpz_setbit(a->v, bit); }
void zphp_mpz_clrbit(zphp_mpz* a, unsigned long bit) { mpz_clrbit(a->v, bit); }
unsigned long zphp_mpz_popcount(const zphp_mpz* a) { return mpz_popcount(a->v); }
unsigned long zphp_mpz_scan0(const zphp_mpz* a, unsigned long start) { return mpz_scan0(a->v, start); }
unsigned long zphp_mpz_scan1(const zphp_mpz* a, unsigned long start) { return mpz_scan1(a->v, start); }
int zphp_mpz_legendre(const zphp_mpz* a, const zphp_mpz* p) { return mpz_legendre(a->v, p->v); }
int zphp_mpz_jacobi(const zphp_mpz* a, const zphp_mpz* b) { return mpz_jacobi(a->v, b->v); }
int zphp_mpz_perfect_square_p(const zphp_mpz* a) { return mpz_perfect_square_p(a->v); }
int zphp_mpz_fits_ulong_p(const zphp_mpz* a) { return mpz_fits_ulong_p(a->v); }
uint64_t zphp_mpz_get_ui64(const zphp_mpz* a) {
    uint64_t v = 0;
    if (mpz_sgn(a->v) != 0) mpz_export(&v, NULL, -1, sizeof v, 0, 0, a->v);
    return v;
}
int zphp_mpz_odd_p(const zphp_mpz* a) { return mpz_odd_p(a->v); }
void zphp_mpz_fac_ui(zphp_mpz* r, unsigned long n) { mpz_fac_ui(r->v, n); }
void zphp_mpz_bin_ui(zphp_mpz* r, const zphp_mpz* n, unsigned long k) { mpz_bin_ui(r->v, n->v, k); }
void zphp_mpz_powm_sec(zphp_mpz* r, const zphp_mpz* a, const zphp_mpz* e, const zphp_mpz* m) { mpz_powm_sec(r->v, a->v, e->v, m->v); }
/* mpz_prevprime (gmp 6.3): 2 when the result is surely prime, 1 when probably */
int zphp_mpz_prevprime(zphp_mpz* r, const zphp_mpz* a) { return mpz_prevprime(r->v, a->v); }
