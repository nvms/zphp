<?php
// a write through $GLOBALS reaches a global that is a reference, and every
// other name bound to it; extract(EXTR_REFS) releases the old value only
// once the variable names the element
$x = 1;
$r = &$x;
$GLOBALS["x"] = 5;
var_dump($x, $r);

$a = ["k" => 1];
$k = &$a["k"];
$GLOBALS["k"] = 7;
var_dump($a, $k);

function setFromFunction() { $GLOBALS["z"] = 3; }
$z = 0;
$rz = &$z;
setFromFunction();
var_dump($z, $rz);

class D {
    public function __destruct() {
        var_dump($GLOBALS["b"]);
        $GLOBALS["b"] = 43;
    }
}
$b = new D;
$array = ["b" => 42];
extract($array, EXTR_REFS);
var_dump($b, $array);
