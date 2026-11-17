<?php
// an element bound by a by-reference foreach and then rebound to another
// variable leaves the loop variable's reference behind
function f() {
    $a = [1, 2];
    foreach ($a as &$v) {
        $x = 'X';
        $a[0] =& $x;
        break;
    }
    $v = 'V';
    return $a;
}
var_dump(f());

function g() {
    $a = [1, 2];
    $r = &$a[1];
    $y = 'Y';
    $a[1] =& $y;
    $r = 'R';
    $y = 'Y2';
    return $a;
}
var_dump(g());

function h() {
    $a = [1, 2];
    foreach ($a as &$v) {
        $a[0] =& $a;
        $c = 5;
        $a =& $c;
        break;
    }
    unset($v);
    var_dump(gc_collect_cycles());
}
h();
echo "done\n";
