<?php
// ints compare exactly, even where floats cannot tell them apart
var_dump(PHP_INT_MIN + 1 <=> PHP_INT_MIN);
var_dump(PHP_INT_MAX <=> PHP_INT_MAX - 1);
var_dump([PHP_INT_MAX] == [PHP_INT_MAX - 1]);
var_dump([PHP_INT_MAX] <=> [PHP_INT_MAX - 1]);
var_dump(max(PHP_INT_MIN * 2, PHP_INT_MIN, PHP_INT_MIN + 1));
var_dump(min([PHP_INT_MAX, PHP_INT_MAX - 1]));
$a = [PHP_INT_MAX, PHP_INT_MAX - 1, PHP_INT_MAX - 2];
sort($a);
var_dump($a);
var_dump(in_array(PHP_INT_MAX - 1, [PHP_INT_MAX]));
var_dump(array_search(PHP_INT_MAX, [PHP_INT_MAX - 1, PHP_INT_MAX]));
var_dump(1 <=> 1.5, 2 <=> 1.5, 1.0 <=> 1);
