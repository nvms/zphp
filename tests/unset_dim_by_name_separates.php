<?php
// unset($v[k]) on a variable known by name (a global, a closure's
// by-reference use) separates the array from its other holders first

function closureUse() {
    $h = [1, 2, 3];
    $copy = $h;
    $f = function () use (&$h) {
        unset($h[0]);
        unset($h[5]);
    };
    $f();
    var_dump($copy, $h);
}
closureUse();

$g = ['a' => [1, 2], 'b' => 2];
$gc = $g;
$inner = $g['a'];
function viaGlobal() {
    global $g;
    unset($g['a'][0]);
    unset($g['b']);
}
viaGlobal();
var_dump($gc, $inner, $g);

// a missing or non-array variable is left for the unset to judge
function missing() {
    global $nothing, $str;
    unset($nothing[0]);
    var_dump($nothing);
    try {
        unset($str[0]);
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
$str = "abc";
missing();
