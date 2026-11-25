<?php
function f($a, &$b = null, $c = 1) { var_dump(func_get_args()); }
$g = f(1, c: ?);
$g(3);
function h($a, $b = 5, $c = 1) { var_dump(func_get_args(), func_num_args()); }
$k = h(1, c: ?);
$k(3);
$k2 = h(c: ?, a: 9);
$k2(4);
