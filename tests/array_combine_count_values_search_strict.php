<?php
print_r(array_combine(["a","b","c"], [1,2,3]));
print_r(array_combine([0,1,2], ["x","y","z"]));
print_r(array_combine([], []));

try { array_combine(["a","b"], [1,2,3]); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { array_combine(["a"], []); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { array_combine([], ["x"]); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

print_r(array_combine(["k1","k2","k1"], [1,2,3]));

print_r(array_combine([10,20,30], ["a","b","c"]));

print_r(array_count_values(["a", "b", "a", "c", "b", "a"]));
print_r(array_count_values([1, 2, 1, 3, 2, 1]));
print_r(array_count_values([1, "1", 1, "1"]));
print_r(array_count_values([]));
print_r(array_count_values(["only"]));


var_dump(array_search("b", ["a","b","c"]));
var_dump(array_search("x", ["a","b","c"]));
var_dump(array_search("b", ["a"=>1,"b"=>2]));
var_dump(array_search(2, ["a"=>1,"b"=>2]));

$arr = [0, "0", null, false, "", 1];
var_dump(array_search(0, $arr));
var_dump(array_search("0", $arr));
var_dump(array_search(false, $arr));
var_dump(array_search(null, $arr));

var_dump(array_search(0, $arr, true));
var_dump(array_search("0", $arr, true));
var_dump(array_search(false, $arr, true));
var_dump(array_search(null, $arr, true));
var_dump(array_search("", $arr, true));
var_dump(array_search(1, $arr, true));

var_dump(array_search(1.0, [1, 2, 3], true));
var_dump(array_search(1, [1.0, 2.0, 3.0], true));
var_dump(array_search(1.0, [1, 2, 3], false));

var_dump(array_search("apple", [["apple", "banana"], ["cherry"]]));
var_dump(array_search([1, 2], [[1, 2], [3, 4]]));
var_dump(array_search([1, 2], [[1, 2], [3, 4]], true));

var_dump(array_search("hello", []));

var_dump(in_array(0, ["abc", "def"]));
var_dump(in_array(0, ["abc", "def"], true));

$haystack = [10, "10", 10.0, "10.0"];
var_dump(array_search(10, $haystack));
var_dump(array_search(10, $haystack, true));
var_dump(array_search("10", $haystack, true));
var_dump(array_search(10.0, $haystack, true));


print_r(array_count_values(["1", "2", 1, 2, "1"]));

$dupes = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55];
print_r(array_count_values($dupes));

$result = array_combine(["a","b","c"], [["x","y"], ["z"], 42]);
print_r($result);

try {
    array_combine([1, "key"], [["value"]]);
    echo "no\n";
} catch (\ValueError $e) {
    echo "ve\n";
}

$arr = ["a", null, "b", null, "c"];
var_dump(array_search(null, $arr));
var_dump(array_search(null, $arr, true));

$arr = [true, "true", 1, "1"];
var_dump(array_search(true, $arr));
var_dump(array_search(true, $arr, true));

$arr = [1.5, 2.5, "1.5", 3.5];
var_dump(array_search(1.5, $arr));
var_dump(array_search(1.5, $arr, true));
var_dump(array_search("1.5", $arr, true));

$big = range(1, 100);
echo array_search(50, $big), "\n";
echo array_search(1, $big), "\n";
echo array_search(100, $big), "\n";

$nested = [[1], [2], [3]];
var_dump(array_search([2], $nested));
var_dump(array_search([4], $nested));

$arr = ["a", "b", "c", "b", "a"];
$first = array_search("b", $arr);
echo $first, "\n";

