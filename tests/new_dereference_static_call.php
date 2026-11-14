<?php
// a static call on a new expression with constructor arguments (php 8.4)

class A {
    public static function staticMethod(): void { echo static::class, " static method\n"; }
    public function method(): void { echo "method\n"; }
}
class B extends A {}

$class = 'B';
new A()::staticMethod();
new $class()::staticMethod();
new (trim(' A '))()::staticMethod();
(new $class)::staticMethod();
new class { public static function staticMethod() { echo "anonymous static method\n"; } }::staticMethod();
new class extends A {}::staticMethod();
new $class()->method();
