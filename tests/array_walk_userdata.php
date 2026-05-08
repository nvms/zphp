<?php
// userdata passed as 3rd arg
$a = [1, 2, 3];
array_walk($a, function(&$v, $k, $u) { $v = $v * $u + $k; }, 10);
print_r($a);

// recursive with userdata
$b = [1, [2, [3]], 4];
array_walk_recursive($b, function(&$v, $k, $u) { $v = "$u-$v"; }, 'p');
print_r($b);

// no userdata: callback receives only 2 args
$c = [1, 2];
$out = [];
array_walk($c, function(&$v, $k) use (&$out) { $out[] = "$k:$v"; $v = $v * 2; });
print_r($out);
print_r($c);

// callback unsetting other entries during walk should not crash
$f = [1,2,3,4];
array_walk($f, function(&$v, $k) use (&$f) { unset($f[2]); $v = $v * 10; });
print_r($f);

// array_diff_assoc and array_intersect_assoc use string-cast comparison
print_r(array_diff_assoc(['a' => 0], ['a' => false]));
print_r(array_diff_assoc(['a' => 0], ['a' => '0']));
print_r(array_intersect_assoc(['a' => 1, 'b' => 2], ['a' => '1', 'b' => 2]));
print_r(array_intersect_assoc(['a' => 0], ['a' => false]));

// str_contains with empty needle
var_dump(str_contains("abc", ""));
var_dump(str_contains("", ""));
var_dump(str_starts_with("abc", ""));
var_dump(str_ends_with("abc", ""));
