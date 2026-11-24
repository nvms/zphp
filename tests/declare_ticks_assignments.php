<?php
// php 8.6 emits no tick after a statement that is a plain or by-reference
// assignment; compound assignments and other statements still tick
function counter($label) { echo "tick $label\n"; }
register_tick_function('counter', 'a');
declare(ticks=1) {
    echo "s1\n";
    $x = 1;
    $y = &$x;
    ($z = 2);
    [$p, $q] = [1, 2];
    echo "s2\n";
    $x += 1;
    $x ??= 3;
    $x++;
    if ($x) {
        $w = 4;
    }
    echo "s3\n";
    if ($x) {
        $w .= "x";
    }
    foo($w = 5);
}
function foo($v) { echo "foo $v\n"; }
echo "end\n";
