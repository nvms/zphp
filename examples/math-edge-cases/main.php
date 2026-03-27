<?php
// covers: integer overflow, float precision, division edge cases, modulo,
//         abs, ceil, floor, round, max, min, pow, sqrt, log, intdiv,
//         PHP_INT_MAX, PHP_INT_MIN, PHP_FLOAT_MAX, PHP_FLOAT_EPSILON,
//         INF, NAN, is_nan, is_infinite, is_finite, intval, floatval

// --- integer limits ---

echo "--- integer limits ---\n";
echo "INT_MAX: " . PHP_INT_MAX . "\n";
echo "INT_MIN: " . PHP_INT_MIN . "\n";
echo "INT_MAX is positive: " . (PHP_INT_MAX > 0 ? "true" : "false") . "\n";
echo "INT_MIN is negative: " . (PHP_INT_MIN < 0 ? "true" : "false") . "\n";

// --- float precision ---

echo "--- float precision ---\n";
echo "0.1 + 0.2 == 0.3: " . ((0.1 + 0.2) == 0.3 ? "true" : "false") . "\n";
$epsilon = 1e-10;
echo "within epsilon: " . (abs(0.1 + 0.2 - 0.3) < $epsilon ? "true" : "false") . "\n";

echo "1/3 + 2/3: " . (1/3 + 2/3) . "\n";
echo "1/3 * 3: " . (1/3 * 3) . "\n";

// --- division ---

echo "--- division ---\n";
echo "10 / 3: " . (10 / 3) . "\n";
echo "10 / 5: " . (10 / 5) . "\n";
echo "intdiv(10, 3): " . intdiv(10, 3) . "\n";
echo "-7 / 2: " . (-7 / 2) . "\n";
echo "intdiv(-7, 2): " . intdiv(-7, 2) . "\n";

// --- modulo ---

echo "--- modulo ---\n";
echo "10 % 3: " . (10 % 3) . "\n";
echo "-10 % 3: " . (-10 % 3) . "\n";
echo "10 % -3: " . (10 % -3) . "\n";
echo "-10 % -3: " . (-10 % -3) . "\n";
echo "fmod(10.5, 3.2): " . fmod(10.5, 3.2) . "\n";
echo "fmod(-10.5, 3.2): " . fmod(-10.5, 3.2) . "\n";

// --- special values ---

echo "--- special values ---\n";
echo "INF: " . INF . "\n";
echo "-INF: " . (-INF) . "\n";
echo "NAN: " . NAN . "\n";
echo "is_nan(NAN): " . (is_nan(NAN) ? "true" : "false") . "\n";
echo "is_nan(1.0): " . (is_nan(1.0) ? "true" : "false") . "\n";
echo "is_infinite(INF): " . (is_infinite(INF) ? "true" : "false") . "\n";
echo "is_infinite(1.0): " . (is_infinite(1.0) ? "true" : "false") . "\n";
echo "is_finite(1.0): " . (is_finite(1.0) ? "true" : "false") . "\n";
echo "is_finite(INF): " . (is_finite(INF) ? "true" : "false") . "\n";
echo "INF + INF: " . (INF + INF) . "\n";
echo "INF - INF: " . (INF - INF) . "\n";
echo "INF * 0: " . (INF * 0) . "\n";
echo "1 / INF: " . (1 / INF) . "\n";

// --- math functions ---

echo "--- math functions ---\n";
echo "abs(-42): " . abs(-42) . "\n";
echo "abs(42): " . abs(42) . "\n";
echo "ceil(4.1): " . ceil(4.1) . "\n";
echo "ceil(4.9): " . ceil(4.9) . "\n";
echo "ceil(-4.1): " . ceil(-4.1) . "\n";
echo "floor(4.9): " . floor(4.9) . "\n";
echo "floor(-4.1): " . floor(-4.1) . "\n";
echo "round(4.5): " . round(4.5) . "\n";
echo "round(4.4): " . round(4.4) . "\n";
echo "round(-4.5): " . round(-4.5) . "\n";
echo "round(3.14159, 2): " . round(3.14159, 2) . "\n";

echo "pow(2, 10): " . pow(2, 10) . "\n";
echo "pow(2, -1): " . pow(2, -1) . "\n";
echo "sqrt(144): " . sqrt(144) . "\n";
echo "sqrt(2): " . round(sqrt(2), 10) . "\n";

echo "max(1, 2, 3): " . max(1, 2, 3) . "\n";
echo "min(1, 2, 3): " . min(1, 2, 3) . "\n";

echo "log(M_E): " . round(log(M_E), 10) . "\n";
echo "log10(1000): " . log10(1000) . "\n";
echo "log2(8): " . log(8, 2) . "\n";

// --- type conversion ---

echo "--- type conversion ---\n";
echo "intval('42'): " . intval('42') . "\n";
echo "intval('0x1A'): " . intval('0x1A', 16) . "\n";
echo "intval('0b1010'): " . intval('0b1010', 2) . "\n";
echo "intval('077'): " . intval('077', 8) . "\n";
echo "floatval('3.14'): " . floatval('3.14') . "\n";
echo "intval(3.9): " . intval(3.9) . "\n";
echo "intval(-3.9): " . intval(-3.9) . "\n";

// --- bitwise ---

echo "--- bitwise ---\n";
echo "0xFF & 0x0F: " . (0xFF & 0x0F) . "\n";
echo "0xF0 | 0x0F: " . (0xF0 | 0x0F) . "\n";
echo "0xFF ^ 0x0F: " . (0xFF ^ 0x0F) . "\n";
echo "~0: " . (~0) . "\n";
echo "1 << 8: " . (1 << 8) . "\n";
echo "256 >> 4: " . (256 >> 4) . "\n";

// --- comparison edge cases ---

echo "--- comparisons ---\n";
echo "0 == false: " . (0 == false ? "true" : "false") . "\n";
echo "0 === false: " . (0 === false ? "true" : "false") . "\n";
echo "'' == false: " . ('' == false ? "true" : "false") . "\n";
echo "'0' == false: " . ('0' == false ? "true" : "false") . "\n";
echo "null == false: " . (null == false ? "true" : "false") . "\n";
echo "0 == null: " . (0 == null ? "true" : "false") . "\n";
echo "'' == null: " . ('' == null ? "true" : "false") . "\n";

// spaceship operator
echo "1 <=> 2: " . (1 <=> 2) . "\n";
echo "2 <=> 1: " . (2 <=> 1) . "\n";
echo "1 <=> 1: " . (1 <=> 1) . "\n";

echo "done\n";
