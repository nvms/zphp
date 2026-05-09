<?php
// abs edges
echo abs(0), "\n";
echo abs(-5), "\n";
echo abs(-5.5), "\n";
echo abs(PHP_INT_MIN), "\n";  // float
echo abs("-7"), "\n";
echo abs("3.14"), "\n";       // 3.14 (float path)
echo abs(-INF), "\n";
echo abs(-0.0), "\n";

// intval on various types
echo intval(true), "\n";
echo intval(false), "\n";
echo intval(null), "\n";
echo intval([1,2,3]), "\n";   // 1
echo intval([]), "\n";        // 0
echo intval("5abc"), "\n";
echo intval("abc"), "\n";
echo intval("0x1A", 16), "\n";
echo intval("0x1A", 0), "\n";
echo intval("010", 0), "\n";
echo intval("123", 8), "\n";

// floatval
echo floatval("3.14abc"), "\n";
echo floatval("abc"), "\n";
echo floatval("1e3"), "\n";

// number_format on PHP_INT_MAX (full precision via int path)
echo number_format(PHP_INT_MAX), "\n";
echo number_format(-PHP_INT_MAX), "\n";
echo number_format(PHP_INT_MAX, 2), "\n";

// arithmetic overflow promotion
$big = PHP_INT_MAX + 1;
var_dump($big);
$small = PHP_INT_MIN - 1;
var_dump($small);

// intdiv overflow
try {
    intdiv(PHP_INT_MIN, -1);
} catch (\ArithmeticError $e) {
    echo "ad: caught\n";
}
