<?php
// a function returning an array by value gives its caller a copy: writing
// into the result changes nothing else, while a by-reference result writes
// through
class Holder {
    public $items = [1];
    function get() { return $this->items; }
    function __call($name, $args) { return $this->items; }
}
$h = new Holder;
$h->get()[0] = 2;
$h->magic()[1] = 3;
var_dump($h->items);

$global = ['a' => 1];
function byValue() { global $global; return $global; }
byValue()['a'] = 2;
var_dump($global);

function &byRef(array &$a) { return $a; }
$local = [1];
byRef($local)[0] = 5;
byRef($local)[] = 6;
var_dump($local);

function loop(Holder $h) {
    for ($i = 0; $i < 3; $i++) {
        $h->get()[0] = $i;
    }
    return $h->items;
}
var_dump(loop($h));
