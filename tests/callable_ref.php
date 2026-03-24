<?php

// basic function reference
$fn = strlen(...);
echo $fn("hello") . "\n";       // 5

$upper = strtoupper(...);
echo $upper("world") . "\n";    // WORLD

// pass as callback to array_map
$result = array_map(strtoupper(...), ["a", "b", "c"]);
echo implode(",", $result) . "\n"; // A,B,C

// pass to usort
$arr = [3, 1, 2];
usort($arr, function($a, $b) { return $a - $b; });
echo implode(",", $arr) . "\n"; // 1,2,3

// assign and call later
$trim = trim(...);
echo $trim("  hi  ") . "\n";    // hi

echo "done\n";
