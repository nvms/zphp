<?php
echo sprintf("%d", 42), "\n";
echo sprintf("%5d", 42), "\n";
echo sprintf("%-5d|", 42), "\n";
echo sprintf("%05d", 42), "\n";
echo sprintf("%+d", 42), "\n";
echo sprintf("%+d", -42), "\n";
echo sprintf("%5.0d", 42), "\n";
echo sprintf("%-10d|", 42), "\n";
echo sprintf("%010d", -42), "\n";

echo sprintf("%s", "hello"), "\n";
echo sprintf("%10s", "hi"), "\n";
echo sprintf("%-10s|", "hi"), "\n";
echo sprintf("%.3s", "hello world"), "\n";
echo sprintf("%5.3s", "hello"), "\n";
echo sprintf("%-5.3s|", "hello"), "\n";
echo sprintf("%s", ""), "\n";

echo sprintf("%f", 3.14), "\n";
echo sprintf("%.2f", 3.14), "\n";
echo sprintf("%.0f", 3.14), "\n";
echo sprintf("%10.2f", 3.14), "\n";
echo sprintf("%-10.2f|", 3.14), "\n";
echo sprintf("%010.2f", 3.14), "\n";
echo sprintf("%+.2f", 3.14), "\n";
echo sprintf("%.2f", -3.14), "\n";
echo sprintf("%.5f", 0.1), "\n";

echo sprintf("%x", 255), "\n";
echo sprintf("%X", 255), "\n";
echo sprintf("%04x", 255), "\n";
echo sprintf("%4x", 255), "\n";
echo sprintf("%-4x|", 255), "\n";
echo sprintf("%x", 0), "\n";
echo sprintf("%x", -1) === "ffffffffffffffff" ? "y" : "n", "\n";

echo sprintf("%o", 8), "\n";
echo sprintf("%o", 64), "\n";
echo sprintf("%5o", 64), "\n";
echo sprintf("%05o", 64), "\n";
echo sprintf("%-5o|", 64), "\n";

echo sprintf("%b", 5), "\n";
echo sprintf("%b", 255), "\n";
echo sprintf("%8b", 5), "\n";
echo sprintf("%08b", 5), "\n";
echo sprintf("%-8b|", 5), "\n";

echo sprintf("%c", 65), "\n";
echo sprintf("%c", 97), "\n";

echo sprintf("%%"), "\n";
echo sprintf("a%%b"), "\n";

echo sprintf("%2\$s %1\$s", "world", "hello"), "\n";
echo sprintf("%1\$d-%2\$d-%1\$d", 1, 2), "\n";

echo sprintf("%-30s|", "left"), "\n";
echo sprintf("%30s|", "right"), "\n";

echo sprintf("%'.10s", "hi"), "\n";
echo sprintf("%'-10s", "hi"), "\n";
echo sprintf("%'010s", "hi"), "\n";

echo sprintf("%d %s %f", 1, "x", 2.5), "\n";

echo sprintf("[%s]", null), "\n";
echo sprintf("[%s]", true), "\n";
echo sprintf("[%s]", false), "\n";
echo sprintf("[%d]", null), "\n";
echo sprintf("[%d]", true), "\n";
echo sprintf("[%d]", "5abc") === "[5]" ? "y" : "n", "\n";

echo sprintf("%5.10s", "hello world"), "\n";
echo sprintf("%.0s", "hello"), "\n";

echo sprintf("%.20f", 1.5), "\n";
echo sprintf("%.20f", 0.1), "\n";
echo sprintf("%.0f", 0.5), "\n";
echo sprintf("%.0f", 1.5), "\n";
echo sprintf("%.0f", 2.5), "\n";

echo sprintf("%30.20f", 3.14), "\n";

echo sprintf("%e", 1234.5678), "\n";
echo sprintf("%.3e", 1234.5678), "\n";
echo sprintf("%E", 1234.5678), "\n";

echo sprintf("%g", 1234.5678), "\n";
echo sprintf("%g", 0.0001234), "\n";
echo sprintf("%.3g", 1234.5678), "\n";

echo sprintf("%05d", 12345), "\n";
echo sprintf("%05d", 123456), "\n";

echo sprintf("%.0d", 0), "\n";
echo sprintf("%.0d", 5), "\n";

echo sprintf("%5.2d", 42), "\n";

echo sprintf("%-30.5s|", "hello world"), "\n";
echo sprintf("%-30.20s|", "hello world"), "\n";

echo sprintf("%'_-10s|", "hi"), "\n";
echo sprintf("%'_10s|", "hi"), "\n";

echo sprintf("%2\$s-%1\$s-%3\$s", "B", "A", "C"), "\n";

echo strlen(sprintf("%100s", "x")), "\n";
echo strlen(sprintf("%-100s", "x")), "\n";

echo sprintf("[%d]", PHP_INT_MAX), "\n";
echo sprintf("[%d]", PHP_INT_MIN), "\n";

echo sprintf("%.0f", 1e20), "\n";

echo sprintf("%s", "naïve"), "\n";
echo strlen(sprintf("%10s", "naïve")), "\n";
