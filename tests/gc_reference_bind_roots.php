<?php
// binding an element or property by reference to another element records no
// possible root, so the root buffer fills when php's does and the automatic
// collection frees what php's frees

function roots($label) {
    echo $label, ": ", gc_status()['roots'], "\n";
}

$a = [[1]];
$a[0][0] = &$a[0];
roots("element to its container");
$f = [[1]];
$f[0][1] = &$f[0];
roots("element to a sibling");
$g = [];
$g[] = &$g;
roots("append");
$o = new stdClass;
$o->self = &$o;
$p = [[1]];
$o->p = &$p[0];
roots("property");

$a = $f = $g = $o = $p = null;
gc_collect_cycles();

$x = array();
for ($i = 0; $i < 9999; $i++) {
    $x[$i] = array(array());
    $x[$i][0] = & $x[$i];
}
var_dump(gc_collect_cycles());
unset($x);
var_dump(gc_collect_cycles());
$x = array();
for ($i = 0; $i < 10001; $i++) {
    $x[$i] = array(array());
    $x[$i][0] = & $x[$i];
}
var_dump(gc_collect_cycles());
// the 10001st root fills the buffer: 10000 are collected automatically
unset($x);
var_dump(gc_collect_cycles());
