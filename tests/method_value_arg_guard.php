<?php
class ValueArgReader {
    function take($v) { echo $v, "\n"; }
}
class ValueArgWriter {
    function take(&$v) { $v += 10; }
}
class ValueArgMagic {
    function __call($name, $args) { echo $name, ':', $args[0], "\n"; }
}
function invokeValueArg($receiver, &$values) {
    $receiver->take($values['x']);
}
$a = ['x' => 1];
$copy = $a;
$r = new ValueArgReader;
$w = new ValueArgWriter;
foreach ([$r, $r, $w, $w, $r, $r, new ValueArgMagic, $r] as $receiver) {
    invokeValueArg($receiver, $a);
}
echo $a['x'], ':', $copy['x'], "\n";
class ValueArgProperty {
    public private(set) int $x = 7;
}
function invokePropertyArg($receiver, $box) { $receiver->take($box->x); }
$box = new ValueArgProperty;
invokePropertyArg($r, $box);
invokePropertyArg($r, $box);
try { invokePropertyArg($w, $box); } catch (Error $e) { echo $e->getMessage(), "\n"; }
echo $box->x, "\n";
