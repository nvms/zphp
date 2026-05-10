<?php
echo number_format(-1234.5678), "\n";
echo number_format(-1234.5678, 2), "\n";
echo number_format(-0.5), "\n";
echo number_format(-0.4), "\n";
echo number_format(0.5), "\n";
echo number_format(0.4), "\n";
echo number_format(-0.0), "\n";
echo number_format(0.0), "\n";

echo number_format(1e20), "\n";
echo number_format(1.5e20, 2), "\n";
echo number_format(-1e20), "\n";
echo number_format(1e-5, 10), "\n";
echo number_format(0.00001234, 8), "\n";

echo number_format(1234.5, 2, ",", "."), "\n";
echo number_format(1234.5, 2, ".", ","), "\n";
echo number_format(1234.5, 2, " ", "'"), "\n";
echo number_format(1234567.89, 2, ".", "_"), "\n";

echo number_format(123, 5), "\n";
echo number_format(0, 5), "\n";
echo number_format(-0.000001, 8), "\n";

echo number_format(PHP_INT_MAX), "\n";
echo number_format(PHP_INT_MIN), "\n";

echo sprintf("%e", 0), "\n";
echo sprintf("%e", 1.5), "\n";
echo sprintf("%e", 12345.6789), "\n";
echo sprintf("%e", -1234.5), "\n";
echo sprintf("%e", 0.000123), "\n";
echo sprintf("%.3e", 12345.6789), "\n";
echo sprintf("%.0e", 12345.6789), "\n";
echo sprintf("%.10e", 1.5), "\n";
echo sprintf("%15.5e", 1234.5), "\n";
echo sprintf("%-15.5e|", 1234.5), "\n";
echo sprintf("%+.3e", 1.5), "\n";
echo sprintf("%+.3e", -1.5), "\n";
echo sprintf("%E", 1234.5), "\n";

echo sprintf("%g", 0), "\n";
echo sprintf("%g", 1.5), "\n";
echo sprintf("%g", 12345.6789), "\n";
echo sprintf("%g", 1234567), "\n";
echo sprintf("%g", 0.000123), "\n";
echo sprintf("%g", 1.0e-10), "\n";
echo sprintf("%.3g", 1234.5), "\n";
echo sprintf("%.5g", 1234.5), "\n";
echo sprintf("%.0g", 1234.5), "\n";
echo sprintf("%g", -123.45), "\n";
echo sprintf("%G", 12345678), "\n";

echo sprintf("%.5g", 0.0001), "\n";
echo sprintf("%.5g", 0.00001), "\n";
echo sprintf("%.5g", 100000), "\n";
echo sprintf("%.5g", 1000000), "\n";

echo printf("%d", 42), "\n";
echo printf(""), "\n";
echo printf("hello"), "\n";
echo printf("%s %d", "x", 1), "\n";

echo sprintf("%5.2f", 3.14), "\n";
echo sprintf("%-5.2f|", 3.14), "\n";
echo sprintf("%+5.2f", 3.14), "\n";
echo sprintf("%05.2f", 3.14), "\n";

echo number_format(999.999, 2), "\n";
echo number_format(0.005, 2), "\n";
echo number_format(0.025, 2), "\n";
echo number_format(0.0049, 2), "\n";

echo sprintf("%e", 1e-300), "\n";
echo sprintf("%e", 1e300), "\n";
echo sprintf("%e", PHP_FLOAT_EPSILON), "\n";

echo sprintf("%g", INF), "\n";
echo sprintf("%g", -INF), "\n";
echo sprintf("%g", NAN), "\n";

echo sprintf("[%-10.2e]", 1.5), "\n";
echo sprintf("[%+10.2e]", 1.5), "\n";
