<?php
// `foreach ($a as &$o->p)` makes the property a reference to each element in
// turn; a readonly property refuses it
enum Foo: int { case Bar = 0; }
class C { public $p; public $q; public readonly int $r; }

$c = new C;
foreach ([1, 2] as &$c->p) {}
var_dump($c);

$arr = [1, 2];
foreach ($arr as $k => &$c->p) {
    echo $k, ": ", $c->p, "\n";
}
$arr[1] = 20;
var_dump($arr, $c);

$name = 'q';
$list = ['a', 'b'];
foreach ($list as &$c->$name) {}
$c->q = 'changed';
var_dump($list);

try {
    foreach ([1] as &$c->r) {}
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

try {
    $bar = Foo::Bar;
    foreach ([1] as &$bar->value) {}
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(Foo::Bar->value);

function f() {
    $o = new stdClass;
    foreach ([3, 4] as &$o->x) {
        if ($o->x === 3) continue;
        break;
    }
    return $o;
}
var_dump(f());
