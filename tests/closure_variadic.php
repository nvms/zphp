<?php

// closure with variadic params receives all args
$f = function (...$args) { return count($args); };
echo $f(1, 2, 3) . "\n"; // 3
echo $f() . "\n"; // 0
echo $f('only') . "\n"; // 1

// arrow function variadic
$g = fn(...$args) => array_sum($args);
echo $g(1, 2, 3, 4, 5) . "\n"; // 15

// closure with fixed + variadic
$h = function (string $prefix, ...$rest) {
    return $prefix . ":" . implode(",", $rest);
};
echo $h('tag', 'a', 'b', 'c') . "\n";

// wrap pattern (the one that broke before)
function wrap(callable $fn): callable {
    return function (...$args) use ($fn) {
        return $fn(...$args);
    };
}
$add = wrap(fn($a, $b) => $a + $b);
echo $add(2, 3) . "\n";

// closure called with array unpack
$concat = function (...$parts) { return implode('-', $parts); };
$arr = ['x', 'y', 'z'];
echo $concat(...$arr) . "\n";

// nested wraps don't lose args
$logger = function ($d) {};
$timed = function (callable $fn, callable $logger): callable {
    return function (...$args) use ($fn, $logger) {
        $result = $fn(...$args);
        $logger($result);
        return $result;
    };
};
$timedAdd = $timed(fn($a, $b, $c) => $a + $b + $c, $logger);
echo $timedAdd(1, 2, 3) . "\n";

// closure with reference + variadic
$increments = [];
$incAll = function (int ...$nums) use (&$increments) {
    foreach ($nums as $n) $increments[] = $n + 1;
};
$incAll(1, 2, 3);
$incAll(10, 20);
echo count($increments) . "\n";
print_r($increments);
