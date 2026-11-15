<?php
// a value where the callee takes a reference is an Error: $GLOBALS itself
// (a read-only copy since php 8.1) and literals sent to a closure or a
// function named by a variable

$lambda = function (&$x) { return ++$x; };
function by_ref(&$ref) { return 'by_ref ran'; }
function by_val($v) { return count($v) > 0 ? 'by_val ran' : 'empty'; }

function run() {
    global $lambda;
    $y = 1;
    $name = 'by_ref';
    $calls = [
        fn () => $lambda(1),
        fn () => $GLOBALS['lambda'](1),
        fn () => $name(2),
        fn () => by_ref($GLOBALS),
        fn () => by_ref(1),
        fn () => array_splice($GLOBALS, 0, 1),
        fn () => end($GLOBALS),
        fn () => later($GLOBALS),
        fn () => by_val($GLOBALS),
        fn () => by_ref($GLOBALS['lambda']),
        fn () => $lambda($y) . " $y",
    ];
    foreach ($calls as $i => $call) {
        try {
            var_dump($call());
        } catch (Error $e) {
            echo "$i: ", str_replace(__FILE__, 'FILE', $e->getMessage()), "\n";
        }
    }
}
function later(&$ref) {}
run();
