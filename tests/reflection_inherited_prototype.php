<?php
// an inherited method's prototype, as the inheriting class's copy has it:
// an interface the class implements makes the interface's method it

interface a {
    function foo();
    function bar();
}
interface b {
    function foo();
}
interface d extends a {}

abstract class c {
    function bar() { }
    function baz() { }
}

class x extends c implements a, b {
    function foo() { }
}
class y extends x {}
class z extends c implements d { function foo() { } }
class w extends c {}

foreach (['c', 'x', 'y', 'z', 'w'] as $class) {
    foreach (['foo', 'bar', 'baz'] as $method) {
        if (!method_exists($class, $method)) continue;
        $m = new ReflectionMethod($class, $method);
        try {
            $proto = $m->getPrototype();
            echo "$class::$method: ", $proto->class, "::", $proto->name, "\n";
        } catch (ReflectionException $e) {
            echo "$class::$method: ", $e->getMessage(), "\n";
        }
    }
}
echo new ReflectionClass('x');
echo new ReflectionMethod('z', 'bar');
