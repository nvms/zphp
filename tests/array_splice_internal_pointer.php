<?php
// array_splice resets the internal pointer to the first element (php-src gh19926)
$a = [1, 2, 3];
unset($a[0]);
next($a);
var_dump(current($a));
array_splice($a, 0, 0, [999]);
var_dump(current($a));
$a = [1, 2, 3];
next($a); next($a);
array_splice($a, 2, 1);
var_dump(current($a));
$a = [1, 2, 3];
end($a);
$r = array_splice($a, 0, 1);
var_dump(current($a), key($a));
