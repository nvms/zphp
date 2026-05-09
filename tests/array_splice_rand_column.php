<?php
// array_splice insert with replacement
$a = [1, 2, 3, 4, 5];
$removed = array_splice($a, 2, 2, ["X", "Y", "Z"]);
print_r($removed);
print_r($a);

// array_splice remove all
$a = [1, 2, 3, 4, 5];
$removed = array_splice($a, 0);
print_r($removed);
print_r($a);

// array_splice negative offset
$a = [1, 2, 3, 4, 5];
array_splice($a, -2);
print_r($a); // [1, 2, 3]

// array_splice with negative length
$a = [1, 2, 3, 4, 5];
array_splice($a, 1, -1, ["X"]);
print_r($a); // [1, X, 5]

// array_splice preserves string keys in replacement
$a = [1, 2, 3];
array_splice($a, 1, 1, ["a" => 100, "b" => 200]);
print_r($a); // PHP: [1, 100, 200, 3] - string keys discarded

// array_splice replacement is single value
$a = [1, 2, 3];
array_splice($a, 1, 1, "hello");
print_r($a); // [1, "hello", 3]

// array_slice preserve_keys
$a = [10 => "a", 20 => "b", 30 => "c", 40 => "d"];
print_r(array_slice($a, 1, 2));
print_r(array_slice($a, 1, 2, true));

// array_slice with sequential numeric
$a = [1, 2, 3, 4, 5];
print_r(array_slice($a, 1, 3));
print_r(array_slice($a, 1, 3, true));

// array_rand with count
$a = [10, 20, 30, 40, 50];
$picks = array_rand($a, 3);
echo is_array($picks) ? count($picks) : "not-array", "\n";
echo count($picks) === 3 ? "ok" : "fail", "\n";
$pick = array_rand($a);
echo is_int($pick) ? "int" : "not", "\n";

// array_count_values strings + ints (mix)
print_r(array_count_values([1, "1", 2, "2", 1])); // PHP: {1: 2, "1": 1, 2: 1, "2": 1} 
// strict separation: int 1 and string "1" are different keys

// array_column missing key
$rows = [
    ["id" => 1, "name" => "x"],
    ["id" => 2],   // missing name
    ["id" => 3, "name" => "z"],
];
print_r(array_column($rows, "name"));
print_r(array_column($rows, "name", "id"));
print_r(array_column($rows, "missing"));
print_r(array_column($rows, null));   // returns rows as-is
print_r(array_column($rows, null, "id"));

// array_search with object equality
class O { public int $v; public function __construct(int $v) { $this->v = $v; } }
$a = new O(1); $b = new O(2); $c = new O(1);
$arr = [$a, $b, $c];
$found = array_search($a, $arr);
var_dump($found); // 0 (a found at index 0)
$found = array_search($a, $arr, true);
var_dump($found); // 0 (strict identity)
$found = array_search($c, $arr); // loose: c matches a (same prop value)
var_dump($found);
$found = array_search($c, $arr, true); // strict: c only matches itself
var_dump($found);

// in_array with object
var_dump(in_array($a, $arr));
var_dump(in_array($a, $arr, true));
var_dump(in_array($c, $arr));
var_dump(in_array($c, $arr, true));

// array_combine string + int keys
print_r(array_combine([1, "two", 3.5, true, "four"], ["a", "b", "c", "d", "e"]));

// str_pad with pad string longer than gap
echo str_pad("x", 5, "abcdefghij"), "|\n"; // gap=4, pad="abcd"
echo str_pad("x", 3, "abcdefghij"), "|\n"; // gap=2
echo str_pad("xxx", 8, "ab"), "|\n"; // gap=5: "ababa"
echo str_pad("xxx", 8, "ab", STR_PAD_LEFT), "|\n";
echo str_pad("xxx", 8, "ab", STR_PAD_BOTH), "|\n"; // 2 left, 3 right

// str_repeat with large count (skip the absolute extreme, use moderate)
echo strlen(str_repeat("a", 1000)), "\n";
echo strlen(str_repeat("ab", 500)), "\n";
echo str_repeat("a", 1) === "a" ? "ok" : "fail", "\n";
