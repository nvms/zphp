<?php
// zend_call_function: a callback's by-reference parameter given a plain
// value warns and works on a temporary (internal functions too), while an
// array element that is a reference is passed as that reference
function by_ref(&$arg) { $arg = "changed"; }
function by_val($arg) { $arg = "changed"; }

$a = [3, 1, 2];
var_dump(call_user_func("sort", $a), $a);
var_dump(call_user_func_array("sort", [$a]), $a);
var_dump(call_user_func_array("rsort", [&$a]), $a);
var_dump(call_user_func("shuffle", [1]));

$arg = ["original"];
call_user_func_array("by_ref", $arg);
var_dump($arg);

$arg = ["original"];
$ref = &$arg[0];
call_user_func_array("by_ref", $arg);
var_dump($arg, $ref);

$arg = ["original"];
$ref2 = &$arg[0];
call_user_func_array("by_val", $arg);
var_dump($arg);

$x = 1;
$y = 2;
call_user_func_array(function (&$p, $q, &$r) { $p = 10; $r = 30; }, [&$x, $y, 5]);
var_dump($x, $y);

var_dump(array_map("by_ref", [1]));
usort($a, function (&$l, &$r) { return $l <=> $r; });
var_dump($a);
