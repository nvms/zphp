<?php
// array functions copy a referenced element as a reference while another
// name still holds it, as php's do, and as a plain value otherwise
$a = 1;
$b = 2;
$c = "x";
$arr = [&$a, "k" => &$b, 3, "s" => &$c];

var_dump(array_values($arr));
var_dump(array_slice($arr, 1));
var_dump(array_slice($arr, 1, 2, true));
var_dump(array_merge($arr, ["k" => 9, &$a]));
var_dump(array_merge_recursive($arr, [5]));
var_dump(array_replace($arr, [1 => 7]));
var_dump(array_chunk($arr, 2));
var_dump(array_chunk($arr, 3, true));
var_dump(array_reverse($arr));
var_dump(array_filter($arr));
var_dump(array_filter($arr, fn($v) => $v !== 3));
var_dump(array_unique([&$a, &$a, 1, &$c]));
var_dump(array_unique([&$a, 1.0, true], SORT_REGULAR));
var_dump(array_map(null, $arr));
var_dump(array_map(null, [&$a, 5], [&$b]));
var_dump(preg_grep('/^\d$/', $arr));
var_dump(preg_grep('/^\d$/', $arr, PREG_GREP_INVERT));

// writes through the copies reach the variables, and the other way round
$v = array_values($arr);
$v[0] = 100;
$a = 101;
var_dump($v[0], $a);

// a reference only the array holds is copied as a value
$only = [1, 2];
$r = &$only[0];
unset($r);
var_dump(array_values($only));

// array_splice moves references into the removed array and inserts the
// replacement's references as references
$n = [0, 1, 2, 3, 4, 5, 6];
$in = [0, &$n[1], "two" => &$n[2], 3, &$n[4]];
$removed = array_splice($in, 1, 2, [&$n[5], 9]);
var_dump($removed, $in);
$n[1] = "one";
$n[5] = "five";
var_dump($removed, $in);

// a string-keyed duplicate replaces the reference it overwrites
var_dump(array_merge(["k" => &$a], ["k" => 2]));
