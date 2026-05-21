<?php
// regression: sprintf %e / %E with precision 0. zphp emitted a stray '.'
// for zero ("0.e+0") and failed to carry the exponent when the mantissa
// rounded up to 10 (99999 -> "10E+4" instead of "1E+5").
echo sprintf("%.0e", 0.0), "\n";        // 0e+0
echo sprintf("%+.0e", 0.0), "\n";       // +0e+0
echo sprintf("%.0E", 0.0), "\n";        // 0E+0
echo sprintf("%.0e", 99999.0), "\n";    // 1e+5
echo sprintf("%.0E", 99999.0), "\n";    // 1E+5
echo sprintf("%.0e", 5.0), "\n";        // 5e+0
echo sprintf("%.0e", 1234.5), "\n";     // 1e+3
echo sprintf("%.0e", -7.0), "\n";       // -7e+0
echo sprintf("%.0e", 0.5), "\n";        // 5e-1

// the exponent carry also applies at higher precision
echo sprintf("%.2e", 9.999), "\n";      // 1.00e+1
echo sprintf("%.1e", 9.96), "\n";       // 1.0e+1
echo sprintf("%.3e", 9999.9999), "\n";  // 1.000e+4

// precision > 0 still includes the decimal point
echo sprintf("%.1e", 0.0), "\n";        // 0.0e+0
echo sprintf("%.3e", 0.0), "\n";        // 0.000e+0
echo sprintf("%e", 0.0), "\n";          // 0.000000e+0
echo sprintf("%.2e", 1.0), "\n";        // 1.00e+0

// ordinary scientific values unaffected
echo sprintf("%.3e", 12345.678), "\n";
echo sprintf("%.2e", 0.00012345), "\n";
echo sprintf("%E", 123456789.0), "\n";
