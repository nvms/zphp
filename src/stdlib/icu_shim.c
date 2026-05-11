/*
 * ICU symbol shim for zphp.
 *
 * libicu uses preprocessor macros to rename its public API per ABI version
 * (u_strFromUTF8 -> u_strFromUTF8_77, etc). Zig's @cImport doesn't apply
 * these renames consistently, so direct calls from zig fail to link on
 * platforms where U_DISABLE_RENAMING is 0 (most linux distros).
 *
 * This shim is compiled by the system C compiler, so the preprocessor
 * resolves the renames naturally. Each wrapper has an unversioned name
 * (zphp_<icu_name>) that zig can link to directly on every platform.
 */

#include <stddef.h>
#include <stdint.h>
#include <unicode/utypes.h>
#include <unicode/uloc.h>
#include <unicode/ustring.h>
#include <unicode/unorm2.h>
#include <unicode/ucol.h>
#include <unicode/unum.h>
#include <unicode/utrans.h>
#include <unicode/udat.h>
#include <unicode/umsg.h>
#include <unicode/uidna.h>

/* ----- utf-16 / utf-8 conversion ----- */

UChar* zphp_u_strFromUTF8(UChar* dest, int32_t cap, int32_t* pLen, const char* src, int32_t srcLen, UErrorCode* err) {
    return u_strFromUTF8(dest, cap, pLen, src, srcLen, err);
}

char* zphp_u_strToUTF8(char* dest, int32_t cap, int32_t* pLen, const UChar* src, int32_t srcLen, UErrorCode* err) {
    return u_strToUTF8(dest, cap, pLen, src, srcLen, err);
}

/* ----- Normalizer ----- */

const UNormalizer2* zphp_unorm2_getNFCInstance(UErrorCode* err) { return unorm2_getNFCInstance(err); }
const UNormalizer2* zphp_unorm2_getNFDInstance(UErrorCode* err) { return unorm2_getNFDInstance(err); }
const UNormalizer2* zphp_unorm2_getNFKCInstance(UErrorCode* err) { return unorm2_getNFKCInstance(err); }
const UNormalizer2* zphp_unorm2_getNFKDInstance(UErrorCode* err) { return unorm2_getNFKDInstance(err); }
const UNormalizer2* zphp_unorm2_getNFKCCasefoldInstance(UErrorCode* err) { return unorm2_getNFKCCasefoldInstance(err); }
int32_t zphp_unorm2_normalize(const UNormalizer2* n, const UChar* src, int32_t srcLen, UChar* dest, int32_t cap, UErrorCode* err) {
    return unorm2_normalize(n, src, srcLen, dest, cap, err);
}
UBool zphp_unorm2_isNormalized(const UNormalizer2* n, const UChar* src, int32_t srcLen, UErrorCode* err) {
    return unorm2_isNormalized(n, src, srcLen, err);
}

/* ----- Locale ----- */

const char* zphp_uloc_getDefault(void) { return uloc_getDefault(); }
void zphp_uloc_setDefault(const char* locale, UErrorCode* err) { uloc_setDefault(locale, err); }
int32_t zphp_uloc_getLanguage(const char* loc, char* buf, int32_t cap, UErrorCode* err) {
    return uloc_getLanguage(loc, buf, cap, err);
}
int32_t zphp_uloc_getCountry(const char* loc, char* buf, int32_t cap, UErrorCode* err) {
    return uloc_getCountry(loc, buf, cap, err);
}
int32_t zphp_uloc_getScript(const char* loc, char* buf, int32_t cap, UErrorCode* err) {
    return uloc_getScript(loc, buf, cap, err);
}
int32_t zphp_uloc_canonicalize(const char* loc, char* buf, int32_t cap, UErrorCode* err) {
    return uloc_canonicalize(loc, buf, cap, err);
}
int32_t zphp_uloc_getDisplayName(const char* loc, const char* inLocale, UChar* buf, int32_t cap, UErrorCode* err) {
    return uloc_getDisplayName(loc, inLocale, buf, cap, err);
}
int32_t zphp_uloc_getDisplayLanguage(const char* loc, const char* inLocale, UChar* buf, int32_t cap, UErrorCode* err) {
    return uloc_getDisplayLanguage(loc, inLocale, buf, cap, err);
}
int32_t zphp_uloc_getDisplayCountry(const char* loc, const char* inLocale, UChar* buf, int32_t cap, UErrorCode* err) {
    return uloc_getDisplayCountry(loc, inLocale, buf, cap, err);
}
int32_t zphp_uloc_getDisplayScript(const char* loc, const char* inLocale, UChar* buf, int32_t cap, UErrorCode* err) {
    return uloc_getDisplayScript(loc, inLocale, buf, cap, err);
}

/* ----- Collator ----- */

UCollator* zphp_ucol_open(const char* loc, UErrorCode* err) { return ucol_open(loc, err); }
void zphp_ucol_close(UCollator* c) { ucol_close(c); }
UCollationResult zphp_ucol_strcoll(const UCollator* c, const UChar* a, int32_t aLen, const UChar* b, int32_t bLen) {
    return ucol_strcoll(c, a, aLen, b, bLen);
}
void zphp_ucol_setStrength(UCollator* c, UCollationStrength s) { ucol_setStrength(c, s); }
UCollationStrength zphp_ucol_getStrength(const UCollator* c) { return ucol_getStrength(c); }

/* ----- NumberFormatter ----- */

UNumberFormat* zphp_unum_open(UNumberFormatStyle s, const UChar* pat, int32_t patLen, const char* loc, void* parse_err, UErrorCode* err) {
    return unum_open(s, pat, patLen, loc, parse_err, err);
}
void zphp_unum_close(UNumberFormat* f) { unum_close(f); }
int32_t zphp_unum_formatInt64(const UNumberFormat* f, int64_t v, UChar* buf, int32_t cap, void* pos, UErrorCode* err) {
    return unum_formatInt64(f, v, buf, cap, pos, err);
}
int32_t zphp_unum_formatDouble(const UNumberFormat* f, double v, UChar* buf, int32_t cap, void* pos, UErrorCode* err) {
    return unum_formatDouble(f, v, buf, cap, pos, err);
}
int32_t zphp_unum_formatDoubleCurrency(const UNumberFormat* f, double v, UChar* ccy, UChar* buf, int32_t cap, void* pos, UErrorCode* err) {
    return unum_formatDoubleCurrency(f, v, ccy, buf, cap, pos, err);
}
double zphp_unum_parseDouble(const UNumberFormat* f, const UChar* src, int32_t srcLen, int32_t* parsePos, UErrorCode* err) {
    return unum_parseDouble(f, src, srcLen, parsePos, err);
}
void zphp_unum_setAttribute(UNumberFormat* f, UNumberFormatAttribute attr, int32_t v) { unum_setAttribute(f, attr, v); }
void zphp_unum_setDoubleAttribute(UNumberFormat* f, UNumberFormatAttribute attr, double v) { unum_setDoubleAttribute(f, attr, v); }
int32_t zphp_unum_getAttribute(const UNumberFormat* f, UNumberFormatAttribute attr) { return unum_getAttribute(f, attr); }

/* ----- Transliterator ----- */

UTransliterator* zphp_utrans_openU(const UChar* id, int32_t idLen, UTransDirection dir, const UChar* rules, int32_t rulesLen, UParseError* pe, UErrorCode* err) {
    return utrans_openU(id, idLen, dir, rules, rulesLen, pe, err);
}
void zphp_utrans_close(UTransliterator* t) { utrans_close(t); }
void zphp_utrans_transUChars(const UTransliterator* t, UChar* text, int32_t* textLen, int32_t textCap, int32_t start, int32_t* limit, UErrorCode* err) {
    utrans_transUChars(t, text, textLen, textCap, start, limit, err);
}

/* ----- IntlDateFormatter ----- */

UDateFormat* zphp_udat_open(UDateFormatStyle timeStyle, UDateFormatStyle dateStyle, const char* locale, const UChar* tzID, int32_t tzIDLen, const UChar* pattern, int32_t patternLen, UErrorCode* err) {
    return udat_open(timeStyle, dateStyle, locale, tzID, tzIDLen, pattern, patternLen, err);
}
void zphp_udat_close(UDateFormat* f) { udat_close(f); }
int32_t zphp_udat_format(const UDateFormat* f, double date, UChar* result, int32_t resultLen, void* pos, UErrorCode* err) {
    return udat_format(f, date, result, resultLen, pos, err);
}
double zphp_udat_parse(const UDateFormat* f, const UChar* text, int32_t textLen, int32_t* parsePos, UErrorCode* err) {
    return udat_parse(f, text, textLen, parsePos, err);
}
void zphp_udat_applyPattern(UDateFormat* f, UBool localized, const UChar* pattern, int32_t patternLen) {
    udat_applyPattern(f, localized, pattern, patternLen);
}
int32_t zphp_udat_toPattern(const UDateFormat* f, UBool localized, UChar* result, int32_t resultLen, UErrorCode* err) {
    return udat_toPattern(f, localized, result, resultLen, err);
}

/* ----- IDNA (UTS46) ----- */

UIDNA* zphp_uidna_openUTS46(uint32_t options, UErrorCode* err) {
    return uidna_openUTS46(options, err);
}
void zphp_uidna_close(UIDNA* idna) { uidna_close(idna); }
int32_t zphp_uidna_nameToASCII(const UIDNA* idna, const UChar* name, int32_t nameLen, UChar* dest, int32_t cap, UIDNAInfo* info, UErrorCode* err) {
    return uidna_nameToASCII(idna, name, nameLen, dest, cap, info, err);
}
int32_t zphp_uidna_nameToUnicode(const UIDNA* idna, const UChar* name, int32_t nameLen, UChar* dest, int32_t cap, UIDNAInfo* info, UErrorCode* err) {
    return uidna_nameToUnicode(idna, name, nameLen, dest, cap, info, err);
}

/* sizeof(UIDNAInfo) so zig can allocate it without knowing struct layout */
size_t zphp_uidna_info_size(void) { return sizeof(UIDNAInfo); }
void zphp_uidna_info_init(UIDNAInfo* info) {
    UIDNAInfo init = UIDNA_INFO_INITIALIZER;
    *info = init;
}
