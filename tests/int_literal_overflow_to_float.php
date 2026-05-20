<?php
// regression: an integer literal too large for a 64-bit int promotes to
// float, matching PHP. previously zphp's literal parser returned i64 and
// fell back to 0 on overflow, so 9223372036854775808 (PHP_INT_MAX + 1)
// var_dumped as int(0).
var_dump(9223372036854775807);          // PHP_INT_MAX - stays int
var_dump(9223372036854775808);          // +1 - promotes to float
var_dump(99999999999999999999999999);   // far past - float
var_dump(9_223_372_036_854_775_808);    // underscores + overflow - float
var_dump(1234567890);                   // normal - int
var_dump(0x7FFFFFFFFFFFFFFF);           // hex = PHP_INT_MAX - int
var_dump(is_int(9223372036854775807));
var_dump(is_float(9223372036854775808));

// overflowing literal is usable in arithmetic as a float
$big = 9223372036854775808;
var_dump($big > PHP_INT_MAX);
var_dump($big / 2);

// the runtime ** operator already promotes; confirm it agrees with the
// literal path
var_dump(2 ** 63 === 9223372036854775808);
