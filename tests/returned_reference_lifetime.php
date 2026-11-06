<?php
// a value returned by reference outlives the call whether or not it is bound
class Foo {
    public function &__call($method, $args) { return $method; }
}
$bar = (new Foo)->bar(...);
echo $bar(), "\n";
function &counter() {
    static $n = 0;
    $n++;
    return $n;
}
$c = &counter();
counter();
echo $c, "\n";
