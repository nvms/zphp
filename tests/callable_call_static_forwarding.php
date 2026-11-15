<?php
// a callable that reaches __callStatic through parent:: or self:: forwards
// the caller's called class, as zend_is_callable_check_class sets it

class A {
    static function test() { echo static::class, "\n"; }
    static function __callStatic($name, $args) {
        echo "A::__callStatic($name) as ", static::class, "\n";
    }
}
class B extends A {
    static function run() {
        parent::missing();
        @call_user_func("parent::missing");
        @call_user_func(["parent", "missing"]);
        @call_user_func("self::missing");
        call_user_func([static::class, "missing"]);
        call_user_func("A::missing");
        call_user_func([A::class, "missing"]);
    }
}
class C extends B {}
C::run();
