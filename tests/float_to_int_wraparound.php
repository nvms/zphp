<?php
// regression: casting an out-of-range float to int wraps modulo 2^64 the way
// PHP's zend_dval_to_lval does, instead of saturating at PHP_INT_MIN.
// PHP emits an E_WARNING on the lossy cast that zphp does not mirror (same
// posture as the NaN/Inf cast warning); silence it so this test checks the
// converted value, which is the behavior being verified.
error_reporting(0);
echo (int)9.5e18, "\n";        // -8946744073709551616
echo (int)1e25, "\n";          // 1590897979265384448
echo (int)-1e20, "\n";         // -7766279631452241920
echo intval(1e30), "\n";       // 5076964154930102272
echo (int)(PHP_INT_MAX + 1), "\n";

// in-range floats still truncate toward zero
echo (int)3.9, "\n";           // 3
echo (int)-3.9, "\n";          // -3
echo (int)0.0, "\n";           // 0
echo (int)-0.5, "\n";          // 0

// NaN and Inf cast to 0
echo (int)NAN, "\n";           // 0
echo (int)INF, "\n";           // 0
echo (int)-INF, "\n";          // 0

// settype to integer uses the same conversion
$f = 9.5e18;
settype($f, 'integer');
echo $f, "\n";                 // -8946744073709551616

// a huge float used as an array key truncates without panicking
$big = 1e25;
$arr = [];
$arr[$big] = 'v';
echo array_key_first($arr), "\n";

// arithmetic that overflows int still promotes to float (not affected)
$x = PHP_INT_MAX + 1;
echo gettype($x), "\n";        // double
