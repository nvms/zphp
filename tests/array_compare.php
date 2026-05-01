<?php

// length-based ordering
echo ([1, 2] <=> [1, 2, 3]) . "\n"; // -1
echo ([1, 2, 3] <=> [1, 2]) . "\n"; // 1
echo ([] <=> []) . "\n"; // 0
echo ([] <=> [1]) . "\n"; // -1

// element-by-element when same length
echo ([1, 2, 3] <=> [1, 2, 3]) . "\n"; // 0
echo ([1, 2, 3] <=> [1, 2, 4]) . "\n"; // -1
echo ([2, 1] <=> [1, 1]) . "\n"; // 1
echo ([1] <=> [2]) . "\n"; // -1

// associative: missing key on the other side
echo (['a' => 1] <=> ['b' => 1]) . "\n"; // 1 (uncomparable, php returns 1)

// element types
echo (['a' => 1] <=> ['a' => 2]) . "\n"; // -1
echo (['a' => 1, 'b' => 2] <=> ['a' => 1, 'b' => 2]) . "\n"; // 0

// nested
echo ([[1, 2]] <=> [[1, 3]]) . "\n"; // -1

// usort with arrays
$rows = [['n' => 3], ['n' => 1], ['n' => 2]];
usort($rows, fn($a, $b) => $a <=> $b);
foreach ($rows as $r) echo $r['n'] . " ";
echo "\n";

// array vs scalar (always scalar < array)
echo (1 <=> [1]) . "\n"; // -1
echo ([1] <=> 1) . "\n"; // 1
