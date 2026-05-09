<?php
// array spaceship
echo [1,2,3] <=> [1,2,3], "\n"; // 0
echo [1,2] <=> [1,2,3], "\n"; // -1 (shorter)
echo [1,2,3] <=> [1,2,2], "\n"; // 1
echo [1,2,3] <=> [1,3,3], "\n"; // -1

// mixed comparison
var_dump([] <=> [1]);
var_dump(["a" => 1] <=> ["a" => 2]);
var_dump(["a" => 1, "b" => 2] <=> ["b" => 2, "a" => 1]); // same keys+values

// sort with SORT_NATURAL
$a = ["img12", "img2", "img1", "img10"];
sort($a, SORT_NATURAL);
print_r($a);
$a = ["IMG10", "img2", "IMG1", "img11"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

// array_intersect_ukey
$a = ["red" => 1, "blue" => 2, "green" => 3];
$b = ["red" => 99, "yellow" => 88];
print_r(array_intersect_ukey($a, $b, fn($x, $y) => strcmp($x, $y)));

// array_intersect_uassoc
$a = ["red" => 1, "blue" => 2];
$b = ["red" => 1, "blue" => 9];
print_r(array_intersect_uassoc($a, $b, fn($x, $y) => strcmp($x, $y)));

// array_uintersect
$a = [1, 2, 3, 4];
$b = [2, 4, 6, 8];
print_r(array_uintersect($a, $b, fn($x, $y) => $x <=> $y));

// array_udiff
$a = [1, 2, 3, 4];
$b = [2, 4];
print_r(array_udiff($a, $b, fn($x, $y) => $x <=> $y));

// array_walk return value (not used, modifies in-place)
$a = [1, 2, 3];
$r = array_walk($a, function(&$v) { $v *= 10; });
var_dump($r); // bool(true)
print_r($a);

// array_filter with truthy non-bool
$a = [0, 1, 2, "", "x", null, [], [1]];
print_r(array_filter($a, fn($v) => $v));

// count modes
$a = [1, [2, 3], [4, [5, 6]]];
echo count($a), "\n"; // 3
echo count($a, COUNT_RECURSIVE), "\n"; // 3 + 2 + 2 + 2 = ? PHP counts all elements

// is_resource and tmpfile
$f = tmpfile();
var_dump(is_resource($f)); // PHP: bool(true). zphp: ? maybe object
echo get_resource_type($f), "\n";
fclose($f);

// constant()
define("MY_CONST", 42);
echo constant("MY_CONST"), "\n";
echo defined("MY_CONST") ? "yes\n" : "no\n";
echo defined("UNKNOWN_X") ? "yes\n" : "no\n";

class K { const VAL = 100; }
echo defined("K::VAL") ? "yes\n" : "no\n";
echo constant("K::VAL"), "\n";

// function_exists for builtins
var_dump(function_exists("strlen"));
var_dump(function_exists("array_map"));
var_dump(function_exists("nonexistent_function_xyz"));

// get_defined_vars
function vars_demo() {
    $a = 1; $b = "hi"; $c = [1, 2, 3];
    return get_defined_vars();
}
print_r(vars_demo());

// spl_object_id and spl_object_hash uniqueness
$a = new stdClass; $b = new stdClass; $c = $a;
var_dump(spl_object_id($a) === spl_object_id($c));
var_dump(spl_object_id($a) !== spl_object_id($b));
echo strlen(spl_object_hash($a)), "\n"; // 32
var_dump(spl_object_hash($a) === spl_object_hash($c));
var_dump(spl_object_hash($a) !== spl_object_hash($b));
