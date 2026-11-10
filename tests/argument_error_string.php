<?php
// a TypeError or ArgumentCountError about a call's argument says, as a
// string, where the function is defined

function typed(int $x) {}
function needs($a, $b) {}
class SubTypeError extends TypeError {}

foreach ([fn () => typed("x"), fn () => needs(1), fn () => throw new SubTypeError("a, called in b"), fn () => throw new TypeError("plain")] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo preg_replace('~/\S+~', 'PATH', explode("\n", (string) $e)[0]), "\n";
    }
}
