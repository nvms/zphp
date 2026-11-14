<?php
// an array already evaluated as an operand (a sent argument) keeps its
// value when a later operand writes to the variable it came from, as php's
// operands hold their own reference

function two($x, $y) { echo json_encode($x), " ", json_encode($y), "\n"; }

$x = [1, 2, 3];
function appendGlobal() { global $x; $x[] = 9; return 0; }
two($x, appendGlobal());
two($x, $x);

function byRef(&$r) { $r[0] = 'changed'; return 1; }
$y = ['orig'];
two($y, byRef($y));
two($y, 0);

class Holder {
    public $p = [1];
    public static $s = [1];
    function add() { $this->p[] = 2; self::$s[] = 2; return 0; }
}
$c = new Holder;
two($c->p, $c->add());
two(Holder::$s, Holder::$s[] = 3);

$z = [1];
two($z, $z[] = 5);
$w = ['a' => [1]];
two($w['a'], $w['a'][] = 2);
two($w, $w['a']['b'] = 3);

$h = [1, 2];
function unsetGlobal() { global $h; unset($h[0]); return 0; }
two($h, unsetGlobal());

$j = [1];
$jr = &$j;
two($j, $jr[] = 2);
two($jr, $j[] = 3);

function staticList() { static $a = [1]; $a[] = count($a) + 1; return $a; }
two(staticList(), staticList());

$n = ['x' => 1];
two($n, $n['x'] += 5);
two($n, $n['x']++);

// a write whose value comes from a call still lands in the variable
$a = [0, [0]];
function f() { global $a; $a[] = 'f'; return 'v'; }
$a[0] = f();
$a[1][0] = f();
$a[] = f();
$a[1][] = f();
echo json_encode($a), "\n";

// by-reference arguments and by-reference natives still write in place
function setRef(&$v) { $v = 9; }
$b = [1, [2]];
setRef($b[0]);
setRef($b[1][0]);
$sort = [3, 1, 2];
sort($sort);
$walk = [1, 2, 3];
array_walk($walk, function (&$v) { $v *= 2; });
$push = [1];
two(array_push($push, 2), $push);
echo json_encode([$b, $sort, $walk]), "\n";
// an array passed by reference is the variable, not a copy: a later
// by-reference argument into it doesn't separate them
function bothRef(&$whole, &$part) { var_dump($whole); $part = 5; var_dump($whole); }
$c = [1];
bothRef($c, $c[0]);
$dyn = 'bothRef';
$e = [1, [2]];
$dyn($e, $e[1][0]);
var_dump($e);

// a by-reference foreach that appends sees its own writes
$d = [1, 2, 3];
foreach ($d as $k => &$v) {
    $v *= 10;
    if ($k == 0) $d[] = 4;
}
unset($v);
echo json_encode($d), "\n";

// deep recursion with arrays on the stack
function deep($n, $arr) {
    if ($n == 0) {
        $arr[] = 'leaf';
        return $arr;
    }
    $r = deep($n - 1, [$arr, $n]);
    return is_array($r) ? count($r) : $r + 1;
}
echo deep(50, ['root']), "\n";
