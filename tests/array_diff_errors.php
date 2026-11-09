<?php
// argument checking of the array_diff and array_intersect families: counts,
// callbacks (checked before the arrays) and array types, in php's order

$cmp = fn($a, $b) => $a <=> $b;
$functions = [
    'array_diff', 'array_diff_key', 'array_diff_assoc', 'array_diff_ukey', 'array_diff_uassoc',
    'array_udiff', 'array_udiff_assoc', 'array_udiff_uassoc',
    'array_intersect', 'array_intersect_key', 'array_intersect_assoc', 'array_intersect_ukey',
    'array_intersect_uassoc', 'array_uintersect', 'array_uintersect_assoc', 'array_uintersect_uassoc',
];
$cases = [
    'nothing' => [],
    'one array' => [['a']],
    'one int' => [42],
    'array then int' => [['a'], 7],
    'string first' => ['list', ['a']],
    'two arrays' => [['a'], ['b']],
    'unknown function name' => [['a'], ['b'], 'no_such_function'],
    'int before a bad callback' => [['a'], 7, 'no_such_function'],
    'arrays and a closure' => [['a'], ['b'], $cmp],
    'arrays and two closures' => [['a'], ['b'], $cmp, $cmp],
    'null in the middle' => [['a'], null, $cmp, $cmp],
    'object as array' => [['a'], new ArrayObject([1]), $cmp],
    'callback array of three' => [['a'], ['b'], [1, 2, 3]],
    'float callback' => [['a'], ['b'], 1.5],
    'empty first array' => [[], 5],
    'bool after arrays' => [['a'], ['a'], false],
    'method that does not exist' => [['a'], ['b'], 'ArrayObject::nope'],
];
foreach ($functions as $fn) {
    echo "== $fn\n";
    foreach ($cases as $label => $args) {
        try {
            $result = $fn(...$args);
            echo "$label: ", json_encode($result), "\n";
        } catch (Throwable $e) {
            echo "$label: ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}

echo "== callbacks run while sorting, before a later argument's type error\n";
try {
    array_udiff([3, 1, 2], [5, 4], 'oops', function ($a, $b) {
        echo "cmp($a, $b) ";
        return $a <=> $b;
    });
} catch (TypeError $e) {
    echo "\n", $e->getMessage(), "\n";
}

echo "== objects without __toString cannot be compared as strings\n";
try {
    array_diff([new stdClass()], ['x']);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    array_intersect(['x', 'y'], [new ArrayObject()]);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    array_diff_assoc(['k' => fn() => 1], ['k' => 'v']);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
