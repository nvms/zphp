<?php
// covers: the standard PCRE_VERSION / _MAJOR / _MINOR constants must be defined.
// vendor polyfills (e.g. symfony/polyfill-intl-grapheme) reference PCRE_VERSION
// at load time and throw "Undefined constant" otherwise. zphp and php link the
// same system libpcre2, so the values match; only the version-STABLE shape is
// asserted (the exact patch string varies by build).

var_dump(defined('PCRE_VERSION'));
var_dump(is_string(PCRE_VERSION) && strlen(PCRE_VERSION) > 0);
// libpcre2 is always major version 10
var_dump(PCRE_VERSION_MAJOR);
var_dump(defined('PCRE_VERSION_MINOR'));
// usable in the float comparison vendor code performs (e.g. the grapheme
// polyfill gates on `(float) PCRE_VERSION`)
var_dump(is_int(PCRE_VERSION_MAJOR) && PCRE_VERSION_MAJOR >= 10);
