<?php
// an interface's methods are abstract, so naming one statically is no
// callable
abstract class Foo {
    abstract static function bar();
}
interface MyInterface {
    static function bar();
    function inst();
}
abstract class Bar {
    static function foo() { echo "ok\n"; }
}
var_dump(is_callable(["Foo", "bar"]), is_callable("Foo::bar"));
var_dump(is_callable(["MyInterface", "bar"]), is_callable("MyInterface::bar"), is_callable("myinterface::BAR"));
var_dump(is_callable(["MyInterface", "inst"]));
var_dump(is_callable(["Bar", "foo"]), is_callable("Bar::foo"));
is_callable("MyInterface::bar", false, $name);
var_dump($name);
try {
    call_user_func("MyInterface::bar");
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
