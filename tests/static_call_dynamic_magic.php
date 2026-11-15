<?php
// $c::missing(): __call when $this is an instance of the class, else
// __callStatic, as zend_std_get_static_method picks

class Foo {
    public function __call($a, $b) { echo "__call $a ", count($b), "\n"; }
    public static function __callStatic($a, $b) { echo "__callStatic $a ", count($b), " as ", static::class, "\n"; }
    public function test() {
        $this->one();
        self::two(1);
        $this::three(1, 2);
        $c = static::class;
        $c::four();
        $p = 'Foo';
        $p::five();
    }
}
class Bar extends Foo {}

(new Foo)->test();
(new Bar)->test();
$b = new Bar;
$b::six();
$n = 'Bar';
$n::seven(1);

class Plain {}
try {
    $p = 'Plain';
    $p::nope();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
