<?php
// (object) on a generator or a fiber gives the same object back
function gen() {
    yield 1;
    yield 2;
}
$g = gen();
$o = (object) $g;
var_dump($o === $g, $o instanceof Generator, get_class($o));
foreach ($o as $v) var_dump($v);
$f = new Fiber(function () { return 3; });
$fo = (object) $f;
var_dump($fo === $f, get_class($fo));
$fo->start();
var_dump($f->getReturn());

$gen1 = gen();
$gen2 = (object) $gen1;
foreach ($gen1 as $v1) {
    foreach ($gen2 as $v2) {
        break 2;
    }
}
unset($gen1);
foreach ($gen2 as $v) var_dump($v);
