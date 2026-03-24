<?php
// comprehensive math function sweep

echo abs(-5) . "\n";
echo abs(5) . "\n";
echo floor(4.7) . "\n";
echo ceil(4.2) . "\n";
echo round(4.5) . "\n";
echo round(4.4) . "\n";
echo round(3.14159, 2) . "\n";

echo min(1, 2, 3) . "\n";
echo max(1, 2, 3) . "\n";
echo min([5, 3, 8, 1]) . "\n";
echo max([5, 3, 8, 1]) . "\n";

echo pow(2, 10) . "\n";
echo sqrt(144) . "\n";
echo log(M_E) . "\n";
echo log(8, 2) . "\n";
echo log10(1000) . "\n";

echo intdiv(7, 2) . "\n";
echo fmod(7.5, 3.2) . "\n";

echo base_convert("ff", 16, 10) . "\n";
echo decbin(42) . "\n";
echo bindec("101010") . "\n";
echo dechex(255) . "\n";
echo hexdec("ff") . "\n";
echo decoct(8) . "\n";
echo octdec("10") . "\n";

echo var_export(is_finite(42.0), true) . "\n";
echo var_export(is_finite(INF), true) . "\n";
echo var_export(is_infinite(INF), true) . "\n";
echo var_export(is_nan(NAN), true) . "\n";
echo var_export(is_nan(42.0), true) . "\n";

// trig
echo round(sin(0), 10) . "\n";
echo round(cos(0), 10) . "\n";
echo round(tan(0), 10) . "\n";
echo round(M_PI, 5) . "\n";

echo deg2rad(180) . "\n";
echo rad2deg(M_PI) . "\n";

echo hypot(3, 4) . "\n";

echo "done\n";
