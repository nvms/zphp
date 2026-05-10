<?php
echo fdiv(10, 3), "\n";
echo fdiv(10, 0), "\n";
echo fdiv(-10, 0), "\n";
var_dump(fdiv(0, 0));
echo fdiv(1.5, 0.5), "\n";
echo fdiv(-1, 2), "\n";
echo fdiv(7, 2), "\n";

echo fdiv(INF, 1), "\n";
echo fdiv(-INF, 1), "\n";
var_dump(fdiv(INF, INF));
var_dump(fdiv(NAN, 1));

echo round(1234.5678, 0), "\n";
echo round(1234.5678, 1), "\n";
echo round(1234.5678, 2), "\n";
echo round(1234.5678, -1), "\n";
echo round(1234.5678, -2), "\n";
echo round(1234.5678, -3), "\n";
echo round(1234.5678, -4), "\n";
echo round(0.5, -1), "\n";

echo round(-1234.5678, -1), "\n";
echo round(-1234.5678, -2), "\n";

echo abs(-5.5), "\n";
echo abs(5.5), "\n";
echo abs(-0.0), "\n";
echo abs(-0.5), "\n";
echo abs(-1e-10), "\n";
echo abs(-1.5e10), "\n";
var_dump(abs(NAN));
echo abs(INF), "\n";
echo abs(-INF), "\n";

echo PHP_FLOAT_DIG, "\n";
echo PHP_FLOAT_EPSILON > 0 ? "y" : "n", "\n";

$a = 0.1 + 0.2;
$b = 0.3;
echo abs($a - $b) < PHP_FLOAT_EPSILON ? "no" : "yes-diff", "\n";

echo PHP_FLOAT_MAX > 1e300 ? "big" : "small", "\n";
echo PHP_FLOAT_MIN > 0 ? "min-pos" : "min-zero", "\n";

echo round(0.6225, 3), "\n";
echo round(0.625, 2), "\n";
echo round(0.005, 2), "\n";
echo round(0.015, 2), "\n";
echo round(0.025, 2), "\n";
echo round(0.035, 2), "\n";

echo round(0.005, 2, PHP_ROUND_HALF_UP), "\n";
echo round(0.005, 2, PHP_ROUND_HALF_DOWN), "\n";
echo round(0.005, 2, PHP_ROUND_HALF_EVEN), "\n";
echo round(0.005, 2, PHP_ROUND_HALF_ODD), "\n";

echo intval(0.1 + 0.2), "\n";
echo intval(0.99999999), "\n";
echo intval(-0.99999999), "\n";

echo round(0.1 + 0.2, 1), "\n";
echo (0.1 + 0.2) === 0.3 ? "eq" : "ne", "\n";

echo round(-0.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(0.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(1.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(3.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(4.5, 0, PHP_ROUND_HALF_EVEN), "\n";

echo round(1234567.891, -3), "\n";

echo round(99.5), "\n";
echo round(100.5), "\n";
echo round(99.499), "\n";
echo round(99.501), "\n";

printf("%.20f\n", 0.1);
printf("%.20f\n", 0.2);
printf("%.20f\n", 0.1 + 0.2);

echo abs(PHP_INT_MIN + 1), "\n";

echo abs(-PHP_INT_MAX), "\n";
echo abs(PHP_INT_MAX), "\n";

echo round(123, 0), "\n";
echo round(0, 0), "\n";
echo round(-0.0), "\n";
echo round(0.5, 5), "\n";

echo round(1.005, 2, PHP_ROUND_HALF_UP), "\n";

echo round(2.7, -1), "\n";
echo round(-2.7, -1), "\n";

echo round(7.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(8.5, 0, PHP_ROUND_HALF_EVEN), "\n";
