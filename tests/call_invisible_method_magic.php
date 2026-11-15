<?php
// a method the calling scope cannot see goes to __call or __callStatic when
// the class has one
class A { private function f() { return "priv"; } public function __call($n, $a) { return "call $n"; } }
$a = new A; echo $a->f(), "\n";
class B { private function f() { return "priv"; } public function __call($n, $a) { return $this->$n(); } }
$b = new B; echo $b->f(), "\n";
class C { private function f() { return "priv"; } public function __call($n, $a) { return call_user_func_array([$this, $n], $a); } }
$c = new C; echo $c->f(), "\n";
abstract class Base { public function __call($name, $arguments) { return $this->$name(); } private function foobar() { return 'okey'; } }
class Sub extends Base {}
echo (new Sub)->foobar(), "\n";

class A2 {
    private static function f() { return "priv"; }
    public static function __callStatic($n, $a) { return "callStatic $n"; }
    protected function g() { return "g"; }
    public function __call($n, $a) { return "call $n"; }
}
echo A2::f(), "\n";
$a = new A2;
echo $a->g(), "\n";
echo $a->g(...[1]), "\n";
class B2 { private function h() {} }
try { (new B2)->h(...[1]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
class D extends A2 { function t() { return [$this->g(), A2::f()]; } }
var_dump((new D)->t());
