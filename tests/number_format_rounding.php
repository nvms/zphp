<?php
// classic float-noise rounding cases
echo number_format(1.005, 2), "\n";  // 1.01
echo number_format(2.675, 2), "\n";  // 2.68
echo number_format(0.55, 1), "\n";   // 0.6
echo number_format(0.05, 1), "\n";   // 0.1
echo number_format(0.5), "\n";       // 1
echo number_format(1.5), "\n";       // 2
echo number_format(2.5), "\n";       // 3
echo number_format(-0.5), "\n";      // -1
echo number_format(-1.5), "\n";      // -2
echo number_format(-2.5), "\n";      // -3

// trailing zeros and integers
echo number_format(1.5, 4), "\n";    // 1.5000
echo number_format(0, 2), "\n";      // 0.00
echo number_format(1.7), "\n";       // 2
echo number_format(0.4), "\n";       // 0
echo number_format(-0.4), "\n";      // 0 (no -0)
echo number_format(-0.0, 2), "\n";   // 0.00 (no -0.00)

// large numbers
echo number_format(1e9), "\n";       // 1,000,000,000
echo number_format(1e15, 2), "\n";   // 1,000,000,000,000,000.00

// custom seps
echo number_format(1234567.891, 2, ',', '.'), "\n";  // 1.234.567,89
echo number_format(1234567, 0, '.', ' '), "\n";      // 1 234 567
echo number_format(1234567.89, 2, ',--', '||'), "\n"; // 1||234||567,--89

// scientific input
echo number_format(1e-3, 6), "\n";   // 0.001000
echo number_format(1.5e-5, 8), "\n"; // 0.00001500
echo number_format(2.5e7, 2), "\n";  // 25,000,000.00

// rounding causes carry across integer boundary
echo number_format(99.999, 2), "\n"; // 100.00
echo number_format(9.95, 1), "\n";   // 10.0

// negative custom precision  
echo number_format(-1234.5, 1), "\n"; // -1,234.5

// huge precision
echo number_format(3.14159265358979, 8), "\n"; // 3.14159265
