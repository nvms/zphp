<?php
// closure operations - tests closure creation, invocation, captures
$n = 50000;

// create and call closures
$adders = [];
for ($i = 0; $i < 100; $i++) {
    $adders[] = function ($x) use ($i) { return $x + $i; };
}

$sum = 0;
for ($i = 0; $i < $n; $i++) {
    $sum += $adders[$i % 100]($i);
}

// higher-order: array_map with closure
$data = range(1, 10000);
$squared = array_map(function ($x) { return $x * $x; }, $data);
$total = array_sum($squared);

// nested closures
function compose(callable $f, callable $g): callable {
    return function ($x) use ($f, $g) { return $f($g($x)); };
}

$double = function ($x) { return $x * 2; };
$inc = function ($x) { return $x + 1; };
$doubleThenInc = compose($inc, $double);

$result = 0;
for ($i = 0; $i < $n; $i++) {
    $result += $doubleThenInc($i);
}

echo "$sum\n";
echo "$total\n";
echo "$result\n";
