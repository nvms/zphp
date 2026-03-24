<?php

// regression: __DIR__ in closures/functions resolved to "." instead of file dir
// because sub-compilers didn't inherit file_path from parent

$top = __DIR__;

function getDir() {
    return __DIR__;
}

$closure = function() {
    return __DIR__;
};

$arrow = fn() => __DIR__;

echo ($top === getDir() ? "match" : "mismatch") . "\n";
echo ($top === $closure() ? "match" : "mismatch") . "\n";
echo ($top === $arrow() ? "match" : "mismatch") . "\n";

// nested closure
$nested = function() {
    return (function() {
        return __DIR__;
    })();
};
echo ($top === $nested() ? "match" : "mismatch") . "\n";
