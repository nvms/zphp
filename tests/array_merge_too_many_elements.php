<?php
// array_merge() counts the elements first and refuses a result past the
// most a php array holds, before building anything
$arr = range(0, 2 ** 20 - 1);
try {
    array_merge(...array_fill(0, 2 ** 10, $arr));
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(count(array_merge($arr, [1, 2])));
