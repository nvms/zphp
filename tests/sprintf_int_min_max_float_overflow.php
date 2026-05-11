<?php
echo sprintf("%d", PHP_INT_MAX), "\n";
echo sprintf("%d", PHP_INT_MIN), "\n";
echo sprintf("%020d", PHP_INT_MAX), "\n";
echo sprintf("%020d", PHP_INT_MIN), "\n";
echo sprintf("%+d", PHP_INT_MAX), "\n";
echo sprintf("%+d", PHP_INT_MIN), "\n";

echo sprintf("%x", PHP_INT_MAX), "\n";
echo sprintf("%016x", PHP_INT_MAX), "\n";

echo sprintf("%b", PHP_INT_MAX), "\n";
echo strlen(sprintf("%b", PHP_INT_MAX)), "\n";

echo sprintf("%f", 1e100), "\n";
echo sprintf("%f", -1e100), "\n";
echo sprintf("%.0f", 1e15), "\n";
echo sprintf("%.0f", 1e20), "\n";

echo sprintf("%e", 1e-100), "\n";
echo sprintf("%e", 1e+100), "\n";
echo sprintf("%.5e", 1.23456789e10), "\n";
echo sprintf("%.10e", 1e-100), "\n";
echo sprintf("%E", 1e10), "\n";

echo sprintf("%g", 1e-5), "\n";
echo sprintf("%g", 1e-4), "\n";
echo sprintf("%g", 1e10), "\n";
echo sprintf("%.10g", 1.1234567890123), "\n";

echo sprintf("%30d", 42), "\n";
echo sprintf("%-30d|", 42), "\n";
echo sprintf("%030d", 42), "\n";

echo sprintf("%.50f", 0.1), "\n";

echo sprintf("[%5.0f]", 1.5), "\n";
echo sprintf("[%.0f]", 1234567.89), "\n";

echo sprintf("%'01000s|", "x") === str_pad("x", 1000, "0", STR_PAD_LEFT) . "|" ? "y" : "n", "\n";

echo strlen(sprintf("%100s", "test")), "\n";

echo sprintf("%d", 9.99e15), "\n";

echo sprintf("%.5f", INF), "\n";
echo sprintf("%.5f", -INF), "\n";
echo sprintf("%.5f", NAN), "\n";

echo sprintf("%5d|%5d", 1, 2), "\n";
echo sprintf("%-10s|%-10s", "left", "right"), "\n";

$args = [42, "text", 3.14];
echo vsprintf("%d %s %.2f", $args), "\n";

echo sprintf("%d", "9223372036854775807"), "\n";

echo sprintf("[%010s]", "abc"), "\n";
echo sprintf("[%010d]", -5), "\n";

echo sprintf("[%-010d]", 5), "\n";

echo sprintf("%X", 0xdeadbeef), "\n";

echo sprintf("%o", 0777), "\n";
echo sprintf("%o", 0xff), "\n";

echo sprintf("%.20e", PHP_FLOAT_EPSILON), "\n";

echo sprintf("%c%c%c", 65, 66, 67), "\n";

echo strlen(sprintf("%'-100d", 42)), "\n";

$result = sprintf("%1\$s %1\$s", "hi");
echo $result, "\n";

echo sprintf("[%1\$.3f]", 3.14159), "\n";
echo sprintf("[%5\$d]-[%1\$d]", 1, 2, 3, 4, 5), "\n";

$f = 1.0 / 3.0;
echo sprintf("%.5f", $f), "\n";
echo sprintf("%.15f", $f), "\n";
echo sprintf("%.30f", $f), "\n";

echo sprintf("%d", 1e15), "\n";
echo sprintf("%d", 0.5), "\n";
echo sprintf("%d", -0.5), "\n";

echo sprintf("%f", 0.0), "\n";
echo sprintf("%f", -0.0), "\n";
echo sprintf("%+f", 0.0), "\n";
echo sprintf("%+f", -0.0), "\n";

echo sprintf("%e", 0.0), "\n";
echo sprintf("%e", -0.0), "\n";

echo sprintf("%05d", 0), "\n";
echo sprintf("%05d", -0), "\n";

echo sprintf("%.0e", 1234567), "\n";

echo sprintf("%d", true), "\n";
echo sprintf("%d", false), "\n";
echo sprintf("%d", null), "\n";

echo sprintf("%05d", true), "\n";

$big = 99999999999999.5;
echo sprintf("%.2f", $big), "\n";
echo sprintf("%.0f", $big), "\n";

echo sprintf("%.10f", 1.0 / 7.0), "\n";


$arr = [1, 2, 3];
echo vsprintf("(%d, %d, %d)", $arr), "\n";
