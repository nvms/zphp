<?php
// regression: unset() on a plain (slot-backed) variable makes isset()/empty()/
// ?? see it as gone. previously unset_var only removed the name from the
// frame's dynamic vars map but left the slot-backed copy in frame.locals, so
// isset() still found the old value and reported the variable as set.

$a = 10;
echo isset($a) ? "1:set\n" : "1:unset\n";
unset($a);
echo isset($a) ? "2:set\n" : "2:unset\n";

// inside a function (slot-backed local)
function f() {
    $local = 5;
    unset($local);
    return isset($local) ? 'set' : 'unset';
}
echo "fn: ", f(), "\n";

// empty() after unset
$e = 'value';
unset($e);
echo empty($e) ? "empty\n" : "notempty\n";

// ?? coalesce after unset
$c = 'present';
unset($c);
echo ($c ?? 'fallback'), "\n";

// re-assigning after unset works
$r = 1;
unset($r);
$r = 'reborn';
echo $r, "\n";

// unset multiple variables in one call
$x = 1; $y = 2; $z = 3;
unset($x, $y);
echo (isset($x) ? 'x' : '-'), (isset($y) ? 'y' : '-'), (isset($z) ? 'z' : '-'), "\n";

// unset a reference variable breaks the binding without touching the target
$orig = 100;
$ref = &$orig;
unset($ref);
echo $orig, " ", (isset($ref) ? 'ref-set' : 'ref-gone'), "\n";

// array-element unset still works (was already correct)
$arr = ['k' => 1, 'm' => 2];
unset($arr['k']);
echo (isset($arr['k']) ? 'k' : '-'), (isset($arr['m']) ? 'm' : '-'), "\n";

// unset in a foreach loop body
$nums = [10, 20, 30, 40];
foreach ($nums as $i => $n) {
    if ($n % 20 === 0) unset($nums[$i]);
}
echo implode(',', $nums), "\n";
