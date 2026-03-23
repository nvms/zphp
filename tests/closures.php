<?php

// closure assigned to variable
$add = function($a, $b) { return $a + $b; };
echo $add(3, 4) . "\n";

// closure passed to higher-order function
function apply($fn, $val) { return $fn($val); }
$double = function($x) { return $x * 2; };
echo apply($double, 5) . "\n";

// arrow function
$sq = fn($x) => $x * $x;
echo $sq(6) . "\n";

// array_map with closure
$nums = [1, 2, 3, 4, 5];
$doubled = array_map(function($x) { return $x * 2; }, $nums);
echo implode(',', $doubled) . "\n";

// array_map with arrow function
$plus10 = array_map(fn($x) => $x + 10, [10, 20, 30]);
echo implode(',', $plus10) . "\n";

// array_filter with closure
$even = array_filter($nums, function($x) { return $x % 2 == 0; });
echo implode(',', $even) . "\n";

// array_filter without callback (truthy filter)
$mixed = [0, 1, '', 'hello', null, 42];
$truthy = array_filter($mixed);
echo count($truthy) . "\n";

// usort
$arr = [3, 1, 4, 1, 5];
usort($arr, function($a, $b) { return $a - $b; });
echo implode(',', $arr) . "\n";

// named function as string callback
function triple($x) { return $x * 3; }
$tripled = array_map('triple', [1, 2, 3]);
echo implode(',', $tripled) . "\n";

// inline closure call
echo (function($x) { return $x + 1; })(99) . "\n";

// use clause - single var
$x = 10;
$addX = function($y) use ($x) { return $x + $y; };
echo $addX(5) . "\n";

// use clause - multiple vars
$first = 'hello';
$second = ' world';
$concat = function() use ($first, $second) { return $first . $second; };
echo $concat() . "\n";

// use captures at creation time, not call time
$val = 1;
$getVal = function() use ($val) { return $val; };
$val = 99;
echo $getVal() . "\n";

// use with array_map
$factor = 5;
$scaled = array_map(function($n) use ($factor) { return $n * $factor; }, [1, 2, 3]);
echo implode(',', $scaled) . "\n";
