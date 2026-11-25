<?php

function f($a = g(new stdClass, $x, ?)) {
    return $a(1);
}

function g(string $a, int $b) {
    return [$a, $b];
}

try {
    var_dump(f());
} catch (Error $e) {
    echo $e::class, ": ", $e->getMessage(), " on line ", $e->getLine();
}

?>
