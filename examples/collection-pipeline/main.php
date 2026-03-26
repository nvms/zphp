<?php
// covers: array_map, array_filter, array_reduce, array_walk, usort, uksort,
// uasort, array_combine, array_column, array_keys, array_values, compact,
// extract, array_unique, array_flip, array_reverse, array_slice, array_splice,
// array_chunk, array_merge, array_pad, array_fill, in_array, array_search,
// array_sum, array_product, array_count_values, array_intersect, array_diff,
// closures as callbacks, arrow functions

// test 1: map/filter/reduce chain
echo "=== Test 1: Map/Filter/Reduce ===\n";
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$doubled = array_map(fn($n) => $n * 2, $numbers);
echo "Doubled: " . implode(', ', $doubled) . "\n";

$evens = array_filter($numbers, fn($n) => $n % 2 === 0);
echo "Evens: " . implode(', ', $evens) . "\n";

$sum = array_reduce($numbers, fn($carry, $item) => $carry + $item, 0);
echo "Sum: $sum\n";

$evenSum = array_reduce(
    array_filter($numbers, fn($n) => $n % 2 === 0),
    fn($carry, $item) => $carry + $item,
    0
);
echo "Even sum: $evenSum\n";

// test 2: array_walk with modification
echo "\n=== Test 2: Array Walk ===\n";
$prices = ['apple' => 1.50, 'banana' => 0.75, 'cherry' => 2.00];
array_walk($prices, function(&$price, $key) {
    $price = round($price * 1.1, 2);
});
foreach ($prices as $item => $price) {
    echo "$item: $price\n";
}

// test 3: sorting functions
echo "\n=== Test 3: Sorting ===\n";
$data = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
usort($data, fn($a, $b) => $a - $b);
echo "Sorted: " . implode(', ', $data) . "\n";

usort($data, fn($a, $b) => $b - $a);
echo "Reverse: " . implode(', ', $data) . "\n";

$assoc = ['banana' => 2, 'apple' => 1, 'cherry' => 3];
uksort($assoc, fn($a, $b) => strcmp($a, $b));
echo "Key sorted: ";
foreach ($assoc as $k => $v) echo "$k=$v ";
echo "\n";

uasort($assoc, fn($a, $b) => $b - $a);
echo "Value sorted (preserve keys): ";
foreach ($assoc as $k => $v) echo "$k=$v ";
echo "\n";

// test 4: array_combine and array_column
echo "\n=== Test 4: Combine and Column ===\n";
$keys = ['name', 'age', 'city'];
$values = ['Alice', 30, 'NYC'];
$person = array_combine($keys, $values);
echo "Person: ";
foreach ($person as $k => $v) echo "$k=$v ";
echo "\n";

$people = [
    ['name' => 'Alice', 'age' => 30, 'city' => 'NYC'],
    ['name' => 'Bob', 'age' => 25, 'city' => 'LA'],
    ['name' => 'Charlie', 'age' => 35, 'city' => 'Chicago'],
];
$names = array_column($people, 'name');
echo "Names: " . implode(', ', $names) . "\n";

$byName = array_column($people, null, 'name');
echo "Bob's age: " . $byName['Bob']['age'] . "\n";

// test 5: compact and extract
echo "\n=== Test 5: Compact/Extract ===\n";
$name = "Alice";
$age = 30;
$city = "NYC";
$data = compact('name', 'age', 'city');
echo "Compact: ";
foreach ($data as $k => $v) echo "$k=$v ";
echo "\n";

$record = ['color' => 'blue', 'size' => 'large', 'count' => 42];
extract($record);
echo "Extract: color=$color, size=$size, count=$count\n";

// test 6: set operations
echo "\n=== Test 6: Set Operations ===\n";
$a = [1, 2, 3, 4, 5];
$b = [3, 4, 5, 6, 7];
echo "Intersect: " . implode(', ', array_intersect($a, $b)) . "\n";
echo "Diff (a-b): " . implode(', ', array_diff($a, $b)) . "\n";
echo "Diff (b-a): " . implode(', ', array_diff($b, $a)) . "\n";
echo "Union: " . implode(', ', array_unique(array_merge($a, $b))) . "\n";

// test 7: array manipulation
echo "\n=== Test 7: Array Manipulation ===\n";
$arr = [1, 2, 3, 4, 5];
echo "Reverse: " . implode(', ', array_reverse($arr)) . "\n";
echo "Slice(1,3): " . implode(', ', array_slice($arr, 1, 3)) . "\n";
echo "Chunk(2): ";
$chunks = array_chunk($arr, 2);
foreach ($chunks as $chunk) {
    echo "[" . implode(',', $chunk) . "] ";
}
echo "\n";

echo "Pad to 8: " . implode(', ', array_pad($arr, 8, 0)) . "\n";
echo "Fill(0,5,x): " . implode(', ', array_fill(0, 5, 'x')) . "\n";

// test 8: search and count
echo "\n=== Test 8: Search and Count ===\n";
$fruits = ['apple', 'banana', 'cherry', 'banana', 'date', 'banana'];
echo "Has banana: " . (in_array('banana', $fruits) ? 'yes' : 'no') . "\n";
echo "Has grape: " . (in_array('grape', $fruits) ? 'yes' : 'no') . "\n";
echo "Search cherry: " . array_search('cherry', $fruits) . "\n";
echo "Sum [1..5]: " . array_sum([1, 2, 3, 4, 5]) . "\n";
echo "Product [1..5]: " . array_product([1, 2, 3, 4, 5]) . "\n";

$counts = array_count_values($fruits);
echo "Banana count: " . $counts['banana'] . "\n";

// test 9: flip and unique
echo "\n=== Test 9: Flip and Unique ===\n";
$map = ['a' => 1, 'b' => 2, 'c' => 3];
$flipped = array_flip($map);
echo "Flipped: ";
foreach ($flipped as $k => $v) echo "$k=$v ";
echo "\n";

$dupes = [1, 2, 2, 3, 3, 3, 4];
echo "Unique: " . implode(', ', array_unique($dupes)) . "\n";

// test 10: keys and values
echo "\n=== Test 10: Keys/Values ===\n";
$data = ['x' => 10, 'y' => 20, 'z' => 30];
echo "Keys: " . implode(', ', array_keys($data)) . "\n";
echo "Values: " . implode(', ', array_values($data)) . "\n";

// test 11: nested map/filter with closures
echo "\n=== Test 11: Nested Callbacks ===\n";
$words = ['hello', 'world', 'foo', 'bar', 'baz', 'php'];
$result = array_map(
    'strtoupper',
    array_filter($words, fn($w) => strlen($w) > 3)
);
echo "Long words upper: " . implode(', ', $result) . "\n";

// test 12: array_map with keys via array_keys
echo "\n=== Test 12: Map with Keys ===\n";
$inventory = ['apples' => 5, 'bananas' => 12, 'cherries' => 3];
$labels = array_map(
    fn($k, $v) => "$k: $v",
    array_keys($inventory),
    array_values($inventory)
);
echo implode(', ', $labels) . "\n";

// test 13: complex pipeline
echo "\n=== Test 13: Complex Pipeline ===\n";
$students = [
    ['name' => 'Alice', 'grade' => 92],
    ['name' => 'Bob', 'grade' => 78],
    ['name' => 'Charlie', 'grade' => 95],
    ['name' => 'Diana', 'grade' => 88],
    ['name' => 'Eve', 'grade' => 61],
];

$honorRoll = array_filter($students, fn($s) => $s['grade'] >= 85);
usort($honorRoll, fn($a, $b) => $b['grade'] - $a['grade']);
$names = array_map(fn($s) => $s['name'] . " (" . $s['grade'] . ")", $honorRoll);
echo "Honor roll: " . implode(', ', $names) . "\n";

$avg = array_sum(array_column($students, 'grade')) / count($students);
echo "Class average: " . round($avg, 1) . "\n";

// test 14: splice
echo "\n=== Test 14: Splice ===\n";
$arr = ['a', 'b', 'c', 'd', 'e'];
$removed = array_splice($arr, 1, 2, ['x', 'y', 'z']);
echo "After splice: " . implode(', ', $arr) . "\n";
echo "Removed: " . implode(', ', $removed) . "\n";

echo "\nAll collection pipeline tests passed!\n";
