<?php
// is_callable() sets $callable_name for every value, callable or not, as
// zend_get_callable_name names it, and checks with zend_is_callable's rules
abstract class A {
    abstract function foo();
    static function stat() {}
}
class B extends A {
    function foo() {}
    private function hidden() {}
    function test() {
        foreach ([['A', 'foo'], ['B', 'foo'], [$this, 'hidden'], ['A', 'stat'], 'A::stat', [$this, 'nope']] as $c) {
            var_dump(is_callable($c, false, $name), $name);
        }
    }
}
(new B)->test();

$values = [0, 1234567890, -2, 0.567, "", "\0", "strlen", "no_such_function", null, true, false, [], [1, 2], ['B', 123],
    [new B, 'foo'], [new B, 'hidden'], ['B', 'foo', 'x'], [1 => 'foo', 0 => 'B'], new B, function () {}, strlen(...)];
foreach ($values as $v) {
    var_dump(is_callable($v, false, $name), $name);
    var_dump(is_callable($v, true, $name), $name);
}
$f = fopen('php://memory', 'r');
var_dump(is_callable($f, false, $name), $name);
