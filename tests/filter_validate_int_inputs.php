<?php
// regression: FILTER_VALIDATE_INT follows PHP's stringify-then-filter model
// for non-string scalar inputs, and accepts the 0o octal prefix.
// previously zphp rejected every bool and float input outright.

// bool: true stringifies to "1" -> 1; false stringifies to "" -> failure
var_dump(filter_var(true, FILTER_VALIDATE_INT));    // int(1)
var_dump(filter_var(false, FILTER_VALIDATE_INT));   // false

// float: integer-valued floats pass, non-integer floats fail
var_dump(filter_var(3.0, FILTER_VALIDATE_INT));     // int(3)
var_dump(filter_var(-7.0, FILTER_VALIDATE_INT));    // int(-7)
var_dump(filter_var(0.0, FILTER_VALIDATE_INT));     // int(0)
var_dump(filter_var(3.7, FILTER_VALIDATE_INT));     // false
var_dump(filter_var(1e20, FILTER_VALIDATE_INT));    // false (out of int range)

// 0o octal prefix with FILTER_FLAG_ALLOW_OCTAL
var_dump(filter_var('0o17', FILTER_VALIDATE_INT, FILTER_FLAG_ALLOW_OCTAL));  // int(15)
var_dump(filter_var('0O20', FILTER_VALIDATE_INT, FILTER_FLAG_ALLOW_OCTAL));  // int(16)
var_dump(filter_var('017', FILTER_VALIDATE_INT, FILTER_FLAG_ALLOW_OCTAL));   // int(15)
var_dump(filter_var('0o17', FILTER_VALIDATE_INT));                          // false (flag off)

// plain cases still work
var_dump(filter_var(42, FILTER_VALIDATE_INT));
var_dump(filter_var('42', FILTER_VALIDATE_INT));
var_dump(filter_var('-99', FILTER_VALIDATE_INT));
var_dump(filter_var('0x1A', FILTER_VALIDATE_INT, FILTER_FLAG_ALLOW_HEX));
var_dump(filter_var('abc', FILTER_VALIDATE_INT));

// range options still apply after coercion
var_dump(filter_var(5.0, FILTER_VALIDATE_INT, ['options' => ['min_range' => 0, 'max_range' => 10]]));
var_dump(filter_var(50.0, FILTER_VALIDATE_INT, ['options' => ['min_range' => 0, 'max_range' => 10]]));
