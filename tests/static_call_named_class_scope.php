<?php
// A::m() names A as the called class of a static method, while self:: and
// parent:: forward the caller's; an instance method on a fitting $this runs
// with $this's class

class A {
    public static function who() { echo static::class, "\n"; }
    public static function viaName() { A::who(); }
    public static function viaSelf() { self::who(); }
    public static function viaSelfAfterName() {
        A::who();
        self::who();
        A::who();
    }
    public static function viaSelfInCatch() {
        try {
            throw new Exception();
        } catch (Exception $e) {
            A::who();
            self::who();
        }
    }
    public function inst() { echo static::class, "\n"; }
    public function callInst() { A::inst(); self::inst(); }
    public static function closure() {
        return function () { self::who(); A::who(); static::who(); };
    }
}
class B extends A {
    public static function viaParent() { parent::who(); A::who(); B::who(); }
}
class C extends B {}

B::viaName();
B::viaSelf();
B::viaSelfAfterName();
B::viaSelfInCatch();
C::viaParent();
(new C)->callInst();
$f = C::closure();
$f();
$g = Closure::bind(function () { self::who(); }, null, B::class);
$g();

trait T {
    public static function tw() { self::who(); }
}
class D extends A { use T; }
class E extends D {}
E::tw();
