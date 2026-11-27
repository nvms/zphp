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
#include <string.h>
#include <stdlib.h>
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
#include <unicode/ucal.h>
#include <unicode/ubrk.h>
#include <unicode/utext.h>
#include <unicode/ulistformatter.h>

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
/* the "uts46" instance is UTS #46 mapping plus NFC, which the whatwg url
 * host parser uses for its idna processing */
const UNormalizer2* zphp_unorm2_getInstance(const char* packageName, const char* name, int32_t mode, UErrorCode* err) {
    return unorm2_getInstance(packageName, name, (UNormalization2Mode) mode, err);
}
int32_t zphp_unorm2_normalize(const UNormalizer2* n,const UChar* src, int32_t srcLen, UChar* dest, int32_t cap, UErrorCode* err) {
    return unorm2_normalize(n, src, srcLen, dest, cap, err);
}
UBool zphp_unorm2_isNormalized(const UNormalizer2* n, const UChar* src, int32_t srcLen, UErrorCode* err) {
    return unorm2_isNormalized(n, src, srcLen, err);
}

/* ----- Locale ----- */

const char* zphp_uloc_getDefault(void) { return uloc_getDefault(); }
UBool zphp_uloc_isRightToLeft(const char* locale) { return uloc_isRightToLeft(locale); }

UListFormatter* zphp_ulistfmt_open(const char* locale, int32_t type, int32_t width, UErrorCode* err) {
    return ulistfmt_openForType(locale, (UListFormatterType)type, (UListFormatterWidth)width, err);
}
void zphp_ulistfmt_close(UListFormatter* f) { ulistfmt_close(f); }
int32_t zphp_ulistfmt_format(const UListFormatter* f, const UChar* const strings[], const int32_t* lengths,
                             int32_t count, UChar* result, int32_t cap, UErrorCode* err) {
    return ulistfmt_format(f, strings, lengths, count, result, cap, err);
}
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
UNumberFormat* zphp_unum_clone(const UNumberFormat* f, UErrorCode* err) { return unum_clone(f, err); }
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
UTransliterator* zphp_utrans_clone(const UTransliterator* t, UErrorCode* err) { return utrans_clone(t, err); }
void zphp_utrans_transUChars(const UTransliterator* t, UChar* text, int32_t* textLen, int32_t textCap, int32_t start, int32_t* limit, UErrorCode* err) {
    utrans_transUChars(t, text, textLen, textCap, start, limit, err);
}

/* ----- IntlDateFormatter ----- */

UDateFormat* zphp_udat_open(UDateFormatStyle timeStyle, UDateFormatStyle dateStyle, const char* locale, const UChar* tzID, int32_t tzIDLen, const UChar* pattern, int32_t patternLen, UErrorCode* err) {
    return udat_open(timeStyle, dateStyle, locale, tzID, tzIDLen, pattern, patternLen, err);
}
void zphp_udat_close(UDateFormat* f) { udat_close(f); }
UDateFormat* zphp_udat_clone(const UDateFormat* f, UErrorCode* err) { return udat_clone(f, err); }
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

/* ----- IntlCalendar ----- */

UCalendar* zphp_ucal_open(const UChar* zoneID, int32_t len, const char* locale, UCalendarType type, UErrorCode* err) {
    return ucal_open(zoneID, len, locale, type, err);
}
void zphp_ucal_close(UCalendar* cal) { ucal_close(cal); }
int32_t zphp_ucal_get(const UCalendar* cal, UCalendarDateFields field, UErrorCode* err) {
    return ucal_get(cal, field, err);
}
void zphp_ucal_set(UCalendar* cal, UCalendarDateFields field, int32_t value) {
    ucal_set(cal, field, value);
}
void zphp_ucal_add(UCalendar* cal, UCalendarDateFields field, int32_t amount, UErrorCode* err) {
    ucal_add(cal, field, amount, err);
}
void zphp_ucal_roll(UCalendar* cal, UCalendarDateFields field, int32_t amount, UErrorCode* err) {
    ucal_roll(cal, field, amount, err);
}
double zphp_ucal_getMillis(const UCalendar* cal, UErrorCode* err) {
    return ucal_getMillis(cal, err);
}
void zphp_ucal_setMillis(UCalendar* cal, double dateTime, UErrorCode* err) {
    ucal_setMillis(cal, dateTime, err);
}
void zphp_ucal_setDate(UCalendar* cal, int32_t year, int32_t month, int32_t date, UErrorCode* err) {
    ucal_setDate(cal, year, month, date, err);
}
void zphp_ucal_setDateTime(UCalendar* cal, int32_t y, int32_t mo, int32_t d, int32_t h, int32_t mi, int32_t s, UErrorCode* err) {
    ucal_setDateTime(cal, y, mo, d, h, mi, s, err);
}
UBool zphp_ucal_inDaylightTime(const UCalendar* cal, UErrorCode* err) {
    return ucal_inDaylightTime(cal, err);
}
UBool zphp_ucal_isSet(const UCalendar* cal, UCalendarDateFields field) {
    return ucal_isSet(cal, field);
}
void zphp_ucal_clear(UCalendar* cal) { ucal_clear(cal); }
void zphp_ucal_clearField(UCalendar* cal, UCalendarDateFields field) { ucal_clearField(cal, field); }
int32_t zphp_ucal_getLimit(const UCalendar* cal, UCalendarDateFields field, UCalendarLimitType type, UErrorCode* err) {
    return ucal_getLimit(cal, field, type, err);
}
UBool zphp_ucal_equivalentTo(const UCalendar* a, const UCalendar* b) {
    return ucal_equivalentTo(a, b);
}
int32_t zphp_ucal_getType(const UCalendar* cal, char* buf, int32_t buf_len, UErrorCode* err) {
    const char* type = ucal_getType(cal, err);
    if (!type) return -1;
    size_t n = strlen(type);
    if ((int32_t)n >= buf_len) return -1;
    memcpy(buf, type, n);
    buf[n] = 0;
    return (int32_t)n;
}
int32_t zphp_ucal_getLocaleByType(const UCalendar* cal, ULocDataLocaleType type, char* buf, int32_t buf_len, UErrorCode* err) {
    const char* loc = ucal_getLocaleByType(cal, type, err);
    if (!loc) return -1;
    size_t n = strlen(loc);
    if ((int32_t)n >= buf_len) return -1;
    memcpy(buf, loc, n);
    buf[n] = 0;
    return (int32_t)n;
}
int32_t zphp_ucal_getTimeZoneID(const UCalendar* cal, UChar* buf, int32_t cap, UErrorCode* err) {
    return ucal_getTimeZoneID(cal, buf, cap, err);
}
void zphp_ucal_setTimeZone(UCalendar* cal, const UChar* zoneID, int32_t len, UErrorCode* err) {
    ucal_setTimeZone(cal, zoneID, len, err);
}
int32_t zphp_ucal_getFirstDayOfWeek(const UCalendar* cal, UErrorCode* err) {
    return ucal_getAttribute(cal, UCAL_FIRST_DAY_OF_WEEK);
}
void zphp_ucal_setFirstDayOfWeek(UCalendar* cal, int32_t day) {
    ucal_setAttribute(cal, UCAL_FIRST_DAY_OF_WEEK, day);
}
UBool zphp_ucal_isWeekend(const UCalendar* cal, double date, UErrorCode* err) {
    return ucal_isWeekend(cal, date, err);
}
UCalendar* zphp_ucal_clone(const UCalendar* cal, UErrorCode* err) {
    return ucal_clone(cal, err);
}
UBool zphp_ucal_getLenient(const UCalendar* cal) {
    return ucal_getAttribute(cal, UCAL_LENIENT);
}
void zphp_ucal_setLenient(UCalendar* cal, int32_t lenient) {
    ucal_setAttribute(cal, UCAL_LENIENT, lenient);
}

/* ----- IntlBreakIterator -----
 *
 * PHP's IntlBreakIterator reports UTF-8 byte offsets. ICU's natural input is
 * UTF-16 (UChar) but utext_openUTF8 lets it work directly on UTF-8 with the
 * boundary positions reported as byte offsets into the original buffer.
 *
 * We allocate one UText alongside each UBreakIterator and own its lifetime
 */

typedef struct {
    UBreakIterator* bi;
    UText* ut;
    char* text_copy;
    int32_t text_len;
} zphp_brk;

zphp_brk* zphp_ubrk_open(UBreakIteratorType type, const char* locale, UErrorCode* err) {
    zphp_brk* w = (zphp_brk*)calloc(1, sizeof(zphp_brk));
    if (!w) return NULL;
    w->bi = ubrk_open(type, locale, NULL, 0, err);
    if (U_FAILURE(*err)) { free(w); return NULL; }
    return w;
}

void zphp_ubrk_close(zphp_brk* w) {
    if (!w) return;
    if (w->bi) ubrk_close(w->bi);
    if (w->ut) utext_close(w->ut);
    if (w->text_copy) free(w->text_copy);
    free(w);
}

void zphp_ubrk_setText(zphp_brk* w, const char* text, int32_t len, UErrorCode* err) {
    if (w->ut) { utext_close(w->ut); w->ut = NULL; }
    if (w->text_copy) { free(w->text_copy); w->text_copy = NULL; }
    if (len > 0) {
        w->text_copy = (char*)malloc((size_t)len + 1);
        if (!w->text_copy) { *err = U_MEMORY_ALLOCATION_ERROR; return; }
        memcpy(w->text_copy, text, (size_t)len);
        w->text_copy[len] = 0;
        w->text_len = len;
    } else {
        w->text_copy = (char*)malloc(1);
        w->text_copy[0] = 0;
        w->text_len = 0;
    }
    w->ut = utext_openUTF8(NULL, w->text_copy, w->text_len, err);
    if (U_FAILURE(*err)) return;
    ubrk_setUText(w->bi, w->ut, err);
}

/* ubrk_clone shares the source's UText, so the copy gets its own text buffer
 * and is moved back to the source's boundary */
zphp_brk* zphp_ubrk_clone(const zphp_brk* src, UErrorCode* err) {
    zphp_brk* w = (zphp_brk*)calloc(1, sizeof(zphp_brk));
    if (!w) { *err = U_MEMORY_ALLOCATION_ERROR; return NULL; }
    w->bi = ubrk_clone(src->bi, err);
    if (U_FAILURE(*err)) { free(w); return NULL; }
    if (!src->text_copy) return w;
    int32_t pos = ubrk_current(src->bi);
    zphp_ubrk_setText(w, src->text_copy, src->text_len, err);
    if (U_FAILURE(*err)) { zphp_ubrk_close(w); return NULL; }
    if (pos >= 0) ubrk_isBoundary(w->bi, pos);
    return w;
}

const char* zphp_ubrk_getText(zphp_brk* w, int32_t* len) {
    *len = w->text_len;
    return w->text_copy ? w->text_copy : "";
}

int32_t zphp_ubrk_first(zphp_brk* w) { return ubrk_first(w->bi); }
int32_t zphp_ubrk_last(zphp_brk* w) { return ubrk_last(w->bi); }
int32_t zphp_ubrk_next(zphp_brk* w) { return ubrk_next(w->bi); }
int32_t zphp_ubrk_previous(zphp_brk* w) { return ubrk_previous(w->bi); }
int32_t zphp_ubrk_current(zphp_brk* w) { return ubrk_current(w->bi); }
int32_t zphp_ubrk_following(zphp_brk* w, int32_t off) { return ubrk_following(w->bi, off); }
int32_t zphp_ubrk_preceding(zphp_brk* w, int32_t off) { return ubrk_preceding(w->bi, off); }
UBool zphp_ubrk_isBoundary(zphp_brk* w, int32_t off) { return ubrk_isBoundary(w->bi, off); }
int32_t zphp_ubrk_getRuleStatus(zphp_brk* w) { return ubrk_getRuleStatus(w->bi); }
int32_t zphp_ubrk_getLocaleByType(zphp_brk* w, ULocDataLocaleType ltype, char* buf, int32_t buf_len, UErrorCode* err) {
    const char* loc = ubrk_getLocaleByType(w->bi, ltype, err);
    if (!loc) return -1;
    size_t n = strlen(loc);
    if ((int32_t)n >= buf_len) return -1;
    memcpy(buf, loc, n);
    buf[n] = 0;
    return (int32_t)n;
}

/* ----- IntlChar (unicode/uchar.h) ----- */

#include <unicode/uchar.h>

struct zphp_intlchar_constant {
    const char* name;
    int kind;
    int64_t int_value;
    double float_value;
    const char* string_value;
};

#include "intlchar_constants_generated.h"

const struct zphp_intlchar_constant* zphp_intlchar_constant_at(size_t i) {
    if (i >= sizeof(zphp_intlchar_constants) / sizeof(zphp_intlchar_constants[0])) return NULL;
    return &zphp_intlchar_constants[i];
}

UBool zphp_u_hasBinaryProperty(UChar32 c, int32_t which) { return u_hasBinaryProperty(c, (UProperty)which); }
int32_t zphp_u_getIntPropertyValue(UChar32 c, int32_t which) { return u_getIntPropertyValue(c, (UProperty)which); }
int32_t zphp_u_getIntPropertyMinValue(int32_t which) { return u_getIntPropertyMinValue((UProperty)which); }
int32_t zphp_u_getIntPropertyMaxValue(int32_t which) { return u_getIntPropertyMaxValue((UProperty)which); }
double zphp_u_getNumericValue(UChar32 c) { return u_getNumericValue(c); }
int32_t zphp_ublock_getCode(UChar32 c) { return (int32_t)ublock_getCode(c); }

typedef UBool (*zphp_char_types_fn)(void* context, int32_t start, int32_t limit, int32_t type);
struct zphp_char_types_ctx { zphp_char_types_fn fn; void* context; };
static UBool zphp_char_types_trampoline(const void* context, UChar32 start, UChar32 limit, UCharCategory type) {
    const struct zphp_char_types_ctx* c = (const struct zphp_char_types_ctx*)context;
    return c->fn(c->context, start, limit, (int32_t)type);
}
void zphp_u_enumCharTypes(zphp_char_types_fn fn, void* context) {
    struct zphp_char_types_ctx c = { fn, context };
    u_enumCharTypes(zphp_char_types_trampoline, &c);
}

int32_t zphp_u_charName(UChar32 code, int32_t choice, char* buffer, int32_t cap, UErrorCode* err) {
    return u_charName(code, (UCharNameChoice)choice, buffer, cap, err);
}
UChar32 zphp_u_charFromName(int32_t choice, const char* name, UErrorCode* err) {
    return u_charFromName((UCharNameChoice)choice, name, err);
}

typedef UBool (*zphp_char_names_fn)(void* context, int32_t code, int32_t choice, const char* name, int32_t length);
struct zphp_char_names_ctx { zphp_char_names_fn fn; void* context; };
static UBool zphp_char_names_trampoline(void* context, UChar32 code, UCharNameChoice choice, const char* name, int32_t length) {
    struct zphp_char_names_ctx* c = (struct zphp_char_names_ctx*)context;
    return c->fn(c->context, code, (int32_t)choice, name, length);
}
void zphp_u_enumCharNames(UChar32 start, UChar32 limit, zphp_char_names_fn fn, void* context, int32_t choice, UErrorCode* err) {
    struct zphp_char_names_ctx c = { fn, context };
    u_enumCharNames(start, limit, zphp_char_names_trampoline, &c, (UCharNameChoice)choice, err);
}

const char* zphp_u_getPropertyName(int32_t property, int32_t choice) { return u_getPropertyName((UProperty)property, (UPropertyNameChoice)choice); }
int32_t zphp_u_getPropertyEnum(const char* alias) { return (int32_t)u_getPropertyEnum(alias); }
const char* zphp_u_getPropertyValueName(int32_t property, int32_t value, int32_t choice) {
    return u_getPropertyValueName((UProperty)property, value, (UPropertyNameChoice)choice);
}
int32_t zphp_u_getPropertyValueEnum(int32_t property, const char* alias) { return u_getPropertyValueEnum((UProperty)property, alias); }
UChar32 zphp_u_foldCase(UChar32 c, uint32_t options) { return u_foldCase(c, options); }
int32_t zphp_u_digit(UChar32 c, int8_t radix) { return u_digit(c, radix); }
UChar32 zphp_u_forDigit(int32_t digit, int8_t radix) { return u_forDigit(digit, radix); }
void zphp_u_charAge(UChar32 c, uint8_t* version) { u_charAge(c, version); }
void zphp_u_getUnicodeVersion(uint8_t* version) { u_getUnicodeVersion(version); }
int32_t zphp_u_getFC_NFKC_Closure(UChar32 c, UChar* dest, int32_t cap, UErrorCode* err) { return u_getFC_NFKC_Closure(c, dest, cap, err); }

#define ZPHP_UCHAR_BOOL(name) UBool zphp_u_##name(UChar32 c) { return u_##name(c); }
ZPHP_UCHAR_BOOL(isUAlphabetic)
ZPHP_UCHAR_BOOL(isULowercase)
ZPHP_UCHAR_BOOL(isUUppercase)
ZPHP_UCHAR_BOOL(isUWhiteSpace)
ZPHP_UCHAR_BOOL(islower)
ZPHP_UCHAR_BOOL(isupper)
ZPHP_UCHAR_BOOL(istitle)
ZPHP_UCHAR_BOOL(isdigit)
ZPHP_UCHAR_BOOL(isalpha)
ZPHP_UCHAR_BOOL(isalnum)
ZPHP_UCHAR_BOOL(isxdigit)
ZPHP_UCHAR_BOOL(ispunct)
ZPHP_UCHAR_BOOL(isgraph)
ZPHP_UCHAR_BOOL(isblank)
ZPHP_UCHAR_BOOL(isdefined)
ZPHP_UCHAR_BOOL(isspace)
ZPHP_UCHAR_BOOL(isJavaSpaceChar)
ZPHP_UCHAR_BOOL(isWhitespace)
ZPHP_UCHAR_BOOL(iscntrl)
ZPHP_UCHAR_BOOL(isISOControl)
ZPHP_UCHAR_BOOL(isprint)
ZPHP_UCHAR_BOOL(isbase)
ZPHP_UCHAR_BOOL(isMirrored)
ZPHP_UCHAR_BOOL(isIDStart)
ZPHP_UCHAR_BOOL(isIDPart)
ZPHP_UCHAR_BOOL(isIDIgnorable)
ZPHP_UCHAR_BOOL(isJavaIDStart)
ZPHP_UCHAR_BOOL(isJavaIDPart)
#undef ZPHP_UCHAR_BOOL

int32_t zphp_u_charDirection(UChar32 c) { return (int32_t)u_charDirection(c); }
int32_t zphp_u_charType(UChar32 c) { return (int32_t)u_charType(c); }
int32_t zphp_u_getCombiningClass(UChar32 c) { return (int32_t)u_getCombiningClass(c); }
int32_t zphp_u_charDigitValue(UChar32 c) { return u_charDigitValue(c); }
UChar32 zphp_u_charMirror(UChar32 c) { return u_charMirror(c); }
UChar32 zphp_u_tolower(UChar32 c) { return u_tolower(c); }
UChar32 zphp_u_toupper(UChar32 c) { return u_toupper(c); }
UChar32 zphp_u_totitle(UChar32 c) { return u_totitle(c); }
UChar32 zphp_u_getBidiPairedBracket(UChar32 c) { return u_getBidiPairedBracket(c); }
