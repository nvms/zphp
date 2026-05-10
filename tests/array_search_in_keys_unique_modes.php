<?php
$arr = ["a", "b", "c", "d"];
var_dump(array_search("b", $arr));
var_dump(array_search("x", $arr));
var_dump(array_search("a", $arr));

$arr = ["x"=>1, "y"=>2, "z"=>3];
var_dump(array_search(2, $arr));
var_dump(array_search(99, $arr));

$arr = [0, "0", false, null, "", 1];
var_dump(array_search(0, $arr));
var_dump(array_search("0", $arr));
var_dump(array_search(false, $arr));
var_dump(array_search(null, $arr));
var_dump(array_search(0, $arr, true));
var_dump(array_search("0", $arr, true));
var_dump(array_search(false, $arr, true));
var_dump(array_search(null, $arr, true));
var_dump(array_search("", $arr, true));

var_dump(in_array(0, ["abc", "def"]));
var_dump(in_array(0, ["abc", "def"], true));
var_dump(in_array("0", [0, 1, 2]));
var_dump(in_array("0", [0, 1, 2], true));
var_dump(in_array(1, ["1", "2", "3"]));
var_dump(in_array(1, ["1", "2", "3"], true));
var_dump(in_array("1.0", [1.0, 2.0]));
var_dump(in_array("1.0", [1.0, 2.0], true));

$arr = [1, 2, 3, 2, 1];
print_r(array_keys($arr));
print_r(array_keys($arr, 2));
print_r(array_keys($arr, "2"));
print_r(array_keys($arr, "2", true));
print_r(array_keys($arr, 99));

$arr = [0, "0", false, null, "", 1];
print_r(array_keys($arr, 0));
print_r(array_keys($arr, 0, true));
print_r(array_keys($arr, false, true));
print_r(array_keys($arr, null, true));

$arr = ["a"=>1, "b"=>2, "c"=>1];
print_r(array_keys($arr, 1));
print_r(array_keys($arr));

print_r(array_values([10,20,30]));
print_r(array_values(["a"=>1,"b"=>2,"c"=>3]));
print_r(array_values([5=>"a",10=>"b",15=>"c"]));
print_r(array_values([]));

$mixed = ["k"=>1, 5=>"a", 0=>"b", "x"=>2];
print_r(array_values($mixed));

print_r(array_unique([1,2,2,3,3,3,4]));
print_r(array_unique(["a","b","a","c","b"]));
print_r(array_unique([1,"1",1.0,true]));
print_r(array_unique([1,"1",1.0,true], SORT_STRING));
print_r(array_unique([1,"1",1.0,true], SORT_NUMERIC));
print_r(array_unique([1,"1",1.0,true], SORT_REGULAR));

print_r(array_unique([10,1,2,10,1]));
print_r(array_unique([10,1,2,10,1], SORT_NUMERIC));

print_r(array_unique(["b","a","B","A"]));
print_r(array_unique(["b","a","B","A"], SORT_STRING));

print_r(array_unique([]));

print_r(array_unique(["k1"=>1, "k2"=>2, "k3"=>1, "k4"=>3]));
print_r(array_unique([1.5, "1.5", "1.50", 2]));

$arr = ["a", 1, "1", true, false, null];
print_r(array_unique($arr, SORT_STRING));
print_r(array_unique($arr, SORT_REGULAR));

$arr = [1.5, 2.5, "1.5", 1.5, 2.5];
print_r(array_unique($arr));
print_r(array_unique($arr, SORT_NUMERIC));
print_r(array_unique($arr, SORT_STRING));

print_r(array_search("b", []));
print_r(in_array("x", []));
print_r(array_keys([]));
print_r(array_keys([], "x"));

$arr = [[1,2], [3,4], [1,2]];
var_dump(array_search([1,2], $arr));
var_dump(in_array([3,4], $arr));
var_dump(in_array([3,4], $arr, true));
