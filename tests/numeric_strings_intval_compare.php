<?php
foreach (["1", "1.5", " 1", "1 ", " 1 ", "  1.5 ", "+1", "-1", "+1.5", "-0.5", "1e3", "1.5e2", "0", "00", "01", "0x1A", "0b101", "0o17", "017", "1abc", "abc", "", " ", "."] as $s) {
    echo var_export($s, true), " is_numeric=", var_export(is_numeric($s), true), "\n";
}

foreach (["1", "1.5", "+1", " 1", "1 ", "1abc", "abc"] as $s) {
    echo var_export($s, true), " (int)=", (int)$s, " (float)=", (float)$s, "\n";
}

echo intval("0x1A"), "\n";
echo intval("0x1A", 16), "\n";
echo intval("0x1A", 0), "\n";
echo intval("1A", 16), "\n";
echo intval("0b101"), "\n";
echo intval("0b101", 2), "\n";
echo intval("0b101", 0), "\n";
echo intval("017"), "\n";
echo intval("017", 8), "\n";
echo intval("017", 0), "\n";

echo "0" == 0 ? "y" : "n", "\n";
echo "0" === 0 ? "y" : "n", "\n";
echo "0" == false ? "y" : "n", "\n";
echo "0" == "" ? "y" : "n", "\n";
echo 0 == "" ? "y" : "n", "\n";
echo 0 == "abc" ? "y" : "n", "\n";
echo "1" == 1 ? "y" : "n", "\n";
echo "1.0" == 1 ? "y" : "n", "\n";
echo "1abc" == 1 ? "y" : "n", "\n";
echo " 1" == 1 ? "y" : "n", "\n";
echo "1 " == 1 ? "y" : "n", "\n";
echo " 1 " == 1 ? "y" : "n", "\n";

echo strcmp("0", "0"), "\n";
echo strcmp("0", ""), "\n";

var_dump((int)"+5");
var_dump((int)"-5");
var_dump((int)"5+5");
var_dump((int)"  5  ");
var_dump((float)"  3.14  ");
var_dump((float)"1.5e3");
var_dump((float)"1.5E-3");

echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_INT_SIZE, "\n";

echo (int)"99999999999999999999", "\n";
echo (float)"99999999999999999999", "\n";
echo (int)"-99999999999999999999", "\n";

echo is_numeric("1_000") ? "y" : "n", "\n";
echo is_numeric("1.5e") ? "y" : "n", "\n";
echo is_numeric(".5") ? "y" : "n", "\n";
echo is_numeric("5.") ? "y" : "n", "\n";
echo is_numeric("e5") ? "y" : "n", "\n";
echo is_numeric("0e0") ? "y" : "n", "\n";
echo is_numeric("0.0") ? "y" : "n", "\n";
echo is_numeric("1.") ? "y" : "n", "\n";
echo is_numeric(".1") ? "y" : "n", "\n";

if ("100" > "99") echo "str-gt\n"; else echo "str-not\n";
if ("0" < "00") echo "lt\n"; else echo "ge\n";
if ("0" == "00") echo "eq\n"; else echo "ne\n";
if ("0e1" == "0") echo "e-eq\n"; else echo "e-ne\n";
if ("01" == "1") echo "01-eq\n"; else echo "01-ne\n";

echo intval(""), "\n";
echo intval("   "), "\n";
echo intval("abc"), "\n";
echo (float)"", "\n";
echo (float)"abc", "\n";
echo (float).5, "\n";

echo gettype(1+1), "\n";
echo gettype("1"+"1"), "\n";
echo gettype("1.5"+"2.5"), "\n";
echo gettype("1"+"1.5"), "\n";
