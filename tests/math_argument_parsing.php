<?php
// math functions parse their arguments as php's zpp does: numeric strings,
// the null deprecation, lossy float to int, TypeErrors
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

$values = [null, true, false, 5, -2.5, "12", " 12 ", "1.5", "1e3", "12abc", "abc", [], new stdClass, NAN];
$functions = ['abs', 'ceil', 'floor', 'round', 'sin', 'sqrt', 'exp', 'is_nan', 'is_finite', 'decbin', 'dechex', 'decoct', 'bindec', 'hexdec', 'octdec', 'deg2rad', 'rad2deg', 'asinh', 'tanh'];
foreach ($functions as $f) {
    echo "$f\n";
    foreach ($values as $v) {
        try {
            var_dump($f($v));
        } catch (Throwable $e) {
            echo "  ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}

foreach ([[7, 2], [7.5, "2"], [null, 3], ["x", 1], [1, 0], [PHP_INT_MIN, -1]] as [$a, $b]) {
    foreach (['intdiv', 'fmod', 'fdiv', 'fpow', 'hypot', 'atan2', 'log', 'pow'] as $f) {
        try {
            var_dump($f($a, $b));
        } catch (Throwable $e) {
            echo "  $f: ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}

// zero to a negative power is deprecated, for pow() and **
var_dump(pow(0, -1), 0 ** -2, 0.0 ** -1.5, pow("0", "-1"), "2" ** "3", "2.0" ** 2);
$x = 0;
$x **= -1;
var_dump($x);

// the base conversions skip what isn't a digit of the base, with a deprecation
var_dump(bindec("0b1011"), hexdec(" 0xff "), octdec("0o777"), bindec("12"), hexdec("fg"), octdec("9"));
var_dump(bindec(str_repeat("1", 64)), hexdec("ffffffffffffffff"), hexdec("7fffffffffffffff"));
var_dump(base_convert("ff", 16, 2), base_convert("-ff", 16, 10), base_convert("zz", 36, 10), base_convert(str_repeat("f", 20), 16, 10));
foreach ([[1, 37], [0, 10], [10, 1]] as [$from, $to]) {
    try {
        var_dump(base_convert("10", $from, $to));
    } catch (ValueError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
var_dump(decbin(-1), dechex(PHP_INT_MAX), decoct(PHP_INT_MIN), dechex(0));

// log's base
var_dump(log(8, 2), log(1000, 10), log(5, 1), log(M_E));
try {
    log(5, 0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    log(5, -1);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

// round's mode argument
var_dump(round(2.5, 0, RoundingMode::HalfEven), round(-2.5, 0, PHP_ROUND_HALF_DOWN), round(1234, -2), round("3.7"));
try {
    round(1.5, 0, 99);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    round(1.5, 0, new stdClass);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

// the math constants are php's literals
foreach (['M_E', 'M_LOG2E', 'M_LOG10E', 'M_LN2', 'M_LN10', 'M_PI', 'M_PI_2', 'M_PI_4', 'M_1_PI', 'M_2_PI', 'M_SQRTPI', 'M_2_SQRTPI', 'M_LNPI', 'M_EULER', 'M_SQRT2', 'M_SQRT1_2', 'M_SQRT3'] as $c) {
    var_dump(constant($c));
}
