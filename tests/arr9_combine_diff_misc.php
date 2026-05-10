<?php
// array_combine empty
print_r(array_combine([], []));

// length mismatch error
try { array_combine([1, 2], [1]); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// array_combine with bool/null/float keys (cast to int/string)
$r = array_combine([true, false, null, 1.5, 1.9], ["a", "b", "c", "d", "e"]);
print_r($r);

// array_combine with negative int keys
print_r(array_combine([-1, -2, -3], ["a", "b", "c"]));

// duplicate keys
print_r(array_combine([1, 2, 1], ["a", "b", "c"])); // last "a" wins → 1=>"c", 2=>"b"

// array_diff with mixed types (loose comparison)
print_r(array_diff([1, "1", 2, true], [1])); // PHP 8: int 1 matches "1" loosely
print_r(array_diff(["a", "b", "c"], ["a"])); // ["b", "c"]

// array_diff with objects: PHP throws (can't convert to string), zphp accepts (architectural)

// array_intersect strict (no array_intersect_strict, but test with non-loose alt)
print_r(array_intersect([1, "1", 1.0, true], [1])); // loose: all match

// in_array loose vs strict
var_dump(in_array(0, ["abc"])); // false (PHP 8: strict comparison for int vs str)
var_dump(in_array("abc", [0])); // false (string-vs-int strict in PHP 8)
var_dump(in_array("1", [1])); // true (loose: int 1 == "1")
var_dump(in_array("1", [1], true)); // false (strict)
var_dump(in_array(1, ["1"])); // true (loose)
var_dump(in_array(1, ["1"], true)); // false (strict)
var_dump(in_array(true, [1])); // true (loose: 1 == true)
var_dump(in_array(true, ["yes"])); // true (loose: bool cast non-empty string is true)
var_dump(in_array(0, ["false"])); // false (PHP 8 strict numeric vs string)
var_dump(in_array("", [null])); // true (loose: "" == null)
var_dump(in_array(null, [0, "", false, null])); // true (loose)
var_dump(in_array(null, [0, "", false, null], true)); // true (strict matches null)
var_dump(in_array(0, [null], true)); // false

// array_diff_assoc strict
print_r(array_diff_assoc(["a" => 1, "b" => 2], ["a" => "1", "b" => 2])); // a (different value type? actually loose)

// array_unique with SORT_STRING
$arr = [1, "1", 1.0, true];
print_r(array_unique($arr, SORT_STRING));
print_r(array_unique($arr, SORT_REGULAR));

// array_search loose
var_dump(array_search(1, ["1", "2", "3"])); // 0 (loose)
var_dump(array_search(1, ["1", "2", "3"], true)); // false (strict)
var_dump(array_search("3", [1, 2, 3])); // 2 (loose)

// PHP comparison rules for arrays
$a = ["x", "y", "z"];
$b = ["x", "y", "z"];
$c = ["x", "y", "Z"];
var_dump($a == $b);
var_dump($a === $b);
var_dump($a == $c);
var_dump($a == [...$b]); // copy

$d = ["a"=>1, "b"=>2];
$e = ["b"=>2, "a"=>1]; // diff order, same keys/values
var_dump($d == $e); // true (loose: any order)
var_dump($d === $e); // false (order matters strictly)

// nested array equality
$x = ["a" => [1, 2]];
$y = ["a" => [1, 2]];
var_dump($x == $y);
var_dump($x === $y);

// array_merge with empty
print_r(array_merge([], [1, 2]));
print_r(array_merge([1, 2], []));
print_r(array_merge(["a"=>1], ["a"=>2])); // a=>2 (later wins)

// + operator preserves first
print_r([1, 2, 3] + [4, 5, 6, 7]); // 0,1,2 from first, 3 from second

// array_diff_assoc with int keys
print_r(array_diff_assoc([1, 2, 3], [1, 9, 3])); // 1=>2 (different val)

// array_intersect_key
print_r(array_intersect_key(["a"=>1, "b"=>2], ["b"=>9, "c"=>3]));

// array_diff_key
print_r(array_diff_key(["a"=>1, "b"=>2, "c"=>3], ["b"=>9]));
