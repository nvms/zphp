<?php
echo intdiv(10, 3), "\n";
echo intdiv(10, -3), "\n";
echo intdiv(-10, 3), "\n";
echo intdiv(-10, -3), "\n";
echo intdiv(0, 5), "\n";
echo intdiv(PHP_INT_MAX, 1), "\n";

try { intdiv(1, 0); echo "no\n"; } catch (\DivisionByZeroError $e) { echo "dbz\n"; }
try { intdiv(PHP_INT_MIN, -1); echo "no\n"; } catch (\ArithmeticError $e) { echo "ae\n"; }

echo fmod(10, 3), "\n";
echo fmod(10.5, 3), "\n";
echo fmod(-10, 3), "\n";
echo fmod(10, -3), "\n";
echo fmod(0.0, 1.5), "\n";

var_dump(fmod(10, 0));

echo 10 % 3, "\n";
echo 10 % -3, "\n";
echo -10 % 3, "\n";
echo -10 % -3, "\n";

try { $x = 10 % 0; echo "no\n"; } catch (\DivisionByZeroError $e) { echo "dbz\n"; }

echo 2 ** 10, "\n";
echo 2 ** 0, "\n";
echo 2 ** -2, "\n";
echo 0 ** 0, "\n";
echo (-2) ** 3, "\n";
echo (-2) ** 4, "\n";
echo 1.5 ** 2, "\n";
echo 1.5 ** 2.5, "\n";
echo 10 ** 308, "\n";
echo 10 ** 309, "\n";

echo 1 + 2, "\n";
var_dump(1 + 2);
var_dump(1 + 2.5);
var_dump(1.5 + 2);
var_dump(1.5 + 2.5);
var_dump(1 + 1.0);
var_dump(PHP_INT_MAX + 1);
var_dump(PHP_INT_MAX - 1);
var_dump(PHP_INT_MIN - 1);

echo PHP_INT_MAX * 2, "\n";
var_dump(PHP_INT_MAX * 2);

echo 10 / 3, "\n";
var_dump(10 / 3);
var_dump(10 / 2);
var_dump(10 / 5);
var_dump(0 / 1);
var_dump(1 / 0.5);

try { $x = 10 / 0; } catch (\DivisionByZeroError $e) { echo "dbz\n"; }
try { $x = 10.0 / 0; } catch (\DivisionByZeroError $e) { echo "dbz\n"; }

echo 0xff & 0x0f, "\n";
echo 0xff | 0x0f, "\n";
echo 0xff ^ 0x0f, "\n";
echo ~0, "\n";
echo ~1, "\n";
echo ~(-1), "\n";
echo 1 << 3, "\n";
echo 8 >> 1, "\n";
echo 1 << 62, "\n";
echo 1 << 63, "\n";
echo PHP_INT_MAX >> 1, "\n";

echo -5 & 0xff, "\n";
echo -5 | 0, "\n";
echo -5 ^ -1, "\n";
echo -5 << 1, "\n";
echo -5 >> 1, "\n";
echo -1 >> 1, "\n";
echo -1 << 1, "\n";

echo gettype(1 + 2), "\n";
echo gettype(1 + 2.0), "\n";
echo gettype(1 / 2), "\n";
echo gettype(4 / 2), "\n";
echo gettype(1.0 / 1.0), "\n";
echo gettype(2 ** 3), "\n";
echo gettype(2 ** 0.5), "\n";
echo gettype(PHP_INT_MAX + 1), "\n";

echo intval(1.9), "\n";
echo intval(-1.9), "\n";
echo intval(2.5), "\n";
echo intval(-2.5), "\n";
echo (int)1.9, "\n";
echo (int)-1.9, "\n";
echo (int)2.5, "\n";
echo (int)-2.5, "\n";

echo intval("0x1A"), "\n";
echo intval("0x1A", 0), "\n";
echo intval("100", 8), "\n";
echo intval("100", 2), "\n";
echo intval("ff", 16), "\n";

echo abs(-5), "\n";
echo abs(-5.5), "\n";
echo abs(PHP_INT_MIN + 1), "\n";

echo min(1, 2, 3), "\n";
echo max(1, 2, 3), "\n";
echo min(1.5, 1, 2), "\n";
echo max("a", "b", "c"), "\n";
echo min([3,1,2]), "\n";
echo max([3,1,2]), "\n";

var_dump(7.0 / 2.0);
var_dump(7 / 2);
var_dump(7 / 2.0);
var_dump(7.0 / 2);
