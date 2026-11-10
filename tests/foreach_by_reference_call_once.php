<?php
// a foreach by reference over a call evaluates the call once
function f() { echo "f called\n"; return [1, 2, 3]; }
foreach (f() as &$v) { $v *= 2; echo $v, "\n"; }
unset($v);
class O { public $a = [1, 2]; function arr() { echo "arr called\n"; return $this->a; } }
$o = new O;
foreach ($o->arr() as $k => &$v) { echo "$k $v\n"; }
