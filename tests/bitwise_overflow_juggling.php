<?php
// AND
echo 0b1100 & 0b1010, "\n";
echo 0xFF & 0x0F, "\n";
echo -1 & 0xFF, "\n";

// OR
echo 0b1100 | 0b0011, "\n";
echo 0 | 0xFF, "\n";

// XOR
echo 0b1100 ^ 0b1010, "\n";
echo 0xFF ^ 0xFF, "\n";

// NOT
echo ~0, "\n";
echo ~1, "\n";
echo ~-1, "\n";

// shifts
echo 1 << 0, "\n";
echo 1 << 1, "\n";
echo 1 << 8, "\n";
echo 1 << 30, "\n";
echo 1 << 31, "\n";
echo 1 << 62, "\n";
echo 256 >> 1, "\n";
echo 256 >> 8, "\n";
echo 1 >> 1, "\n";
echo -1 >> 1, "\n"; // arithmetic shift

// negative shift count throws
try { $x = 1 << -1; echo "no\n"; }
catch (\ArithmeticError $e) { echo "neg-shift\n"; }

try { $x = 1 >> -1; echo "no\n"; }
catch (\ArithmeticError $e) { echo "neg-shift-r\n"; }

// shift overflow goes to 0
echo 1 << 63, "\n"; // PHP_INT_MIN
echo 1 << 64, "\n"; // 0 (overflow)
echo 0xFF << 60, "\n";

// PHP_INT bounds
echo PHP_INT_MAX, "\n";
echo PHP_INT_MIN, "\n";
echo PHP_INT_SIZE, "\n";

// integer overflow becomes float
echo PHP_INT_MAX + 1, "\n"; // 9.2233720368548E+18
echo PHP_INT_MAX * 2, "\n";
echo PHP_INT_MIN - 1, "\n";

// abs on PHP_INT_MIN overflows to float
echo abs(PHP_INT_MIN), "\n";

// string-on-string bitwise ops (architectural - byte-wise & | ^ ~ on strings)

// integer ops: result is int
$a = 5 & 3; var_dump($a);
$a = 5 | 3; var_dump($a);

// type juggle: bool to int in &
echo (true & 5), "\n"; // 1 (true=1, 5=5)
echo (true | 0), "\n"; // 1

// null in bitwise
echo (null & 5), "\n"; // 0

// float-to-int deprecation in bitwise (architectural - PHP emits notice)
echo (5 & 3), "\n";

// numeric string to int in bitwise
echo ("7" & 3), "\n"; // 3

// non-numeric string with int bitwise -> PHP TypeError (architectural - zphp permissive)

// integer division
echo intdiv(7, 2), "\n";
echo intdiv(-7, 2), "\n";
echo intdiv(7, -2), "\n";

// modulo with negative
echo 7 % 3, "\n";
echo -7 % 3, "\n";
echo 7 % -3, "\n";
echo -7 % -3, "\n";

// modulo by zero
try { $x = 7 % 0; echo "no\n"; }
catch (\DivisionByZeroError $e) { echo "mod0\n"; }

// integer division by zero
try { intdiv(7, 0); echo "no\n"; }
catch (\DivisionByZeroError $e) { echo "id0\n"; }

// PHP_INT_MIN overflow on intdiv
try { intdiv(PHP_INT_MIN, -1); echo "no\n"; }
catch (\ArithmeticError $e) { echo "id-overflow\n"; }

// type juggling in comparison (PHP 8+ semantics)
var_dump(0 == "abc"); // false in PHP 8 (was true in 7)
var_dump(0 == ""); // false in PHP 8
var_dump(0 == "0"); // true
var_dump("1" == "01"); // true (numeric strings)
var_dump("10" == "1e1"); // true (numeric)
var_dump(100 == "1e2"); // true
var_dump("abc" == "abc"); // true
var_dump(null == false); // true
var_dump(null == 0); // true
var_dump(false == 0); // true
var_dump([] == false); // true
var_dump([] == 0); // false
var_dump([] == null); // true

// strict comparison
var_dump(0 === "0"); // false
var_dump(1 === 1.0); // false
var_dump([1, 2] === [1, 2]);
var_dump([1, 2] === [2, 1]);

// arithmetic with strings
echo "3" + 4, "\n"; // 7
echo "3.5" + 4, "\n"; // 7.5
echo "1e2" + 0, "\n"; // 100

// non-numeric string + int -> PHP TypeError (architectural - zphp permissive)

// numeric string with trailing text - PHP 8 deprecated/warning then casts the prefix
$r = (int)"3abc";
echo $r, "\n";

// concat operator
echo 1 . 2, "\n"; // "12"
echo "a" . 1, "\n";

// spaceship
var_dump(1 <=> 2);
var_dump(2 <=> 1);
var_dump(1 <=> 1);
var_dump("a" <=> "b");
var_dump([1, 2] <=> [1, 2]);
var_dump([1, 2] <=> [1, 3]);
