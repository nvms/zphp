<?php
// covers: array_merge_recursive vs array_replace_recursive, array_walk_recursive,
//   array_diff_key/assoc, array_intersect variants, array_combine, array_column,
//   array_chunk, array_fill_keys, array_flip with edge cases

echo "=== array_merge_recursive: collisions become arrays ===\n";
$a = ['user' => ['name' => 'Alice', 'tags' => ['admin']]];
$b = ['user' => ['email' => 'a@x.y', 'tags' => ['editor']]];
print_r(array_merge_recursive($a, $b));

echo "\n=== array_replace_recursive: deep override ===\n";
$base = ['config' => ['debug' => false, 'log' => ['level' => 'warn', 'path' => '/var/log']]];
$override = ['config' => ['debug' => true, 'log' => ['level' => 'debug']]];
print_r(array_replace_recursive($base, $override));

echo "\n=== array_walk_recursive ===\n";
$data = ['x' => 1, 'nested' => ['y' => 2, 'deeper' => ['z' => 3]]];
array_walk_recursive($data, function (&$v) { $v *= 10; });
print_r($data);

echo "\n=== array_diff_key vs array_diff_assoc ===\n";
$a = ['a' => 1, 'b' => 2, 'c' => 3];
$b = ['a' => 1, 'b' => 99, 'd' => 4];
echo "diff_key (keys only): " . implode(',', array_keys(array_diff_key($a, $b))) . "\n";
echo "diff_assoc (key + val): ";
print_r(array_diff_assoc($a, $b));

echo "\n=== array_intersect family ===\n";
echo "intersect values: ";
print_r(array_intersect([1, 2, 3, 4], [3, 4, 5, 6]));
echo "intersect_key: ";
print_r(array_intersect_key(['a' => 1, 'b' => 2, 'c' => 3], ['b' => 0, 'c' => 99, 'd' => 1]));

echo "\n=== array_combine ===\n";
$keys = ['name', 'age', 'role'];
$vals = ['Alice', 30, 'admin'];
print_r(array_combine($keys, $vals));

echo "\n=== array_column ===\n";
$records = [
    ['id' => 1, 'name' => 'Alice',  'dept' => 'eng'],
    ['id' => 2, 'name' => 'Bob',    'dept' => 'eng'],
    ['id' => 3, 'name' => 'Carol',  'dept' => 'sales'],
];
echo "names: " . implode(',', array_column($records, 'name')) . "\n";
echo "keyed by id:\n";
print_r(array_column($records, 'name', 'id'));
echo "rows by id:\n";
print_r(array_column($records, null, 'id'));

echo "\n=== array_chunk preserving keys ===\n";
$data = ['a' => 1, 'b' => 2, 'c' => 3, 'd' => 4, 'e' => 5];
print_r(array_chunk($data, 2, true));

echo "\n=== array_fill_keys ===\n";
print_r(array_fill_keys(['x', 'y', 'z'], 0));

echo "\n=== array_flip ===\n";
print_r(array_flip(['a' => 1, 'b' => 2, 'c' => 3]));
$dups = array_flip(['a' => 1, 'b' => 1, 'c' => 2]);
echo "dup keys collapse: 1 => $dups[1], 2 => $dups[2]\n";

echo "\n=== array_unique modes ===\n";
$a = [1, '1', 2, '2', 1, 2];
echo "regular: " . implode(',', array_unique($a, SORT_REGULAR)) . "\n";
echo "strict (string): " . implode(',', array_unique($a, SORT_STRING)) . "\n";

echo "\n=== array_map with keys preserved ===\n";
$a = ['a' => 1, 'b' => 2, 'c' => 3];
$squared = array_map(fn($v) => $v * $v, $a);
print_r($squared);

echo "\n=== array_filter with ARRAY_FILTER_USE_BOTH ===\n";
$a = ['alice' => 30, 'bob' => 17, 'carol' => 25, 'dave' => 12];
$adults_v = array_filter($a, fn($age) => $age >= 18);
$adults_k = array_filter($a, fn($age, $name) => $age >= 18 and strlen($name) <= 5, ARRAY_FILTER_USE_BOTH);
echo "adults (value): " . implode(',', array_keys($adults_v)) . "\n";
echo "adults + short name: " . implode(',', array_keys($adults_k)) . "\n";

echo "\n=== array_reduce ===\n";
$nums = [1, 2, 3, 4, 5];
echo "sum: " . array_reduce($nums, fn($carry, $v) => $carry + $v, 0) . "\n";
echo "concat: " . array_reduce(['a','b','c'], fn($c, $v) => $c . $v, '') . "\n";

echo "\n=== array_search ===\n";
echo "search bob: " . array_search('bob', ['alice','bob','carol']) . "\n";
echo "search missing: " . var_export(array_search('zoe', ['alice','bob']), true) . "\n";

echo "\n=== compact / extract ===\n";
$name = 'Alice';
$age = 30;
$role = 'admin';
$out = compact('name', 'age', 'role');
print_r($out);
extract(['x' => 100, 'y' => 200, 'z' => 300]);
echo "after extract: x=$x y=$y z=$z\n";

echo "\ndone\n";
