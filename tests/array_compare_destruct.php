<?php
// array_replace_recursive
print_r(array_replace_recursive(
    ["a" => 1, "b" => ["c" => 2, "d" => 3]],
    ["a" => 99, "b" => ["c" => 50]],
    ["b" => ["e" => 100]]
));
print_r(array_replace_recursive(
    ["x" => [1, 2, 3]],
    ["x" => [10, 20]]
));
// scalar replaces deeply
print_r(array_replace_recursive(["a" => ["b" => 1]], ["a" => 99]));

// array_merge_recursive
print_r(array_merge_recursive(
    ["a" => 1, "b" => [1, 2]],
    ["a" => 2, "b" => [3, 4]]
));
print_r(array_merge_recursive(
    ["color" => ["red", "blue"]],
    ["color" => ["green"]]
));
print_r(array_merge_recursive(
    ["k" => "first"],
    ["k" => "second"]
)); // becomes array

// list() destructure
$a = [1, 2, 3];
[$x, $y, $z] = $a;
echo "$x $y $z\n";
[, $y, ] = $a;
echo "skip:$y\n";
list($x, $y, $z) = $a;
echo "list:$x $y $z\n";

// array destructure with keys
$h = ["name" => "Alice", "age" => 30, "city" => "NYC"];
["name" => $n, "age" => $a] = $h;
echo "$n,$a\n";
["age" => $a, "city" => $c] = $h;
echo "$a $c\n";

// nested destructure
$data = ["user" => ["name" => "Bob", "info" => ["age" => 25]]];
["user" => ["name" => $name, "info" => ["age" => $age]]] = $data;
echo "$name $age\n";

// destructure with default-like via ?? after
$r = ["a" => 1];
["a" => $a, "b" => $b] = $r + ["b" => 99];
echo "$a $b\n";

// foreach destructure
$rows = [["id" => 1, "name" => "x"], ["id" => 2, "name" => "y"]];
foreach ($rows as ["id" => $id, "name" => $name]) {
    echo "$id=$name ";
}
echo "\n";
foreach ([[1, 2], [3, 4]] as [$a, $b]) echo "$a/$b ";
echo "\n";

// array_combine empty
print_r(array_combine([], []));

// array_walk_recursive on objects (objects not recursed into - they're leaves)
$d = ["a" => (object)["x" => 1, "y" => 2], "b" => [1, 2]];
array_walk_recursive($d, function(&$v) { if (is_int($v)) $v *= 10; });
print_r($d);

// array_count_values
print_r(array_count_values([1, 2, 1, 3, "a", "a", 2, 2]));

// in_array strict
var_dump(in_array(1, [1.0, 2.0, 3.0])); // loose: true
var_dump(in_array(1, [1.0, 2.0, 3.0], true)); // strict: 1 !== 1.0 -> false
var_dump(in_array(1, [1, 2, 3], true));
var_dump(in_array(null, [0, false, ""], true));
var_dump(in_array(null, [0, false, "", null], true));

// array_search strict null
var_dump(array_search(null, [0, false, ""]));
var_dump(array_search(null, [0, false, "", null], true));
var_dump(array_search(null, [0, false, ""], true));

// ksort SORT_NATURAL
$a = ["item10" => 1, "item2" => 2, "item1" => 3];
ksort($a, SORT_NATURAL);
print_r($a);

// asort SORT_NATURAL
$b = ["x" => "img10", "y" => "img2", "z" => "img1"];
asort($b, SORT_NATURAL);
print_r($b);

// SORT_REGULAR with mixed types
$a = [10, "5", 2, "abc", 100, "20"];
sort($a, SORT_REGULAR);
print_r($a);

// array_multisort with two arrays
$keys = [3, 1, 2];
$vals = ["c", "a", "b"];
array_multisort($keys, $vals);
print_r($keys);
print_r($vals);

// reverse multisort
$a = [3, 1, 4, 1, 5];
$b = ["c", "a", "d", "b", "e"];
array_multisort($a, SORT_DESC, $b);
print_r($a);
print_r($b);

// array_chunk with preserve_keys assoc
print_r(array_chunk(["a" => 1, "b" => 2, "c" => 3, "d" => 4], 2, true));
print_r(array_chunk(["a" => 1, "b" => 2, "c" => 3, "d" => 4], 2, false));
