<?php
// floats print with php's digits everywhere: echo (14 significant), var_dump,
// var_export, json_encode and serialize (shortest round trip), and powers
// are c's pow
$values = [PHP_FLOAT_MAX, -PHP_FLOAT_MAX, PHP_FLOAT_MIN, PHP_FLOAT_EPSILON, 87724174361676976.0, 324582.49435, 0.0036288879892346, 1e25, 1.5e-7, -0.0, 10.0 ** 23, 1.1 ** 400, 7 ** 30, 10 ** 23, 2 ** 63, 6.0221409e23, 1/3, 9007199254740993.0];
foreach ($values as $v) {
    echo $v, ' | ', var_export($v, true), ' | ', json_encode($v), ' | ', serialize($v), "\n";
    var_dump($v);
}
