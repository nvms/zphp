// MessageFormat shim: ICU's C API for MessageFormat is variadic which can't
// be cleanly called from zig. The C++ MessageFormat class takes Formattable
// arrays, which we can pass through a stable C ABI here.

#include <unicode/msgfmt.h>
#include <unicode/unistr.h>
#include <unicode/locid.h>
#include <unicode/fmtable.h>
#include <unicode/parseerr.h>
#include <stdint.h>
#include <string.h>

using icu::Formattable;
using icu::Locale;
using icu::MessageFormat;
using icu::UnicodeString;

// keep ABI in lockstep with zphp_arg_entry in intl.zig
struct zphp_arg_entry {
    int32_t type;   // 0=int64, 1=double, 2=utf16-string
    int64_t ival;
    double dval;
    const UChar* sval;
    int32_t slen;
    const UChar* name;
    int32_t name_len;
};

static const int ARG_INT = 0;
static const int ARG_DOUBLE = 1;
static const int ARG_STRING = 2;

extern "C" int32_t zphp_msgfmt_format(
    const char* locale,
    const UChar* pattern, int32_t pattern_len,
    const struct zphp_arg_entry* args, int32_t arg_count,
    UChar* result, int32_t result_cap,
    UErrorCode* err)
{
    UnicodeString pat(pattern, pattern_len);
    Locale loc = Locale::createFromName(locale);
    MessageFormat fmt(pat, loc, *err);
    if (U_FAILURE(*err)) return -1;

    UnicodeString* names = arg_count > 0 ? new UnicodeString[arg_count] : nullptr;
    Formattable* vals = arg_count > 0 ? new Formattable[arg_count] : nullptr;

    for (int32_t i = 0; i < arg_count; i++) {
        names[i] = UnicodeString(args[i].name, args[i].name_len);
        switch (args[i].type) {
            case ARG_INT:    vals[i] = Formattable((int64_t)args[i].ival); break;
            case ARG_DOUBLE: vals[i] = Formattable(args[i].dval); break;
            case ARG_STRING: vals[i] = Formattable(UnicodeString(args[i].sval, args[i].slen)); break;
            default:         vals[i] = Formattable((int64_t)0); break;
        }
    }

    UnicodeString out;
    fmt.format(names, vals, arg_count, out, *err);

    delete[] names;
    delete[] vals;

    if (U_FAILURE(*err)) return -1;
    return out.extract(result, result_cap, *err);
}

// non-named (positional) form: pattern uses {0}, {1}, ... and args are passed
// in order. used when the caller hasn't given names
extern "C" int32_t zphp_msgfmt_format_positional(
    const char* locale,
    const UChar* pattern, int32_t pattern_len,
    const struct zphp_arg_entry* args, int32_t arg_count,
    UChar* result, int32_t result_cap,
    UErrorCode* err)
{
    UnicodeString pat(pattern, pattern_len);
    Locale loc = Locale::createFromName(locale);
    MessageFormat fmt(pat, loc, *err);
    if (U_FAILURE(*err)) return -1;

    Formattable* vals = arg_count > 0 ? new Formattable[arg_count] : nullptr;
    for (int32_t i = 0; i < arg_count; i++) {
        switch (args[i].type) {
            case ARG_INT:    vals[i] = Formattable((int64_t)args[i].ival); break;
            case ARG_DOUBLE: vals[i] = Formattable(args[i].dval); break;
            case ARG_STRING: vals[i] = Formattable(UnicodeString(args[i].sval, args[i].slen)); break;
            default:         vals[i] = Formattable((int64_t)0); break;
        }
    }

    UnicodeString out;
    icu::FieldPosition pos(icu::FieldPosition::DONT_CARE);
    fmt.format(vals, arg_count, out, pos, *err);

    delete[] vals;

    if (U_FAILURE(*err)) return -1;
    return out.extract(result, result_cap, *err);
}
