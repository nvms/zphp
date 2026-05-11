<?php
echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_INT_SIZE, "\n";

var_dump(PHP_INT_MAX + 0);
var_dump(PHP_INT_MAX + 1);
var_dump(PHP_INT_MIN - 1);
var_dump(PHP_INT_MAX * 2);

echo gettype(PHP_INT_MAX + 1), "\n";
echo gettype(PHP_INT_MIN - 1), "\n";

echo intval(1.9), "\n";
echo intval(1.4), "\n";
echo intval(-1.9), "\n";
echo intval(-1.4), "\n";
echo intval(0.5), "\n";
echo intval(-0.5), "\n";
echo intval(0.0), "\n";

echo (int)1.9, "\n";
echo (int)(-1.9), "\n";

echo intval(1e10), "\n";
echo intval(1.5e10), "\n";

echo intval("100"), "\n";
echo intval("-100"), "\n";
echo intval(" 100 "), "\n";
echo intval("100abc"), "\n";
echo intval("abc"), "\n";
echo intval(""), "\n";
echo intval("3.14"), "\n";
echo intval("1e3"), "\n";
echo intval("+10"), "\n";

echo intval("0x1A"), "\n";
echo intval("0x1A", 16), "\n";
echo intval("0x1A", 0), "\n";
echo intval("0b101"), "\n";
echo intval("0b101", 2), "\n";
echo intval("0b101", 0), "\n";
echo intval("017"), "\n";
echo intval("017", 8), "\n";
echo intval("017", 0), "\n";
echo intval("0o17", 0), "\n";

echo intval("ff", 16), "\n";
echo intval("FF", 16), "\n";
echo intval("777", 8), "\n";
echo intval("1010", 2), "\n";

echo intval(true), "\n";
echo intval(false), "\n";
echo intval(null), "\n";

echo sprintf("%d", PHP_INT_MAX), "\n";
echo sprintf("%d", PHP_INT_MIN), "\n";

echo sprintf("%d", 1.5), "\n";
echo sprintf("%d", -1.5), "\n";

echo sprintf("%d", 1e10), "\n";
echo sprintf("%d", "100abc"), "\n";

echo sprintf("%x", PHP_INT_MAX), "\n";
echo sprintf("%o", PHP_INT_MAX), "\n";
echo sprintf("%b", PHP_INT_MAX), "\n";

echo dechex(PHP_INT_MAX), "\n";
echo decbin(PHP_INT_MAX), "\n";
echo decoct(PHP_INT_MAX), "\n";

echo hexdec("ffffffffffffffff") > PHP_INT_MAX ? "y" : "n", "\n";
echo bindec(str_repeat("1", 63)) === PHP_INT_MAX ? "y" : "n", "\n";

echo intval(PHP_INT_MAX + 0), "\n";

echo intval("9223372036854775807"), "\n";
echo intval("9223372036854775808"), "\n";
echo gettype(intval("9223372036854775808")), "\n";

echo (int)"9223372036854775807", "\n";


echo (int)1.999999999, "\n";
echo (int)(-1.999999999), "\n";

var_dump(PHP_INT_MAX === PHP_INT_MAX);
var_dump(PHP_INT_MIN === PHP_INT_MIN);

echo PHP_INT_MAX + 1.0 > PHP_INT_MAX ? "y" : "n", "\n";

echo intval("16", 10), "\n";
echo intval("16", 2) === 0 ? "y" : "n", "\n";

echo intval(0), "\n";
echo intval(""), "\n";
echo intval(" "), "\n";

echo gettype(intval(2.5)), "\n";
echo gettype(intval("42")), "\n";

echo (int)PHP_INT_MAX === PHP_INT_MAX ? "y" : "n", "\n";

echo intval(0.1), "\n";
echo intval(0.99999), "\n";

echo intval(2147483647), "\n";
echo intval(2147483648), "\n";

if (PHP_INT_SIZE === 8) {
    echo "64-bit\n";
    echo PHP_INT_MAX === 9223372036854775807 ? "y" : "n", "\n";
}

echo intval("123", 16), "\n";
echo intval("0123", 0), "\n";
echo intval("0x123", 0), "\n";
echo intval("0b101", 0), "\n";

echo intval(["0"]) === 1 ? "y" : "n", "\n";
echo intval([]), "\n";

echo intval("999999999999999999999"), "\n";
echo gettype(intval("999999999999999999999")), "\n";

$x = 100;
settype($x, "string");
echo gettype($x), "\n";
echo $x, "\n";

$x = "123";
settype($x, "int");
echo gettype($x), "\n";
echo $x, "\n";

$x = 1.99;
settype($x, "int");
echo gettype($x), "\n";
echo $x, "\n";
