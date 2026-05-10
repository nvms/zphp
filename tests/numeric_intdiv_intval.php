<?php
echo number_format(1234567.891), "\n"; // 1,234,568
echo number_format(1234567.891, 2), "\n"; // 1,234,567.89
echo number_format(1234567.891, 2, ".", ","), "\n";
echo number_format(1234567.891, 2, ",", "."), "\n";
echo number_format(1234567.891, 2, ".", ""), "\n";
echo number_format(1234567.891, 2, ".", " "), "\n";
echo number_format(0.5), "\n"; // 1 (banker's round? no, half-away from zero in PHP)
echo number_format(1.5), "\n"; // 2
echo number_format(2.5), "\n"; // 3
echo number_format(-0.5), "\n"; // -1
echo number_format(-1.5), "\n"; // -2
echo number_format(0.123, 2), "\n"; // 0.12
echo number_format(0.125, 2), "\n"; // 0.13
echo number_format(0.135, 2), "\n"; // 0.14
echo number_format(99.999, 2), "\n"; // 100.00
echo number_format(-1234.5, 0), "\n";
echo number_format(0), "\n";
echo number_format(0, 2), "\n";
echo number_format(-0.0, 1), "\n";

echo number_format(1e9), "\n";
echo number_format(1.234e-3, 5), "\n";

echo number_format(123, 2), "\n";
echo number_format(1234, 2), "\n";
echo number_format(12345, 2), "\n";
echo number_format(123456, 2), "\n";

echo number_format(1234567.89, 2, ".", "_"), "\n";
echo number_format(1234567, 2, ".", "'"), "\n";

echo number_format(1234.5678, 4), "\n";
echo number_format(1234.5678, 6), "\n";

var_dump(intval("42")); // 42
var_dump(intval("42abc")); // 42
var_dump(intval("abc")); // 0
var_dump(intval("0x1f")); // 0 (default base 10 doesn't handle 0x)
var_dump(intval("0x1f", 16)); // 31
var_dump(intval("1f", 16)); // 31
var_dump(intval("11", 2)); // 3
var_dump(intval("11", 8)); // 9
var_dump(intval("11", 10)); // 11
var_dump(intval("0x1f", 0)); // 31
var_dump(intval("0b11", 0)); // 3
var_dump(intval("011", 0)); // 9
var_dump(intval("11", 0)); // 11
var_dump(intval(42.7)); // 42
var_dump(intval(-42.7)); // -42
var_dump(intval(true)); // 1
var_dump(intval(false)); // 0
var_dump(intval(null)); // 0
var_dump(intval("  -42")); // -42 (leading ws ok)
var_dump(intval("+42")); // 42
var_dump(intval("1e3")); // 1000 in PHP 7+
var_dump(intval("1.5e3")); // 1500 in PHP 7+

var_dump(floatval("1.5"));
var_dump(floatval("1.5abc"));
var_dump(floatval("abc"));
var_dump(floatval("1e3"));
var_dump(floatval("1.5e3"));
var_dump(floatval("  1.5"));
var_dump(floatval("+1.5"));
var_dump(floatval("-1.5e-2"));
var_dump(floatval(""));
var_dump(floatval("."));
var_dump(floatval("1.5.5"));
var_dump((float)"1.5.5");
var_dump((float)"123abc.456");

echo intdiv(10, 3), "\n"; // 3
echo intdiv(-10, 3), "\n"; // -3 (truncated toward 0)
echo intdiv(10, -3), "\n"; // -3
echo intdiv(-10, -3), "\n"; // 3
echo intdiv(7, 2), "\n"; // 3
echo intdiv(0, 5), "\n"; // 0
// intdiv(PHP_INT_MIN, -1) throws (covered by ArithmeticError catch below)

try { intdiv(10, 0); echo "no\n"; } catch (\DivisionByZeroError $e) { echo "dbz\n"; }

try { intdiv(PHP_INT_MIN, -1); echo "no\n"; } catch (\ArithmeticError $e) { echo "arith\n"; }

echo abs(-5), "\n";
echo abs(-5.5), "\n";
echo abs(-PHP_INT_MAX), "\n";
echo round(1.5), "\n"; // 2
echo round(2.5), "\n"; // 3 (half away from zero default)
echo round(2.5, 0, PHP_ROUND_HALF_EVEN), "\n"; // 2 (banker's)
echo round(3.5, 0, PHP_ROUND_HALF_EVEN), "\n"; // 4
echo round(2.5, 0, PHP_ROUND_HALF_DOWN), "\n"; // 2 (toward 0)
echo round(2.5, 0, PHP_ROUND_HALF_ODD), "\n"; // 3
echo round(1.45, 1), "\n";
echo round(1234.5678, -2), "\n"; // 1200
echo ceil(4.1), "\n";
echo floor(4.9), "\n";

echo (int)"" . "\n";
echo (int)"abc" . "\n";
echo (int)"0x1f" . "\n";
echo (int)1.999 . "\n";
echo (int)-1.999 . "\n";

echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_FLOAT_MAX, "\n";
echo PHP_FLOAT_MIN, "\n";
echo PHP_FLOAT_EPSILON, "\n";
echo PHP_FLOAT_DIG, "\n";
echo PHP_INT_SIZE, "\n";
