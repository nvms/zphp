<?php
echo 0xff, "\n";        // 255
echo 0xFF, "\n";        // 255
echo 0x10, "\n";        // 16
echo 0x0, "\n";         // 0

echo 0o17, "\n";        // 15 (PHP 8.1+)
echo 017, "\n";         // 15
echo 0o0, "\n";         // 0
echo 0o777, "\n";       // 511

echo 0b1010, "\n";      // 10
echo 0b0, "\n";         // 0
echo 0b11111111, "\n";  // 255

// numeric separators (PHP 7.4+)
echo 1_000_000, "\n";    // 1000000
echo 1_000.5, "\n";       // 1000.5
echo 0xFF_FF_FF, "\n";    // 16777215
echo 0b1010_1010, "\n";   // 170
echo 0o17_77, "\n";       // 1023
echo 1_2_3, "\n";         // 123 (any place)

// scientific
echo 1e3, "\n";        // 1000
echo 1.5e2, "\n";       // 150
echo 2.5e-1, "\n";      // 0.25
echo 1E10, "\n";

// numeric strings
var_dump((int)"42");
var_dump((int)"42abc");
var_dump((int)"abc");
var_dump((int)"  42");
var_dump((int)"+42");
var_dump((int)"-42");
var_dump((int)"42.7");
var_dump((int)"0x1f");      // 0 (string casts don't auto-detect hex)
var_dump((int)"0b101");    // 0
var_dump((int)"017");        // 17 (decimal!)
var_dump((int)"1e2");        // 100 (PHP 7+)
var_dump((int)"1.5e3");      // 1500

// intval with base
echo intval("0x1f", 0), "\n";
echo intval("0x1f", 16), "\n";
echo intval("1f", 16), "\n";
echo intval("777", 8), "\n";
echo intval("0b11", 0), "\n";
echo intval("11", 2), "\n";
echo intval("11", 0), "\n";
echo intval("011", 0), "\n";

// floatval
var_dump((float)"3.14");
var_dump((float)"3.14abc");
var_dump((float)"abc");
var_dump((float)"1.5e3");
var_dump((float)".5");
var_dump((float)"5.");

// is_numeric
var_dump(is_numeric("123"));
var_dump(is_numeric("123abc"));
var_dump(is_numeric(" 123"));
var_dump(is_numeric("123 "));   // true (PHP 8+)
var_dump(is_numeric("0x1f"));    // false
var_dump(is_numeric("1.5e3"));
var_dump(is_numeric(""));
var_dump(is_numeric(123));
var_dump(is_numeric(1.5));
var_dump(is_numeric(true));     // false
var_dump(is_numeric(null));     // false

// arithmetic mixing
echo 1 + 1.5, "\n";       // 2.5 (float)
echo "3" + 4, "\n";        // 7
echo "3.5" + 4, "\n";      // 7.5
echo "1e2" + 0, "\n";      // 100

// integer overflow becomes float
echo PHP_INT_MAX + 1, "\n";
echo PHP_INT_MAX * 2, "\n";

// round trip large
$big = PHP_INT_MAX;
echo $big, "\n";
echo $big + 0.0, "\n";

// float precision
echo 0.1 + 0.2, "\n";
echo 0.1 + 0.2 == 0.3 ? "y" : "n", "\n"; // n (float precision)

// settype
$v = "42";
settype($v, "integer");
echo gettype($v), " ", $v, "\n";

$v = "3.14";
settype($v, "float");
echo gettype($v), " ", $v, "\n";

// printf format specifiers
printf("%d\n", 42);
printf("%d\n", 42.7);    // 42
printf("%d\n", "42abc"); // 42
printf("%05d\n", 42);
printf("%-5d|\n", 42);
printf("%+d %+d\n", 5, -5);
printf("%o\n", 8);       // 10
printf("%x %X\n", 255, 255);
printf("%b\n", 10);
printf("%e\n", 12345.6789);
printf("%f\n", 3.14);
printf("%.2f\n", 3.14159);
printf("%10.2f|\n", 3.14);
printf("%-10.2f|\n", 3.14);

// sprintf
$s = sprintf("[%05d %+.2f]", 42, 1.5);
echo $s, "\n";

// number_format
echo number_format(1234567.891), "\n";
echo number_format(1234567.891, 2), "\n";
echo number_format(1234567.891, 2, ",", "."), "\n";

// PHP_INT_SIZE = 8 on 64-bit
echo PHP_INT_SIZE, "\n";

// abs
echo abs(-PHP_INT_MAX), "\n";
echo abs(PHP_INT_MIN), "\n"; // overflows to float

// constants
echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_FLOAT_MAX > 0 ? "ok" : "bad", "\n";
echo PHP_FLOAT_EPSILON > 0 ? "ok" : "bad", "\n";
echo PHP_FLOAT_DIG, "\n";
