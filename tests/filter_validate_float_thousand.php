<?php
// regression: FILTER_VALIDATE_FLOAT with FILTER_FLAG_ALLOW_THOUSAND accepts a
// number with ',' thousands separators, but only when they form valid
// \d{1,3}(,\d{3})* grouping. zphp previously ignored the flag entirely and
// rejected any comma-containing string.
foreach ([
    '1,234',
    '1,234.5',
    '12,345',
    '1,234,567',
    '22,222.22',
    '999',
    '.5',
    '1,23',        // bad: group of 2
    '1,2,3',       // bad
    '1234,567',    // bad: first group of 4
    '12,34,567',   // bad
    '1,',          // bad
    '1,234,',      // bad
] as $t) {
    $r = filter_var($t, FILTER_VALIDATE_FLOAT, FILTER_FLAG_ALLOW_THOUSAND);
    echo str_pad("'$t'", 14), ' => ', var_export($r, true), "\n";
}

// without the flag, a comma always fails
var_dump(filter_var('1,234.5', FILTER_VALIDATE_FLOAT));

// plain floats are unaffected by the flag
var_dump(filter_var('3.14159', FILTER_VALIDATE_FLOAT, FILTER_FLAG_ALLOW_THOUSAND));
var_dump(filter_var('-42', FILTER_VALIDATE_FLOAT, FILTER_FLAG_ALLOW_THOUSAND));
var_dump(filter_var('1e3', FILTER_VALIDATE_FLOAT, FILTER_FLAG_ALLOW_THOUSAND));
