<?php
echo array_sum([1, 2, 3, 4, 5]);
echo "\n";

echo array_product([1, 2, 3, 4]);
echo "\n";

$a = [1, 2, 3, 4, 5];
$removed = array_splice($a, 1, 2);
echo implode(',', $a);
echo "\n";
echo implode(',', $removed);
echo "\n";

$keys = ['a', 'b', 'c'];
$vals = [1, 2, 3];
$combined = array_combine($keys, $vals);
echo $combined['b'];
echo "\n";

$chunks = array_chunk([1, 2, 3, 4, 5], 2);
echo count($chunks);
echo "\n";
echo implode(',', $chunks[0]);
echo "\n";
echo implode(',', $chunks[2]);
echo "\n";

$flipped = array_flip(['a' => 1, 'b' => 2]);
echo $flipped[1];
echo "\n";
echo $flipped[2];
echo "\n";

$diff = array_diff([1, 2, 3, 4], [2, 4]);
echo implode(',', $diff);
echo "\n";

$intersect = array_intersect([1, 2, 3, 4], [2, 3, 5]);
echo implode(',', $intersect);
echo "\n";

$filled = array_fill(5, 3, 'x');
echo $filled[5] . $filled[6] . $filled[7];
echo "\n";

$fill_keys = array_fill_keys(['a', 'b', 'c'], 0);
echo $fill_keys['a'] . $fill_keys['b'] . $fill_keys['c'];
echo "\n";

$padded = array_pad([1, 2, 3], 5, 0);
echo implode(',', $padded);
echo "\n";

$counts = array_count_values(['a', 'b', 'a', 'c', 'b', 'a']);
echo $counts['a'];
echo "\n";
echo $counts['b'];
echo "\n";

$a = [1, 2, 3];
array_unshift($a, 0);
echo implode(',', $a);
echo "\n";

$dk = array_diff_key(['a' => 1, 'b' => 2, 'c' => 3], ['b' => 99]);
echo implode(',', $dk);
echo "\n";
