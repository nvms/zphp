<?php
// isset/empty/?? on a property or element of $this need an object: outside
// one php throws, where isset($this) alone is just false; other containers
// of an isset are read quietly, dynamic property names too
var_dump(isset($this));
foreach ([
    fn() => isset($this->foo),
    fn() => isset($this->foo->bar),
    fn() => isset($this[0]),
    fn() => empty($this->foo),
    fn() => empty($this[0]),
    fn() => $this->foo ?? 'default',
] as $f) {
    try {
        var_dump($f());
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
class A extends ArrayObject {
    public $foo = 5;
    function test() {
        $this[0] = 5;
        var_dump(isset($this), isset($this->foo), isset($this[0]), empty($this->foo), $this->bar ?? 'none');
    }
}
(new A)->test();
$a = 'foo';
$b = 'name';
var_dump(isset(${$a}->{$b}));
var_dump(isset($GLOBALS['nothing']->$b));
var_dump(isset($undefined->$b));
