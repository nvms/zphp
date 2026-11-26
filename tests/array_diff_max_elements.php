<?php
$arr = range(0, 2**20);
try {
    array_diff(...array_fill(0, 2**12, $arr));
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
var_dump(array_diff([1, 2, 3], [2]));
