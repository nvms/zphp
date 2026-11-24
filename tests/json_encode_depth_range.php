<?php
// json_encode's $depth must fit in a C int; values outside used to wrap
foreach ([PHP_INT_MAX, PHP_INT_MIN, 2147483648, -2147483649, 4294967297, 2147483647, -2147483648, 0, -1, 1] as $depth) {
    try {
        var_dump(json_encode([[1]], 0, $depth));
        echo json_last_error_msg(), "\n";
    } catch (ValueError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    json_encode([1], depth: 1 << 40);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
