<?php
echo number_format(1234567), "\n";
echo number_format(1234567.89), "\n";
echo number_format(1234567.89, 2), "\n";
echo number_format(1234567.89, 2, ".", ","), "\n";
echo number_format(1234567.89, 2, ",", "."), "\n";
echo number_format(1234567.89, 2, " ", "."), "\n";
echo number_format(0, 2), "\n";
echo number_format(0.5), "\n";
echo number_format(0.4), "\n";
echo number_format(-1234567.89, 2, ".", ","), "\n";

echo number_format(0.001, 4), "\n";
echo number_format(0.0001, 4), "\n";
echo number_format(0.00001, 4), "\n";

echo number_format(99.99, 2), "\n";
echo number_format(99.95, 1), "\n";
echo number_format(99.949, 1), "\n";

echo number_format(1000000000), "\n";
echo number_format(1000000000.5, 2), "\n";

echo number_format(-0.5), "\n";
echo number_format(-0.4), "\n";

echo number_format(123.456789, 0), "\n";
echo number_format(123.456789, 4), "\n";
echo number_format(123.456789, 10), "\n";

echo number_format(1234.5, 0), "\n";
echo number_format(2.5, 0), "\n";
echo number_format(3.5, 0), "\n";

echo number_format(1234567.89, 2, ".", ""), "\n";
echo number_format(1234567.89, 0, ".", ""), "\n";

echo number_format(1e9, 2), "\n";
echo number_format(1e15, 2), "\n";

echo number_format(0), "\n";
echo number_format(0.0), "\n";

echo number_format(PHP_INT_MAX), "\n";

echo number_format(123, 0, ".", "_"), "\n";
echo number_format(1234, 0, ".", "_"), "\n";
echo number_format(12345, 0, ".", "_"), "\n";
echo number_format(123456, 0, ".", "_"), "\n";

echo number_format(0.5, 2, ",", "."), "\n";

echo number_format(1234567.891, 2, ".", " "), "\n";
echo number_format(1234567.891, 3, ".", " "), "\n";

echo number_format(-0.0, 2), "\n";

echo number_format(99999.999, 2), "\n";

echo number_format(0.005, 2), "\n";
echo number_format(0.015, 2), "\n";
echo number_format(0.025, 2), "\n";
echo number_format(0.005, 2, ".", ""), "\n";

echo number_format(1234, 0, ",", "."), "\n";
echo number_format(12345.678, 2, ",", " "), "\n";

echo sprintf("%s", 42), "\n";
echo sprintf("$%.2f", 1234.5), "\n";
echo sprintf("%.2f%%", 50), "\n";
echo sprintf("%'05d", 42), "\n";
echo sprintf("%-15s|", "left"), "\n";
echo sprintf("%015.2f", 99.5), "\n";

echo base_convert("ff", 16, 10), "\n";
echo base_convert("255", 10, 16), "\n";
echo base_convert("FF", 16, 2), "\n";
echo base_convert("11111111", 2, 16), "\n";
echo base_convert("777", 8, 10), "\n";
echo base_convert("100", 10, 2), "\n";
echo base_convert("0", 10, 16), "\n";
echo base_convert("10", 10, 36), "\n";
echo base_convert("z", 36, 10), "\n";
echo base_convert("zz", 36, 10), "\n";
echo base_convert("abc", 16, 10), "\n";
echo base_convert("dead", 16, 16), "\n";
echo base_convert("DEAD", 16, 10), "\n";


echo decbin(10), "\n";
echo decbin(255), "\n";
echo dechex(255), "\n";
echo decoct(8), "\n";

echo bindec("1010"), "\n";
echo hexdec("ff"), "\n";
echo octdec("777"), "\n";

echo number_format(-0.5, 2), "\n";

echo number_format(123456789, 0, ".", " "), "\n";

echo number_format(1.005, 2), "\n";
echo number_format(1.015, 2), "\n";

echo number_format(-1234.5, 2), "\n";
echo number_format(-99.999, 2), "\n";

$prices = [10.5, 99.95, 1234.56, 0.99];
foreach ($prices as $p) {
    echo sprintf("\$%s", number_format($p, 2, ".", ",")), "\n";
}

echo number_format(1e20, 2), "\n";
