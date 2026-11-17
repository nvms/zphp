<?php
// php has no assert_* functions: a script may declare its own, and the
// internal function list doesn't name them
var_dump(function_exists('assert_eq'), function_exists('assert_true'));
function assert_eq($a, $b) { return $a === $b ? "equal" : "different"; }
function assert_true($v) { return $v ? "yes" : "no"; }
var_dump(assert_eq(1, 1), assert_true(0));
$internal = get_defined_functions()['internal'];
var_dump(count(array_filter($internal, fn($f) => str_starts_with($f, 'assert_'))));
