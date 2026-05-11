<?php
var_dump((int)"  42  ");
var_dump((int)"42abc");
var_dump((int)"abc");
var_dump((int)"");
var_dump((int)"0");
var_dump((int)"007");
var_dump((int)"0x1A");
var_dump((int)"1e3");
var_dump((int)"-42");
var_dump((int)"+42");
var_dump((int)true);
var_dump((int)false);
var_dump((int)null);
var_dump((int)1.9);
var_dump((int)-1.9);

var_dump((float)"3.14");
var_dump((float)"abc");
var_dump((float)"1e3");

var_dump((bool)"");
var_dump((bool)"0");
var_dump((bool)"0.0");
var_dump((bool)"false");
var_dump((bool)0);
var_dump((bool)1);
var_dump((bool)null);
var_dump((bool)[]);
var_dump((bool)[0]);

var_dump((string)42);
var_dump((string)3.14);
var_dump((string)true);
var_dump((string)false);
var_dump((string)null);

echo (0 == "0") ? "y" : "n", "\n";
echo (0 == "") ? "y" : "n", "\n";
echo (0 == "abc") ? "y" : "n", "\n";
echo (0 == "0abc") ? "y" : "n", "\n";
echo ("1" == "01") ? "y" : "n", "\n";
echo ("10" == "1e1") ? "y" : "n", "\n";
echo (100 == "1e2") ? "y" : "n", "\n";

echo (null == 0) ? "y" : "n", "\n";
echo (null == "") ? "y" : "n", "\n";
echo (null == "0") ? "y" : "n", "\n";
echo (null == false) ? "y" : "n", "\n";
echo (false == 0) ? "y" : "n", "\n";
echo (false == "") ? "y" : "n", "\n";
echo (false == "0") ? "y" : "n", "\n";

echo (0 === "0") ? "y" : "n", "\n";
echo (0 === 0.0) ? "y" : "n", "\n";

echo intval("  42  "), "\n";
echo intval("42abc"), "\n";
echo intval("0x1A", 16), "\n";
echo intval("777", 8), "\n";
echo intval("1010", 2), "\n";
echo intval("ff", 16), "\n";
echo intval(""), "\n";
echo intval(null), "\n";
echo intval("0x1A", 0), "\n";
echo intval("0777", 0), "\n";

echo floatval("3.14"), "\n";
echo floatval("3.14abc"), "\n";
echo floatval("abc"), "\n";
echo floatval("1e3"), "\n";

echo (1 <=> 2), "\n";
echo (2 <=> 1), "\n";
echo (1 <=> 1), "\n";
echo ("a" <=> "b"), "\n";
echo ([1,2] <=> [1,2,3]), "\n";

var_dump(is_numeric("42"));
var_dump(is_numeric("4.2"));
var_dump(is_numeric("4e2"));
var_dump(is_numeric(" 42"));
var_dump(is_numeric("42abc"));
var_dump(is_numeric(""));
var_dump(is_numeric("0x1A"));
var_dump(is_numeric("+42"));
var_dump(is_numeric("-.5"));

var_dump(intdiv(10, 3));
var_dump(intdiv(-10, 3));
var_dump(intdiv(10, -3));

echo ("123" + 0), "\n";
echo ("1.5" * 2), "\n";
echo ("1e3" + 1), "\n";
