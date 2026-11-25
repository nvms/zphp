<?php
// ReflectionMethod::invoke()/invokeArgs() refuse an abstract method before
// they parse their arguments
abstract class A {
    abstract function foo();
    function bar($x) { return $x; }
}
class B extends A { function foo() {} }
$abstract = new ReflectionMethod('A', 'foo');
foreach ([fn() => $abstract->invokeArgs(true), fn() => $abstract->invoke(), fn() => $abstract->invokeArgs(new B, [])] as $f) {
    try {
        $f();
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
$concrete = new ReflectionMethod('A', 'bar');
foreach ([fn() => $concrete->invokeArgs(new B), fn() => $concrete->invoke(), fn() => $concrete->invokeArgs(new B, [7])] as $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
