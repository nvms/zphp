<?php
// round() as php's _php_math_round: every mode, negative and large places,
// values whose scaled form is one off as a decimal, and huge values
foreach ([1.955, 0.285, -2.5, 5.045, 1234567.891, -0.0001, 1.497769578622E+306, 3.95661191169082E-8] as $v) {
    foreach ([0, 2, -2, 23, -24] as $places) {
        $row = [];
        foreach (RoundingMode::cases() as $mode) $row[] = var_export(round($v, $places, $mode), true);
        foreach ([PHP_ROUND_HALF_UP, PHP_ROUND_HALF_DOWN, PHP_ROUND_HALF_EVEN, PHP_ROUND_HALF_ODD] as $mode) $row[] = var_export(round($v, $places, $mode), true);
        echo "$v $places: ", implode(' ', $row), "\n";
    }
}
var_dump(round(5), round(5, -1), round("3.7"));
foreach (['abc', [1], 1.5] as $bad) {
    try { var_dump(round($bad, 0, is_float($bad) ? 9 : 1)); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}
