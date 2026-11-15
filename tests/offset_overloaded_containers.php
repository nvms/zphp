<?php
// write fetches on ArrayAccess objects and ArrayObject: what offsetGet hands
// out is a temporary unless it is an object or a reference
class A implements ArrayAccess {
    public function offsetSet($offset, $value): void { echo "set "; var_dump($offset); }
    public function offsetGet($offset): mixed { echo "get "; var_dump($offset); return 5; }
    public function offsetUnset($offset): void { echo "unset "; var_dump($offset); }
    public function offsetExists($offset): bool { echo "exists "; var_dump($offset); return true; }
}
class B extends ArrayObject {
    public function offsetGet($offset): mixed { echo "B get "; var_dump($offset); return 5; }
}
function t($label, $f) {
    echo "$label: ";
    try { $f(); echo "ok\n"; } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
}
foreach ([new A, new ArrayObject([1 => [2 => 3]]), new B] as $c0) {
    echo "== ", get_class($c0), "\n";
    t("ref", function () use ($c0) { $c = $c0; $r = &$c[1]; var_dump($r); });
    t("refapp", function () use ($c0) { $c = $c0; $r = &$c[]; var_dump($r); });
    t("w2", function () use ($c0) { $c = $c0; $c[1][null] = 5; });
    t("w2b", function () use ($c0) { $c = $c0; $c[7][1.5] = 5; });
    t("rw2", function () use ($c0) { $c = $c0; $c[1][2] += 5; });
    t("app2", function () use ($c0) { $c = $c0; $c[][5] = 1; });
    t("unset2", function () use ($c0) { $c = $c0; unset($c[1][2]); var_dump(count($c)); });
    t("unset2miss", function () use ($c0) { $c = $c0; unset($c[9][2]); });
    t("unset2bad", function () use ($c0) { $c = $c0; unset($c[[]][2]); });
    t("float", function () use ($c0) { $c = $c0; $c[1e20] = 1; $c[NAN] = 2; });
}
$o = new ArrayObject([1 => [2 => 3, 4 => 5]]);
unset($o[1][2]);
var_dump($o->getArrayCopy());

echo "== handler sharing the array\n";
set_error_handler(function ($code, $msg) {
    echo "Err: $msg\n";
    $GLOBALS['copy'] = $GLOBALS['y'];
});
function x(&$s) { $s[100000000000000000000] = 1; }
x($y);
var_dump($y);
$w = [];
function z(&$s) { $s[1.5] = 1; }
z($w);
var_dump($w);
restore_error_handler();

echo "== \$GLOBALS through a reference\n";
function f(&$s) { $s = 5; var_dump($GLOBALS["q"]); }
f($q);
