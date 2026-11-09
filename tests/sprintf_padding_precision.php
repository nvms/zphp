<?php
// width, padding and precision combined the way invoices, tables and logs use them

$rows = [
    ['Widget', 4, 3.5],
    ['Gadget with a long name', 12, 1249.999],
    ['Refund', -1, -5.6],
    ['Free sample', 0, 0.0],
];
foreach ($rows as [$name, $qty, $price]) {
    printf("|%-12.12s|%5d|%10.2f|%-10.2f|%010.3f|%+.1f|\n", $name, $qty, $price, $price, $price, $price);
}

// the precision pads the fraction, the width pads the whole field
var_dump(sprintf("%-7.4f|", -5.6));
var_dump(sprintf("%7.4f|", 5.6));
var_dump(sprintf("%07.2f|%-07.2f|%+07.2f|%+-9.3F|", -1.5, -1.5, 1.5, 2.25));
var_dump(sprintf("%.0f %.0f %.0f %.0f %.0f", 0.5, 1.5, 2.5, -0.5, 3.5000001));
var_dump(sprintf("%.2f %.2f %.2f %.3f", 1.005, 2.675, 1.115, 0.0005));
var_dump(sprintf("%f %F %.10f %.15f", 1 / 3, 2 / 3, M_PI, 0.1));
var_dump(sprintf("%.53f", 0.1));
var_dump(sprintf("%.2f|%.1f|%5.1f", 1e15, 123456789012345678.0, -0.04));
var_dump(sprintf("%.3f %.3F", -0.0, -0.0001));

// custom padding characters
var_dump(sprintf("%'*10s|%'-10s|%-'.10s|%'010d|%'#12.3f", "right", "dash", "dots", 42, 3.14159));
var_dump(sprintf("%'x-8d|%'x8d|%-08d|%08d|%+08d|%-+8d|", 7, 7, -7, -7, 7, 7));

// strings: precision cuts, width pads
var_dump(sprintf("[%.3s][%5.2s][%-6.4s][%.0s][%.s][%010s][%-010s]", "abcdef", "abcdef", "abcdef", "abcdef", "abc", "pad", "pad"));
var_dump(sprintf("[% 5d][% -5d][% d]", 42, 42, -42));

// %e and %E use php's short exponent
var_dump(sprintf("%e|%E|%.2e|%.0e|%10.3e|%-12.1E|%+e", 1234.5678, 0.000123, -98765.4321, 5.5, 1e-10, 6.02e23, 0));
var_dump(sprintf("%e %e %e %.3e", 1.0, 0.0, -0.0, 9.9995));

// %g, %G, %h and %H choose between fixed and exponent notation
var_dump(sprintf("%g|%g|%g|%g|%g|%g", 0.0001, 0.00001, 123456, 1234567, 100000, 1e15));
var_dump(sprintf("%G|%.3g|%.10g|%.0g|%.1g|%g", 1.5e-7, 3.14159, 1 / 7, 25, 0.95, -0.0));
var_dump(sprintf("%h|%H|%.3h|%.20H", 1234567.891, 0.000012345, 6005e9, 0.1));
var_dump(sprintf("%.3g|%.2g|%.4g", 1005, 105, 99995));

// infinities and nan ignore width and precision
var_dump(sprintf("[%10f][%-10.2e][%010g][%+f][%+F][%05f][%5.1F]", INF, -INF, NAN, INF, NAN, -INF, NAN));

// the precision is capped at 53 digits with a notice
var_dump(sprintf("%.60f", 1.5));
var_dump(sprintf("%.100e", 2.5));
var_dump(sprintf("%.54g", 0.1));
