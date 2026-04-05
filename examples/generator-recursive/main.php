<?php
// covers: generators, yield from, recursive generators, nested arrays,
//   foreach with yield from, generator delegation in loops,
//   deep recursion with generators, mixed scalar and array values

// === test: recursive yield from with nested arrays ===
echo "=== recursive walk ===\n";

function walk(array $arr): Generator {
    foreach ($arr as $item) {
        if (is_array($item)) {
            yield from walk($item);
        } else {
            yield $item;
        }
    }
}

$result = [];
foreach (walk([[1]]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: deeply nested arrays ===
echo "=== deep nesting ===\n";

$result = [];
foreach (walk([1, [2, [3, [4, 5]]], 6]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: flat array (no recursion needed) ===
echo "=== flat array ===\n";

$result = [];
foreach (walk([10, 20, 30]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: maximum depth ===
echo "=== max depth ===\n";

$result = [];
foreach (walk([[[[[42]]]]]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: empty sub-arrays ===
echo "=== empty sub-arrays ===\n";

$result = [];
foreach (walk([[], [1], [], [2], []]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: recursive tree flatten ===
echo "=== tree flatten ===\n";

function flatten(array $tree): Generator {
    foreach ($tree as $key => $value) {
        if (is_array($value)) {
            yield from flatten($value);
        } else {
            yield $key => $value;
        }
    }
}

$tree = [
    'a' => 1,
    'b' => ['c' => 2, 'd' => 3],
    'e' => ['f' => ['g' => 4]],
    'h' => 5,
];

$keys = [];
$vals = [];
foreach (flatten($tree) as $k => $v) {
    $keys[] = $k;
    $vals[] = $v;
}
echo "keys: " . implode(',', $keys) . "\n";
echo "vals: " . implode(',', $vals) . "\n";

// === test: recursive generator with multiple yields per level ===
echo "=== multiple yields per level ===\n";

function expandPairs(array $arr): Generator {
    foreach ($arr as $item) {
        if (is_array($item)) {
            yield from expandPairs($item);
        } else {
            yield $item;
            yield $item * 10;
        }
    }
}

$result = [];
foreach (expandPairs([1, [2, [3]]]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: recursive with sibling arrays ===
echo "=== sibling arrays ===\n";

$result = [];
foreach (walk([[1, 2], [3, 4], [5, 6]]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: mixed nesting depths ===
echo "=== mixed depths ===\n";

$result = [];
foreach (walk([1, [2], [[3]], [[[4]]]]) as $v) {
    $result[] = $v;
}
echo implode(',', $result) . "\n";

// === test: recursive generator return values ===
echo "=== return values ===\n";

function countLeaves(array $arr): Generator {
    $count = 0;
    foreach ($arr as $item) {
        if (is_array($item)) {
            $sub = countLeaves($item);
            $subCount = yield from $sub;
            $count += $subCount;
        } else {
            yield $item;
            $count++;
        }
    }
    return $count;
}

$gen = countLeaves([1, [2, 3], [[4]]]);
$leaves = [];
foreach ($gen as $v) {
    $leaves[] = $v;
}
echo "leaves: " . implode(',', $leaves) . "\n";
echo "count: " . $gen->getReturn() . "\n";
