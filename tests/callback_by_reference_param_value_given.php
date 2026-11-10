<?php
// an internal function that calls back with values warns for each
// by-reference parameter, and the call still runs
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
$a = [3, 1, 2];
usort($a, function (&$x, &$y) { return $x <=> $y; });
var_dump($a);
function cmp(&$k1, $k2) { return strcmp($k1, $k2); }
$b = ["b" => 1, "a" => 2];
uksort($b, "cmp");
var_dump($b);
var_dump(array_map(function (&$v) { return $v * 2; }, [1, 2]));
var_dump(call_user_func(function (&$v) { return $v; }, 5));
var_dump(array_filter([1, 0, 2], function (&$v) { return $v; }));
$walked = [1, 2];
array_walk($walked, function (&$v, $k) { $v *= 10; });
var_dump($walked);
