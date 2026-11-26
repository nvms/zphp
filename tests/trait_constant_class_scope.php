<?php
// a trait constant naming the using class (self::, parent::, __CLASS__) is
// evaluated in each using class's scope; read on the trait, in the trait's

trait T0 {
    const C = self::who(...);
    public $p = self::who(...);
    public static $s = self::who(...);
}
class A0 { use T0; public static function who() { return 'A'; } }
class B0 { use T0; public static function who() { return 'B'; } }
echo (A0::C)(), PHP_EOL;
echo (B0::C)(), PHP_EOL;
echo ((new A0)->p)(), PHP_EOL;
echo ((new B0)->p)(), PHP_EOL;
echo (A0::$s)(), PHP_EOL;
echo (B0::$s)(), PHP_EOL;
var_dump(A0::C);

trait T1 {
    const D = self::class;
    const E = __CLASS__;
    const F = [self::class, 1];
}
class A1 { use T1; }
var_dump(A1::D, A1::E, A1::F);
var_dump((new ReflectionClass('T1'))->getConstants());
var_dump((new ReflectionClassConstant('T1', 'D'))->getValue());
var_dump((new ReflectionClass('T1'))->getConstant('F'));

trait T { const C = self::X; const K = [__CLASS__]; }
trait U { const C = self::X; }
class A { use T; const X = 1; const K = ['A']; }
var_dump(A::C, A::K);
class B { use T, U; const X = 2; }
var_dump(B::C);
class P { const X = 'p'; }
class Q extends P { use T; }
var_dump(Q::C, Q::K);
class R extends Q {}
var_dump(R::C, R::K);
var_dump((new ReflectionClass('R'))->getConstants());
var_dump((new ReflectionClassConstant('R', 'C'))->getValue());
trait V { use T; }
class W { use V; const X = 'w'; }
var_dump(W::C);
enum E { use T; const X = 'e'; }
var_dump(E::C, E::K);
trait Z { const C = self::X; }
class Y { use Z; const X = 3; const C = 3; }
var_dump(Y::C);

// a constant that fails is evaluated again on the next access
trait Missing { const C = self::NOPE; }
class M { use Missing; }
for ($i = 0; $i < 2; $i++) {
    try {
        var_dump(M::C);
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
