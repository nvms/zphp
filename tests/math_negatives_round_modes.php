<?php
echo floor(-1.5), "\n";
echo floor(-1.0), "\n";
echo floor(-0.5), "\n";
echo floor(0.0), "\n";
echo floor(0.5), "\n";
echo floor(1.0), "\n";
echo floor(-1.1), "\n";

echo ceil(-1.5), "\n";
echo ceil(-1.0), "\n";
echo ceil(-0.5), "\n";
echo ceil(0.0), "\n";
echo ceil(0.5), "\n";
echo ceil(-0.1), "\n";

echo round(-1.5), "\n";
echo round(-2.5), "\n";
echo round(-3.5), "\n";
echo round(0.5), "\n";
echo round(1.5), "\n";
echo round(2.5), "\n";
echo round(-0.5), "\n";

echo round(-1.5, 0, PHP_ROUND_HALF_UP), "\n";
echo round(-1.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(-1.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(-1.5, 0, PHP_ROUND_HALF_ODD), "\n";
echo round(-2.5, 0, PHP_ROUND_HALF_EVEN), "\n";

echo round(1.234567, 2), "\n";
echo round(-1.234567, 2), "\n";
echo round(1.5, 0), "\n";
echo round(-1.5, 0), "\n";

echo fmod(10, 3), "\n";
echo fmod(-10, 3), "\n";
echo fmod(10, -3), "\n";
echo fmod(-10, -3), "\n";
echo fmod(10.5, 3.2), "\n";
echo fmod(-10.5, 3.2), "\n";
echo fmod(0, 3), "\n";

var_dump(fmod(10, 0));

echo intdiv(10, 3), "\n";
echo intdiv(-10, 3), "\n";
echo intdiv(10, -3), "\n";
echo intdiv(-10, -3), "\n";
echo intdiv(7, 2), "\n";
echo intdiv(-7, 2), "\n";

echo max(1, 2, 3), "\n";
echo max([1, 2, 3]), "\n";
echo max(0, -1, -2), "\n";
echo max(-1, -2, -3), "\n";

echo min(1, 2, 3), "\n";
echo min([5, 2, 8]), "\n";
echo min(-1, -2, -3), "\n";

echo max([3, 1, 4, 1, 5, 9, 2, 6]), "\n";
echo min([3, 1, 4, 1, 5, 9, 2, 6]), "\n";

echo max("apple", "banana"), "\n";
echo min("apple", "banana"), "\n";

echo max(1, 2.5, 3), "\n";
echo max(1, "abc"), "\n";
echo max([3, 2.5, 4]), "\n";

echo abs(-5), "\n";
echo abs(5), "\n";
echo abs(-5.5), "\n";
echo abs(0), "\n";
echo abs(-0.0), "\n";
echo abs(-PHP_INT_MAX), "\n";

echo abs(PHP_INT_MIN), "\n"; // overflow becomes float

echo PHP_INT_MIN, "\n";
echo PHP_INT_MIN + 0.0, "\n"; // float

var_dump((-1) ** 0.5); // NAN
echo (-1) ** 2, "\n"; // 1

echo pow(-2, 3), "\n";
var_dump(pow(-2, 0.5)); // NAN

echo sqrt(0), "\n";
echo sqrt(2), "\n";
var_dump(sqrt(-1));

echo round(0.1 + 0.2, 1), "\n";
echo 0.1 + 0.2, "\n";

echo PHP_FLOAT_DIG, "\n";

echo round(1.005, 2), "\n";
echo round(1.005, 2, PHP_ROUND_HALF_UP), "\n";

echo round(1234.5, -1), "\n";
echo round(1234.5, -2), "\n";
echo round(1234.5, -3), "\n";
echo round(-1234.5, -2), "\n";

echo round(1.234567e10, -3), "\n";

echo floor(123.4), "\n";
echo floor(-123.4), "\n";
echo ceil(123.4), "\n";
echo ceil(-123.4), "\n";

echo intval(3.7), "\n";
echo intval(-3.7), "\n";

echo (int)3.7, "\n";
echo (int)-3.7, "\n";

echo (int)0.999999999, "\n";
echo (int)-0.999999999, "\n";

echo round(2.6, 0), "\n";
echo round(2.4, 0), "\n";
