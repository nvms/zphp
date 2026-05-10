<?php
// array_push/pop on assoc
$a = ["x" => 1, "y" => 2];
$n = array_push($a, "added");
echo $n, "\n";
print_r($a); // x=>1, y=>2, 0=>"added"

echo array_pop($a), "\n";
print_r($a);

// array_pop on empty
$a = [];
var_dump(array_pop($a));

// array_unshift on assoc - prepends int keys, keeps string keys
$a = ["b" => 2, "c" => 3];
$n = array_unshift($a, "front");
echo $n, "\n";
print_r($a); // 0=>front, b=>2, c=>3

// array_shift on assoc - returns first, renumbers numeric
$a = ["a" => 1, "b" => 2, "c" => 3];
echo array_shift($a), "\n";
print_r($a); // b=>2, c=>3 (string keys kept)

$a = [10, 20, 30, "x" => "X"];
echo array_shift($a), "\n";
print_r($a); // 0=>20, 1=>30, x=>X (numeric reindexed, string kept)

// array_slice negative offset+length
$a = [1, 2, 3, 4, 5];
print_r(array_slice($a, -2)); // [4, 5]
print_r(array_slice($a, -3, 2)); // [3, 4]
print_r(array_slice($a, 1, -1)); // [2, 3, 4] (stop before last)
print_r(array_slice($a, -3, -1)); // [3, 4]
print_r(array_slice($a, 0, -100)); // []

// preserve_keys
print_r(array_slice([10, 20, 30], 1, 2, true));
print_r(array_slice(["a"=>1, "b"=>2, "c"=>3], 1, 2)); // string keys preserved

// array_splice with length 0 (insert)
$a = [1, 2, 3, 4];
$removed = array_splice($a, 2, 0, ["X", "Y"]);
print_r($a); // 1, 2, X, Y, 3, 4
print_r($removed); // []

// array_splice with full replacement
$a = [1, 2, 3, 4];
array_splice($a, 1, 2, ["A", "B", "C"]);
print_r($a); // 1, A, B, C, 4

// negative offset
$a = [1, 2, 3, 4, 5];
$removed = array_splice($a, -2);
print_r($removed); // [4, 5]
print_r($a); // [1, 2, 3]

// negative length
$a = [1, 2, 3, 4, 5];
array_splice($a, 1, -1);
print_r($a); // [1, 5]

// range char
print_r(range("a", "e"));
echo count(range("a", "z")), "\n"; // 26
echo count(range("A", "Z")), "\n"; // 26

// range with float step over int
print_r(range(0, 5, 1.5));

// range descending negative
print_r(range(5, 0, -1));

// array_search returns key (preserves type: int or string)
$a = ["a" => "x", "b" => "y", 0 => "z"];
var_dump(array_search("y", $a));
var_dump(array_search("nope", $a));

// strict
var_dump(array_search("0", [0, 1, 2]));
var_dump(array_search("0", [0, 1, 2], true)); // false (strict)

// array_keys filtering
$a = [1, 2, 1, 3, 1];
print_r(array_keys($a, 1));

// array_keys default returns all keys
print_r(array_keys(["a"=>1, "b"=>2]));

// in_array strict variants
var_dump(in_array(1, ["1"]));
var_dump(in_array(1, ["1"], true));
var_dump(in_array("1", [1]));
var_dump(in_array("1", [1], true));

// array_count_values
print_r(array_count_values(["a", "b", "a", "c", "b", "a"]));

// array_column on objects with method-like keys
class Row {
    public function __construct(public string $name, public int $age) {}
}
$rows = [new Row("a", 1), new Row("b", 2)];
print_r(array_column($rows, "name"));
print_r(array_column($rows, "age", "name"));

// array_chunk preserve_keys
$a = ["a" => 1, "b" => 2, "c" => 3, "d" => 4];
print_r(array_chunk($a, 2));        // re-indexed
print_r(array_chunk($a, 2, true));  // preserved

// edge: chunk size larger than array
print_r(array_chunk([1, 2], 5));

// array_pad pos and neg sizes
print_r(array_pad([1, 2, 3], 5, 0));      // pad right: 1,2,3,0,0
print_r(array_pad([1, 2, 3], -5, 0));     // pad left: 0,0,1,2,3
print_r(array_pad([1, 2, 3], 2, 0));      // no pad
print_r(array_pad([], 3, "x"));           // pad empty

// array_fill
print_r(array_fill(0, 3, "a"));
print_r(array_fill(5, 3, "b")); // start at 5
print_r(array_fill(-3, 3, "c")); // PHP 8+: negative start kept

// array_fill_keys
print_r(array_fill_keys(["a", "b", "c"], 0));
print_r(array_fill_keys([1, 2, 3], "default"));

// array_merge behavior with int keys reindexes
print_r(array_merge([1, 2], [3, 4]));
print_r(array_merge([1=>"a", 2=>"b"], [1=>"x"]));   // string-keyed: later wins; int-keyed: appended (renumbered)

// array_combine duplicate keys
print_r(array_combine([1, 2, 1], ["a", "b", "c"])); // 2=>b, 1=>c (last wins)

// array_search returns first match
$a = ["a", "b", "c", "b"];
var_dump(array_search("b", $a)); // 1
