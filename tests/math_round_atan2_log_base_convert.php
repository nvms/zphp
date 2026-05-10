<?php
echo floor(4.7), "\n";
echo floor(-4.7), "\n";
echo floor(4.0), "\n";
echo floor(0), "\n";
echo ceil(4.3), "\n";
echo ceil(-4.3), "\n";
echo ceil(4.0), "\n";
echo ceil(0), "\n";

echo round(1234.5678, -1), "\n";
echo round(1234.5678, -2), "\n";
echo round(0.5), "\n";
echo round(1.5), "\n";
echo round(2.5), "\n";
echo round(-0.5), "\n";
echo round(-1.5), "\n";

echo round(2.5, 0, PHP_ROUND_HALF_UP), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(2.5, 0, PHP_ROUND_HALF_ODD), "\n";

echo round(-2.5, 0, PHP_ROUND_HALF_UP), "\n";
echo round(-2.5, 0, PHP_ROUND_HALF_DOWN), "\n";
echo round(-2.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(-2.5, 0, PHP_ROUND_HALF_ODD), "\n";

echo defined("PHP_ROUND_HALF_AWAY_FROM_ZERO") ? "y" : "n", "\n";
echo defined("PHP_ROUND_HALF_TOWARDS_ZERO") ? "y" : "n", "\n";

echo atan2(1, 1), "\n";
echo round(atan2(1, 0), 6), "\n";
echo round(atan2(0, 1), 6), "\n";
echo round(atan2(1, -1), 6), "\n";
echo round(atan2(-1, -1), 6), "\n";

echo hypot(3, 4), "\n";
echo hypot(0, 0), "\n";
echo hypot(1, 0), "\n";
echo round(hypot(1.5, 2.5), 6), "\n";

echo round(exp(0), 6), "\n";
echo round(exp(1), 6), "\n";
echo round(exp(-1), 6), "\n";
echo round(exp(2), 6), "\n";

echo round(log(M_E), 6), "\n";
echo round(log(1), 6), "\n";
echo round(log(100, 10), 6), "\n";
echo round(log(8, 2), 6), "\n";
echo round(log10(100), 6), "\n";
echo round(log10(0.01), 6), "\n";
var_dump(log(0));
var_dump(log(-1));

echo round(deg2rad(180), 6), "\n";
echo round(deg2rad(90), 6), "\n";
echo round(rad2deg(M_PI), 6), "\n";
echo round(rad2deg(M_PI/2), 6), "\n";

echo base_convert("ff", 16, 10), "\n";
echo base_convert("255", 10, 16), "\n";
echo base_convert("1010", 2, 10), "\n";
echo base_convert("777", 8, 10), "\n";
echo base_convert("10", 10, 2), "\n";
echo base_convert("0", 10, 2), "\n";
echo base_convert("abc", 16, 2), "\n";
echo base_convert("dead", 16, 10), "\n";
echo base_convert("100", 2, 16), "\n";

echo round(M_PI, 6), "\n";
echo round(M_E, 6), "\n";

echo sqrt(16), "\n";
echo sqrt(2) > 1.4 ? "y" : "n", "\n";

echo round(sin(M_PI), 6), "\n";
echo round(cos(0), 6), "\n";
echo round(tan(0), 6), "\n";

echo intval(round(2.99999999, 0)), "\n";
echo round(0.1 + 0.2, 1), "\n";

echo floor(2.5e10), "\n";
echo ceil(-2.5e10), "\n";

echo round(3.45, 1), "\n";
echo round(3.55, 1), "\n";
echo round(0.5, 0, PHP_ROUND_HALF_EVEN), "\n";
echo round(1.5, 0, PHP_ROUND_HALF_EVEN), "\n";

echo round(-1234.5678, -2), "\n";
echo round(1234.5678, -3), "\n";
echo round(0, -1), "\n";
echo round(0.0, 5), "\n";
