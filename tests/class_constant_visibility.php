<?php
// protected and private class constants are readable only where php allows:
// private in the declaring class, protected along its inheritance chain
class A { protected const P = 'p'; private const S = 's'; public static function read() { return [self::P, self::S, static::P]; } }
class B extends A { public static function readP() { return [parent::P, self::P]; } public static function readS() { return parent::S; } }
class Other { public static function peek() { return A::P; } }
trait T { private const TP = 'tp'; public function tp() { return self::TP; } }
class UT { use T; }
enum E { protected const B = 2; public static function b() { return self::B; } }
print_r(A::read()); print_r(B::readP()); echo (new UT)->tp(), E::b(), "\n";
foreach ([fn () => A::P, fn () => A::S, fn () => B::readS(), fn () => Other::peek(), fn () => E::B, fn () => constant('A::P')] as $f) {
    try { var_dump($f()); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
$bound = Closure::bind(fn () => A::S, null, A::class); var_dump($bound());
