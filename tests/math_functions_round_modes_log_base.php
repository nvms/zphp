<?php
error_reporting(0);

echo abs(-5), " ", abs(5), " ", abs(-3.14), " ", abs(0), "\n";
echo abs(PHP_INT_MIN), "\n";
var_dump(abs("-7"));
var_dump(abs("-3.14"));

echo ceil(1.2), " ", ceil(1.8), " ", ceil(-1.2), " ", ceil(-1.8), " ", ceil(2), "\n";
echo floor(1.2), " ", floor(1.8), " ", floor(-1.2), " ", floor(-1.8), " ", floor(2), "\n";
echo round(1.4), " ", round(1.5), " ", round(2.5), " ", round(-1.5), " ", round(-2.5), "\n";
echo round(1.55555, 2), " ", round(1.55555, 4), "\n";
echo round(1.5, 0, PHP_ROUND_HALF_UP), "\n";
echo round(1.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(1.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(0.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(1.5, 0, PHP_ROUND_HALF_ODD), "\n";
echo round(-0.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(1234.5, -1), " ", round(1234.5, -2), " ", round(1234.5, -3), "\n";

echo min(1, 2, 3), " ", max(1, 2, 3), "\n";
echo min([3, 1, 4, 1, 5]), " ", max([3, 1, 4, 1, 5]), "\n";
echo min("a", "b", "c"), " ", max("a", "b", "c"), "\n";
echo min(1.5, 2.5, 0.5), " ", max(1.5, 2.5, 0.5), "\n";
var_dump(min(PHP_INT_MAX, PHP_INT_MIN));

echo round(M_PI, 5), "\n";
echo round(M_E, 5), "\n";
echo is_nan(NAN) ? "y" : "n", "\n";
echo is_infinite(INF) ? "y" : "n", "\n";
echo is_finite(1.5) ? "y" : "n", "\n";
echo PHP_FLOAT_EPSILON > 0 ? "y" : "n", "\n";
echo PHP_FLOAT_MAX > 1 ? "y" : "n", "\n";

echo sqrt(16), " ", round(sqrt(2), 5), "\n";
echo pow(2, 10), " ", pow(2, 0.5), "\n";
echo exp(0), " ", round(exp(1), 5), "\n";
echo log(1), " ", round(log(M_E), 5), "\n";
echo log(100, 10), "\n";
echo log10(1000), " ", log(8, 2), "\n";

echo round(sin(0), 5), " ", round(sin(M_PI / 2), 5), "\n";
echo round(cos(0), 5), " ", round(cos(M_PI), 5), "\n";
echo round(tan(0), 5), "\n";
echo round(atan(1), 5), "\n";
echo round(atan2(1, 1), 5), "\n";
echo round(asin(1), 5), "\n";
echo round(acos(0), 5), "\n";

echo round(deg2rad(180), 5), "\n";
echo round(rad2deg(M_PI), 5), "\n";

echo fmod(10, 3), " ", fmod(10.5, 2.5), "\n";
echo intdiv(10, 3), " ", intdiv(-10, 3), " ", intdiv(10, -3), "\n";
echo fdiv(10, 3), "\n";
echo fdiv(1, 0), "\n";
echo fdiv(-1, 0), "\n";
echo is_nan(fdiv(0, 0)) ? "nan\n" : "x\n";

echo bindec("1010"), " ", decbin(10), "\n";
echo hexdec("ff"), " ", dechex(255), "\n";
echo octdec("777"), " ", decoct(511), "\n";

echo base_convert("ff", 16, 10), "\n";
echo base_convert("1010", 2, 10), "\n";
echo base_convert("100", 10, 16), "\n";
echo base_convert("z", 36, 10), "\n";

echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_INT_SIZE, "\n";

echo intval(3.99), " ", intval(-3.99), "\n";
echo intval("0x10", 16), "\n";
echo intval("0b1010", 2), "\n";


$nums = [3, 1, 4, 1, 5, 9, 2, 6];
echo array_sum($nums), "\n";
echo array_product($nums), "\n";

echo round(1.005, 2), "\n";
echo round(1.025, 2), "\n";

echo hypot(3, 4), "\n";
echo intval(PHP_INT_MAX), "\n";
