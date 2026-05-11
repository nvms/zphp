<?php
echo sprintf("%d", 42), "\n";
echo sprintf("%d", -42), "\n";
echo sprintf("%d", 3.7), "\n";
echo sprintf("%d", "42abc"), "\n";
echo sprintf("%5d", 42), "|\n";
echo sprintf("%-5d", 42), "|\n";
echo sprintf("%05d", 42), "|\n";
echo sprintf("%+d", 42), "\n";
echo sprintf("%+d", -42), "\n";

echo sprintf("%f", 3.14), "\n";
echo sprintf("%.2f", 3.14159), "\n";
echo sprintf("%.4f", 3.14), "\n";
echo sprintf("%10.2f", 3.14), "|\n";
echo sprintf("%-10.2f", 3.14), "|\n";
echo sprintf("%010.2f", 3.14), "|\n";
echo sprintf("%.0f", 3.7), "\n";

echo sprintf("%s", "hello"), "\n";
echo sprintf("%10s", "hi"), "|\n";
echo sprintf("%-10s", "hi"), "|\n";
echo sprintf("%.3s", "hello"), "\n";
echo sprintf("%'_10s", "hi"), "|\n";

echo sprintf("%e", 1234567), "\n";
echo sprintf("%.2e", 0.001234), "\n";
echo sprintf("%E", 1234567), "\n";

echo sprintf("%g", 1234567), "\n";
echo sprintf("%g", 0.00012345), "\n";
echo sprintf("%G", 1234567), "\n";

echo sprintf("%x", 255), "\n";
echo sprintf("%X", 255), "\n";
echo sprintf("%08x", 255), "\n";

echo sprintf("%o", 8), "\n";
echo sprintf("%o", 511), "\n";

echo sprintf("%b", 10), "\n";
echo sprintf("%08b", 10), "\n";

echo sprintf("%c", 65), "\n";
echo sprintf("%c", 8364), "\n";

echo sprintf("%%"), "\n";
echo sprintf("%d%%", 50), "\n";

echo sprintf("%u", 42), "\n";
echo sprintf("%u", -1), "\n";

echo sprintf("%s = %d", "n", 42), "\n";

echo sprintf("%2\$s %1\$s", "first", "second"), "\n";
echo sprintf("%1\$s-%1\$s-%2\$s", "a", "b"), "\n";

printf("%d\n", 42);
$out = printf("%s\n", "hello");
echo $out, "\n";

echo vsprintf("%s %d %f", ["test", 42, 3.14]), "\n";
vprintf("%d\n", [42]);

echo sprintf("%.0f", 0.5), "\n";
echo sprintf("%.0f", 1.5), "\n";
echo sprintf("%.0f", 2.5), "\n";

echo sprintf("%.1f", 1.05), "\n";
echo sprintf("%.1f", 2.05), "\n";

echo sprintf("%5.2f", 1.5), "|\n";
echo sprintf("%-5.2f", 1.5), "|\n";

echo sprintf("%d", PHP_INT_MAX), "\n";
echo sprintf("%d", PHP_INT_MIN), "\n";

echo sprintf("%5d", -42), "|\n";
echo sprintf("%-5d", -42), "|\n";
echo sprintf("%05d", -42), "|\n";

echo sprintf("%'*5d", 1), "|\n";
echo sprintf("%'_-5d", 1), "|\n";

echo sprintf("%.20f", 1.0/3.0), "\n";
echo sprintf("%.20f", 1e-10), "\n";

echo sprintf("%e", 0.0), "\n";
echo sprintf("%g", 0.0), "\n";

echo sprintf("%b", PHP_INT_MAX), "\n";
echo sprintf("%o", PHP_INT_MAX), "\n";
echo sprintf("%x", PHP_INT_MAX), "\n";

echo sprintf("%d", "  10  "), "\n";

echo sprintf("%s", null), "\n";
echo sprintf("%s", true), "\n";
echo sprintf("%s", false), "\n";

echo sprintf("%d", true), "\n";
echo sprintf("%d", false), "\n";
echo sprintf("%d", null), "\n";

echo sprintf("%4\$s %3\$s %2\$s %1\$s", "a", "b", "c", "d"), "\n";
