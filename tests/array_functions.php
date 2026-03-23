<?php
$a = [3, 1, 2];
sort($a);
echo implode(',', $a);
echo "\n";

rsort($a);
echo implode(',', $a);
echo "\n";

echo implode('-', ['a', 'b', 'c']);
echo "\n";

$parts = explode(',', 'one,two,three');
echo count($parts);
echo "\n";
echo $parts[1];
echo "\n";

echo in_array(2, [1, 2, 3]) ? 'true' : 'false';
echo "\n";
echo in_array(5, [1, 2, 3]) ? 'true' : 'false';
echo "\n";

$keys = array_keys(['a' => 1, 'b' => 2, 'c' => 3]);
echo implode(',', $keys);
echo "\n";

$vals = array_values(['x' => 10, 'y' => 20]);
echo implode(',', $vals);
echo "\n";

$rev = array_reverse([1, 2, 3]);
echo implode(',', $rev);
echo "\n";

$merged = array_merge([1, 2], [3, 4]);
echo implode(',', $merged);
echo "\n";

$sliced = array_slice([10, 20, 30, 40, 50], 1, 3);
echo implode(',', $sliced);
echo "\n";

echo array_key_exists('name', ['name' => 'PHP', 'ver' => 8]) ? 'true' : 'false';
echo "\n";
echo array_key_exists('missing', ['name' => 'PHP']) ? 'true' : 'false';
echo "\n";

echo array_search(20, [10, 20, 30]);
echo "\n";

$r = range(1, 5);
echo implode(',', $r);
echo "\n";

$unique = array_unique([1, 2, 2, 3, 3, 3]);
echo implode(',', $unique);
echo "\n";

$mapped = array_map(function($x) { return $x * 2; }, [1, 2, 3]);
echo implode(',', $mapped);
echo "\n";

$filtered = array_filter([1, 2, 3, 4, 5, 6], function($x) { return $x % 2 == 0; });
echo implode(',', $filtered);
echo "\n";

$truthyOnly = array_filter([0, 1, false, 'yes', '', null]);
echo count($truthyOnly);
echo "\n";

$s = [5, 3, 4, 1, 2];
usort($s, function($a, $b) { return $a - $b; });
echo implode(',', $s);
echo "\n";

$words = ['banana', 'apple', 'cherry'];
usort($words, function($a, $b) { return $a <=> $b; });
echo implode(',', $words);
echo "\n";
