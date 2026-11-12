<?php
// naming the same parameter twice is an Error once the second one is passed

function f($a = 0, $b = 0) { return "$a $b"; }

try {
    echo f(a: 1, a: 2), "\n";
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    echo f(b: 1, a: 2, b: 3), "\n";
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    echo str_pad(string: 'x', length: 3, string: 'y'), "\n";
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
echo f(b: 1, a: 2), "\n";
