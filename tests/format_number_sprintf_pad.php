<?php
echo number_format(0), "\n";
echo number_format(0, 2), "\n";
echo number_format(1.5), "\n";
echo number_format(1.4), "\n";
echo number_format(0.5), "\n";
echo number_format(-1.5), "\n";

echo number_format(1234567), "\n";
echo number_format(1234567.891, 2), "\n";
echo number_format(1234567.891, 2, ".", ","), "\n";
echo number_format(1234567.891, 2, ",", "."), "\n";
echo number_format(1234567.891, 2, ".", " "), "\n";
echo number_format(1234567.891, 2, ".", "_"), "\n";
echo number_format(1234567, 0, ".", ""), "\n";

echo number_format(0.999999, 2), "\n";
echo number_format(99.999, 2), "\n";

echo number_format(-PHP_INT_MAX), "\n";
echo number_format(1.0e15), "\n";
echo number_format(1e-3, 6), "\n";

echo printf("%d\n", 42);
$s = sprintf("[%05d]", 42);
echo $s, "\n";
echo sprintf("%-10.2f|", 3.14), "\n";

printf("%'.10d\n", 42);
printf("%'*10s\n", "hi");

printf("%5\$d-%4\$d-%3\$d-%2\$d-%1\$d\n", 1, 2, 3, 4, 5);

echo sprintf("%b", 0xff), "\n";
echo sprintf("%o", 0xff), "\n";
echo sprintf("%x %X", 0xff, 0xff), "\n";

echo sprintf("%c", 0x41), "\n";

echo sprintf("%+05d", 42), "\n";
echo sprintf("%+5.2f", 3.14), "\n";

echo str_pad("hi", 10), "|\n";
echo str_pad("hi", 10, "-"), "|\n";
echo str_pad("hi", 10, "-", STR_PAD_LEFT), "|\n";
echo str_pad("hi", 10, "-", STR_PAD_BOTH), "|\n";

echo str_pad("hello", 12, "ab"), "|\n";
echo str_pad("x", 7, "12345"), "|\n";

echo str_pad("toolong", 5, "-"), "|\n";
echo str_pad("", 5, "-"), "|\n";

echo str_pad("abc", 5, " ", STR_PAD_BOTH), "|\n";
echo str_pad("abc", 6, " ", STR_PAD_BOTH), "|\n";
echo str_pad("abc", 7, " ", STR_PAD_BOTH), "|\n";

echo number_format(1234567.891, 0), "\n";

echo sprintf("%.0f", 0.5), "\n";
echo sprintf("%.0f", 1.5), "\n";
echo sprintf("%.0f", 2.5), "\n";
echo sprintf("%.0f", -0.5), "\n";

echo round(0.5), "\n";
echo round(1.5), "\n";
echo round(2.5), "\n";

echo number_format(1.234e-3, 7), "\n";

echo sprintf("%5d", 1), "\n";
echo sprintf("%-5d|", 1), "\n";
echo sprintf("%05d", 1), "\n";

printf("[%s]\n", "");
printf("[%5s]\n", "");
printf("[%.3s]\n", "abcdef");
printf("[%5.2s]\n", "abcdef");

echo sprintf("%.5s", "abcdef"), "\n";
echo sprintf("%.0s", "abc"), "\n";

$out = sprintf("name=%s age=%d", "alice", 30);
echo $out, "\n";

echo sprintf("%d", true), "\n";
echo sprintf("%d", false), "\n";
echo sprintf("%d", null), "\n";

echo sprintf("[%s]", true), "\n";
echo sprintf("[%s]", false), "\n";
echo sprintf("[%s]", null), "\n";

$ints = [1, 22, 333, 4444];
foreach ($ints as $i) printf("%5d\n", $i);

$strs = ["a", "ab", "abc"];
foreach ($strs as $s) printf("[%-5s]\n", $s);
