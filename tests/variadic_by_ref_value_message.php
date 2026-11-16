<?php
// a variadic parameter has no name in "could not be passed by reference"
function all(&...$args) {}
function some($x, &...$rest) {}
function named(&$x) {}
foreach ([fn() => all(1), fn() => some(1, 2, 3), fn() => named(1)] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    sscanf("1", "%d", 5);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
