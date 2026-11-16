<?php
// an unserialized array holding a cycle stays alive while it is still an
// operand, and its cycle is collected once its variable is gone
$a = [1, [2, 3]];
$a[2] = &$a;
$s = serialize($a);

function f($x, $n) {
    var_dump($n);
    var_dump($x[1]);
    var_dump(count($x[2][2]));
}
f(unserialize($s), gc_collect_cycles());

$b = unserialize($s);
var_dump(gc_collect_cycles());
unset($b);
var_dump(gc_collect_cycles());

unserialize($s);
var_dump(gc_collect_cycles());

var_dump(count([unserialize($s), gc_collect_cycles()][0][2]));
