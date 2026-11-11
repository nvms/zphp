<?php
// number_format as php's _php_math_number_format_ex and _long
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

$values = [0, -0.0, 1234.5678, -1234.5678, 0.5, -0.4, 999.999, 1e15, 4503599627370496.0, -4503599627370497.0, PHP_INT_MAX, PHP_INT_MIN, 9.2233720368547758E+18, 1.0E+25, 1.5e-7, INF, -INF, NAN, "1234.5", "12", true, null];
$decimals = [0, 2, 5, -1, -2, -5, -19, -20, PHP_INT_MIN];
foreach ($values as $v) {
    foreach ($decimals as $d) {
        try {
            echo var_export($v, true), " / $d: ", number_format($v, $d), "\n";
        } catch (Throwable $e) {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}
echo number_format(1234.5678, 4, '0', ','), "\n";
echo number_format(1234567.891, 2, ',', '.'), "\n";
echo number_format(1234567.891, 2, '', ''), "\n";
echo number_format(-1234567, 3, ' dec ', ' thou '), "\n";
echo number_format(0.125, 2), " ", number_format(1.005, 2), " ", number_format(-0.005, 2), "\n";
echo number_format(12345.6789, 30), "\n";
echo strlen(number_format(1.5, 400)), "\n";
foreach (["abc", [], "12abc"] as $bad) {
    try {
        number_format($bad);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
