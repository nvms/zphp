<?php
// a by-reference foreach holds the reference to the variable it iterates:
// the loop goes on over that array when the variable is rebound, keeps it
// alive, and lets it go when the loop ends or an exception leaves it
$a = [0, 1];
foreach($a as &$v) {
    $a[0] =& $a;
    $a[1] = array();
    $a[1][0] =& $a[1];
    $b = 1;
    $a =& $b;
    var_dump(gc_collect_cycles());
    break;
}
var_dump(gc_collect_cycles());

$x = [1, 2, 3];
foreach ($x as $k => &$v) {
    echo $k, ":", $v, "\n";
    if ($k == 0) { $y = [7, 8, 9, 10]; $x =& $y; }
}
var_dump($x);
unset($v);

function g() {
    $a = [1, 2];
    try {
        foreach ($a as &$v) {
            $a[0] =& $a;
            $c = 5;
            $a =& $c;
            throw new Exception("x");
        }
    } catch (Exception $e) {
        var_dump(gc_collect_cycles());
    }
    var_dump(gc_collect_cycles());
}
g();
var_dump(gc_collect_cycles());
$z = [1, 2];
foreach ($z as &$q) {}
var_dump($z);
$w = $z; $w[] = 3; var_dump(count($z));
$a = [1, 2, 3];
foreach ($a as &$v) {
    $v *= 2;
    if ($v == 4) { var_dump(count(preg_grep("/foreach/", array_keys(get_defined_vars())))); }
}
unset($v);
var_dump($a, array_key_exists('a', $GLOBALS));
$copy = $a; $copy[] = 9; var_dump(count($a));

function nested() {
    $m = [[1, 2], [3, 4]];
    foreach ($m as &$row) {
        foreach ($row as &$cell) { $cell += 10; }
        unset($cell);
    }
    unset($row);
    var_dump($m);
    $r = null;
    foreach ($m as &$row) { $r = &$m; break; }
    $r[] = 'x';
    var_dump(count($m));
    return $m;
}
nested();

function ret() {
    $a = [1, 2, 3];
    foreach ($a as $k => &$v) {
        if ($k == 1) return $a;
    }
}
var_dump(ret());

function withGlobal() {
    global $g;
    foreach ($g as &$v) { $v = $v . '!'; }
    unset($v);
}
$g = ['a', 'b'];
withGlobal();
var_dump($g);

function withStatic() {
    static $s = [1, 2];
    foreach ($s as &$v) { $v++; }
    unset($v);
    return $s;
}
withStatic();
var_dump(withStatic());

$fn = function () use (&$a) {
    foreach ($a as &$v) { $v = -$v; }
};
$fn();
var_dump($a);

function gen() {
    $a = [1, 2, 3];
    foreach ($a as &$v) { yield $v; $v = 0; }
    unset($v);
    yield $a;
}
foreach (gen() as $x) var_dump($x);

function fin() {
    $a = [1, 2];
    try {
        foreach ($a as &$v) { throw new Exception("e"); }
    } finally {
        echo "finally\n";
    }
}
try { fin(); } catch (Exception $e) { echo "caught\n"; }

function cont() {
    $a = [1, 2, 3];
    $b = [4, 5];
    foreach ($a as &$x) {
        foreach ($b as &$y) { if ($y == 4) continue 2; }
    }
    unset($x, $y);
    var_dump($a, $b);
    $b2 = $b; $b2[0] = 'c'; var_dump($b[0]);
}
cont();

$o = [1];
foreach ($o as &$q) { unset($o); }
var_dump(isset($o));
$e = [1, 2];
foreach ($e as &$w) { $e = 'str'; }
var_dump($e);

// a generator a loop iterates by reference keeps the references it handed
// out when an exception leaves the loop
class Props { public int $a = 1; public int $b = PHP_INT_MAX;
    public function &each() { yield $this->a; yield $this->b; } }
$props = new Props;
try {
    foreach ($props->each() as &$p) { $p += 1; }
} catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump($props);
