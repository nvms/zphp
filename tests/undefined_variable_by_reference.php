<?php
// variables that are written, not read, never warn: by-reference arguments of
// natives (which define them as null even when left unwritten), the source of
// =&, a variable returned by reference, and empty() over a nullsafe chain
function &f() { return ($a); }
$h =& f();
$x =& $y;
var_dump($y);
var_dump(empty($foo?->bar), empty($foo?->bar->baz));
settype($v, "int");
var_dump($v);
sscanf(":59:58", "%s:%d:%f", $p, $q, $r);
var_dump($p, $q, $r);
function g() {
    sscanf("x", "%d", $a);
    var_dump($a);
}
g();
// a variable variable bound into an array by reference
$b = "a";
$a = [1];
${$b}[] =& $$b;
${$b}[] =& $$b;
${$b}[0] = 2;
echo $a[1][0], $a[2][0], $a[1][2][1][0], "\n";
$n = "m";
$arr = [];
$arr["k"] =& $$n;
$arr[] =& ${"w"};
$m = 5;
$w = 6;
$arr["k"] = 7;
echo $m, $arr[0], "\n";
