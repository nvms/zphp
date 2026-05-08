<?php
// banker's rounding for sprintf %f (PHP behavior)
echo sprintf("%.0f", 0.5), "\n";    // 0 (half to even, 0 is even)
echo sprintf("%.0f", 1.5), "\n";    // 2
echo sprintf("%.0f", 2.5), "\n";    // 2
echo sprintf("%.0f", 3.5), "\n";    // 4
echo sprintf("%.0f", 4.5), "\n";    // 4
echo sprintf("%.0f", -0.5), "\n";   // -0
echo sprintf("%.0f", -2.5), "\n";   // -2
echo sprintf("%.0f", -3.5), "\n";   // -4

// non-tie cases
echo sprintf("%.0f", 0.4), "\n";    // 0
echo sprintf("%.0f", 0.6), "\n";    // 1
echo sprintf("%.0f", 1.49), "\n";   // 1
echo sprintf("%.0f", 1.51), "\n";   // 2

// float-noise classics
echo sprintf("%.2f", 1.005), "\n";  // 1.00 (1.005 stored as 1.00499...)

// rounding extending beyond shortest
echo sprintf("%.4f", log(100) / log(2)), "\n";   // 6.6439

// width and padding still work
echo sprintf("%10.2f|", 1.5), "\n";
echo sprintf("%-10.2f|", 1.5), "\n";
echo sprintf("%05.2f", 1.5), "\n";
echo sprintf("%+.0f", 2.5), "\n";

// %e scientific
echo sprintf("%e", 1234.5), "\n";
echo sprintf("%.2e", 1.5), "\n";
echo sprintf("%.0e", 1234.5), "\n";
echo sprintf("%E", 1234.5), "\n";

// %g general - non-zero
echo sprintf("%.3g", 0.0001234), "\n";
echo sprintf("%.3g", 12345), "\n";
