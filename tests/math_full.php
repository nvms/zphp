<?php
echo abs(-5), "\n";
echo abs(5), "\n";
echo abs(-5.5), "\n";
echo abs(0), "\n";
echo abs(-0.0), "\n";
echo abs(PHP_INT_MIN + 1), "\n";

echo floor(1.5), "\n";
echo floor(-1.5), "\n";
echo floor(0.0), "\n";
echo floor(2.0), "\n";

echo ceil(1.5), "\n";
echo ceil(-1.5), "\n";
echo ceil(0.0), "\n";
echo ceil(2.0), "\n";

echo round(1.5), "\n";
echo round(2.5), "\n";
echo round(-1.5), "\n";
echo round(-2.5), "\n";
echo round(1.234567, 2), "\n";
echo round(1.234567, 4), "\n";
echo round(1234.5, -1), "\n";
echo round(1234.5, -2), "\n";
echo round(0.5), "\n"; // 1
echo round(-0.5), "\n"; // -1

echo round(2.5, 0, PHP_ROUND_HALF_UP), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(3.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_ODD), "\n";
echo round(3.5, 0, PHP_ROUND_HALF_ODD), "\n";

echo sqrt(16), "\n";
echo sqrt(2), "\n";
echo sqrt(0), "\n";
var_dump(sqrt(-1)); // NAN

echo pow(2, 10), "\n";
echo pow(2, 0), "\n";
echo pow(2, -1), "\n";
echo pow(0, 0), "\n";
echo pow(2.5, 3), "\n";
echo 2 ** 10, "\n";

echo log(M_E), "\n";       // 1
echo log(1), "\n";          // 0
echo log(100, 10), "\n";   // 2
echo log(8, 2), "\n";       // 3
echo log10(100), "\n";
echo log(8, 2), "\n";
echo log1p(0), "\n";

echo exp(0), "\n";
echo exp(1), "\n";
printf("%.6f\n", exp(2));

echo round(M_PI, 5), "\n";
echo round(pi(), 5), "\n";
echo round(M_E, 5), "\n";
echo M_PI_2, "\n"; // pi/2
echo round(M_LN2, 5), "\n";
echo round(M_LN10, 5), "\n";

echo round(sin(0), 6), "\n";
echo round(sin(M_PI / 2), 6), "\n";
echo round(cos(0), 6), "\n";
echo round(cos(M_PI), 6), "\n";
echo round(tan(0), 6), "\n";
echo round(tan(M_PI / 4), 6), "\n";

echo round(asin(1), 6), "\n";  // pi/2
echo round(acos(0), 6), "\n";  // pi/2
echo round(atan(1), 6), "\n";  // pi/4
echo round(atan2(1, 1), 6), "\n"; // pi/4
echo round(atan2(0, -1), 6), "\n"; // pi

echo round(deg2rad(180), 6), "\n"; // pi
echo round(rad2deg(M_PI), 6), "\n"; // 180

echo hypot(3, 4), "\n";
echo hypot(0, 0), "\n";
printf("%.6f\n", hypot(1, 1));

echo round(sinh(0), 6), "\n";
echo round(cosh(0), 6), "\n";
echo round(tanh(0), 6), "\n";

echo max(1, 2, 3), "\n";
echo max([1, 2, 3]), "\n";
echo max(0, -1, 5), "\n";
echo max(1.5, 2, 3), "\n";
echo min(1, 2, 3), "\n";
echo min([5, 2, 8]), "\n";
echo min(0.5, 1, -1), "\n";

echo max("apple", "banana"), "\n";
echo min("apple", "banana"), "\n";

echo fmod(10, 3), "\n";
echo fmod(10.5, 3), "\n";
echo fmod(-10, 3), "\n";
echo fmod(10, -3), "\n";
echo fmod(0, 3), "\n";

echo intdiv(10, 3), "\n";
echo intdiv(-10, 3), "\n";

echo dechex(255), "\n";
echo decoct(8), "\n";
echo decbin(10), "\n";
echo hexdec("ff"), "\n";
echo octdec("17"), "\n";
echo bindec("1010"), "\n";

echo base_convert("ff", 16, 2), "\n";
echo base_convert("100", 10, 2), "\n";
echo base_convert("100", 2, 10), "\n";

// undefined constant access (architectural - PHP errors, zphp returns null/false)
echo number_format(1234567.891, 2), "\n";

echo round(M_SQRT2, 6), "\n";
echo round(M_SQRT1_2, 6), "\n";

// edge cases
echo round(0.1 + 0.2, 1), "\n";
echo round(1e15 + 0.5, 0), "\n";

var_dump(is_nan(NAN));
var_dump(is_nan(1.0));
var_dump(is_infinite(INF));
var_dump(is_infinite(-INF));
var_dump(is_infinite(1.0));
var_dump(is_finite(1.0));
var_dump(is_finite(INF));
var_dump(is_finite(NAN));
