<?php
// `&function foo()` returns by reference. caller's `$r = &foo(...)` binds
// to the same storage the function returned a ref to. supported return
// shapes: array element, object property, plain variable.

echo "== array elem ref-return ==\n";
class Box {
    public $items = ['a', 'b', 'c'];
    public function &get(int $i) {
        return $this->items[$i];
    }
}
$b = new Box;
$r = &$b->get(1);
$r = 'BBB';
print_r($b->items);

echo "== prop ref-return ==\n";
class Holder {
    public $name = 'orig';
    public function &nameRef() {
        return $this->name;
    }
}
$h = new Holder;
$nr = &$h->nameRef();
$nr = 'changed';
echo $h->name, "\n";

echo "== plain function ref-return ==\n";
$store = ['x' => 1, 'y' => 2];
function &lookup(string $k) {
    global $store;
    return $store[$k];
}
$xr = &lookup('x');
$xr = 99;
print_r($store);

echo "== ref-return with compound assign through the bound ref ==\n";
class Counter {
    public $n = 5;
    public function &val() {
        return $this->n;
    }
}
$ct = new Counter;
$nr = &$ct->val();
$nr++;
$nr += 10;
echo "n=", $ct->n, "\n";
