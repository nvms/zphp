<?php
// self:: and parent:: constants in a closure follow the scope it is bound to
class P { const C = 'P::C'; const D = 'P::D'; }
class A extends P {
    const C = 'A::C';
    private const PRIV = 'A::PRIV';
    public function f() {
        return function () { return [self::C, parent::C, static::C, self::PRIV, self::class]; };
    }
    public function g() {
        return fn () => [self::C, parent::D];
    }
    public static function h() {
        return static function () { return self::C; };
    }
}
class B extends A { const C = 'B::C'; }
class Q { const C = 'Q::C'; }
var_dump((new A)->f()());
var_dump((new B)->f()());
var_dump((new A)->g()());
var_dump(A::h()());
$f = (new A)->f();
try { var_dump($f->bindTo(new Q, 'Q')()); } catch (Error $e) { echo $e->getMessage(), "\n"; }
$h = A::h();
var_dump(Closure::bind($h, null, 'Q')());
