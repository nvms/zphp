<?php

// ref captures in closures called from native callback functions

// array_walk
$result = [];
$nums = [1, 2, 3];
array_walk($nums, function($val, $key) use (&$result) {
    $result[] = "$key:$val";
});
echo implode(', ', $result) . "\n";

// array_map
$collected = [];
array_map(function($v) use (&$collected) {
    $collected[] = $v * 2;
    return $v;
}, [10, 20, 30]);
echo implode(', ', $collected) . "\n";

// array_filter
$seen = [];
array_filter([1, 2, 3, 4, 5], function($v) use (&$seen) {
    $seen[] = $v;
    return $v % 2 === 0;
});
echo implode(', ', $seen) . "\n";

// usort
$comparisons = 0;
$arr = [3, 1, 2];
usort($arr, function($a, $b) use (&$comparisons) {
    $comparisons++;
    return $a <=> $b;
});
echo implode(', ', $arr) . " (cmp: $comparisons)\n";

// array_reduce
$steps = [];
$sum = array_reduce([1, 2, 3, 4], function($carry, $item) use (&$steps) {
    $steps[] = "$carry+$item";
    return $carry + $item;
}, 0);
echo "sum=$sum steps=" . implode(', ', $steps) . "\n";

// call_user_func
$counter = 0;
$inc = function() use (&$counter) { $counter++; };
call_user_func($inc);
call_user_func($inc);
call_user_func($inc);
echo "counter=$counter\n";

// nested ref captures
$log = [];
$outer = function($label) use (&$log) {
    $log[] = "start:$label";
    $inner = [1, 2];
    array_walk($inner, function($v) use (&$log, $label) {
        $log[] = "$label:$v";
    });
    $log[] = "end:$label";
};
$outer("a");
$outer("b");
echo implode(', ', $log) . "\n";

// ref capture with array_walk modifying the value
$data = ['hello', 'world'];
$upper = [];
array_walk($data, function($val) use (&$upper) {
    $upper[] = strtoupper($val);
});
echo implode(' ', $upper) . "\n";

// multiple ref captures
$evens = [];
$odds = [];
$numbers = [1, 2, 3, 4, 5, 6];
array_walk($numbers, function($v) use (&$evens, &$odds) {
    if ($v % 2 === 0) {
        $evens[] = $v;
    } else {
        $odds[] = $v;
    }
});
echo "evens=" . implode(',', $evens) . " odds=" . implode(',', $odds) . "\n";
