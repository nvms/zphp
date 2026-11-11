<?php
declare(strict_types=1);
// in a strict file an internal function's scalar parameter takes only its
// own type (an int for a float), and a callback an internal function calls
// stays weak

$one = 1;
$calls = [
    fn() => str_repeat("ab", 2),
    fn() => str_repeat("ab", "2"),
    fn() => str_repeat("ab", 2.0),
    fn() => strlen(12),
    fn() => strlen(null),
    fn() => round(5, 1),
    fn() => sqrt(4),
    fn() => in_array(1, [1], $GLOBALS["one"]),
    fn() => substr("abc", 1, null),
    fn() => array_filter([1, 0], "boolval"),
    fn() => array_map('strlen', [1, 22]),
];
foreach ($calls as $i => $call) {
    try {
        echo "$i: ", var_export($call(), true), "\n";
    } catch (Throwable $e) {
        echo "$i: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
