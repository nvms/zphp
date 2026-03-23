<?php

// sin/cos/tan
echo round(sin(0), 10) . "\n";
echo round(sin(M_PI / 2), 10) . "\n";
echo round(cos(0), 10) . "\n";
echo round(cos(M_PI), 10) . "\n";
echo round(tan(0), 10) . "\n";

// inverse trig
echo round(asin(1), 10) . "\n";
echo round(acos(1), 10) . "\n";
echo round(atan(1), 10) . "\n";
echo round(atan2(1, 1), 10) . "\n";

// hyperbolic
echo round(sinh(0), 10) . "\n";
echo round(cosh(0), 10) . "\n";
echo round(tanh(0), 10) . "\n";

// deg2rad / rad2deg
echo round(deg2rad(180), 10) . "\n";
echo round(rad2deg(M_PI), 10) . "\n";

// hypot
echo round(hypot(3, 4), 10) . "\n";

// is_finite / is_infinite / is_nan
echo var_export(is_finite(1.0), true) . "\n";
echo var_export(is_finite(INF), true) . "\n";
echo var_export(is_infinite(INF), true) . "\n";
echo var_export(is_nan(NAN), true) . "\n";
echo var_export(is_nan(1.0), true) . "\n";
