<?php
// regression: PHP 8.1 collects named arguments that match no declared
// parameter into a variadic parameter, keyed by name. zphp threw
// "Unknown named parameter" instead.

function collect(...$args) { return $args; }

// all-named into a pure variadic
print_r(collect(a: 1, b: 2, c: 3));

// mixed positional + named into a pure variadic
print_r(collect(1, 2, x: 9));

// empty and all-positional still work
print_r(collect());
print_r(collect(7, 8, 9));

// fixed params plus a variadic: named args matching a fixed param bind
// there, the rest fall into the variadic
function mixed(int $a, int $b, ...$rest) {
    return ['a' => $a, 'b' => $b, 'rest' => $rest];
}
print_r(mixed(1, 2, extra: 99, more: 88));
print_r(mixed(b: 20, a: 10, tag: 'x'));
print_r(mixed(1, 2, 3, 4, named: 5));
print_r(mixed(1, 2));

// named args that DO match declared parameters still work unchanged
function declared(int $x, int $y, int $z = 0) { return "$x,$y,$z"; }
echo declared(y: 2, x: 1), "\n";
echo declared(1, z: 9, y: 5), "\n";

// a typed variadic still type-checks its elements, including named extras:
// a numeric string coerces, an incompatible value throws TypeError
function typed(int ...$nums) { return array_sum($nums); }
echo typed(a: 1, b: 2, c: 3), "\n";
echo typed(a: "4", b: "5"), "\n";
try {
    typed(bad: [1, 2]);
    echo "no error\n";
} catch (TypeError $e) {
    echo "typed variadic rejected an array\n";
}

// argument unpacking of an associative array into a variadic
$opts = ['first' => 1, 'second' => 2];
print_r(collect(...$opts));
