<?php
class C {
    public const PUB = 1;
    protected const PROT = 2;
    private const PRIV = 3;
    public const COMPUTED = self::PUB + 10;
    public const LIST_VAL = [self::PUB, self::PROT, self::PRIV];
    public const STR = "hello-" . self::PUB;

    public static function showAll(): void {
        echo self::PUB, " ", self::PROT, " ", self::PRIV, "\n";
    }
}

echo C::PUB, "\n";
echo C::COMPUTED, "\n";
print_r(C::LIST_VAL);
echo C::STR, "\n";
C::showAll();

// const visibility enforcement (architectural - const-init phase has no class context)
class D extends C {
    public static function tryProt(): int { return self::PROT; }
}
echo D::tryProt(), "\n";

class M {
    const A = 1;
    const B = 2;
    const SUM = self::A + self::B;
    const PRODUCT = self::A * (self::B + 5);
    const NESTED = ["a" => self::A, "b" => self::B];
}
echo M::SUM, "\n";
echo M::PRODUCT, "\n";
print_r(M::NESTED);

class Parent1 {
    const X = 10;
}
class Child1 extends Parent1 {
    const Y = self::X + 5;
    const Z = parent::X * 2;
}
echo Child1::Y, " ", Child1::Z, "\n";

enum E: string {
    case A = "a";
    public const PREFIX = "X-";
    public const TAGS = ["red", "green", "blue"];
    public const SELFREF = self::PREFIX . "y";
}
echo E::PREFIX, " ", E::SELFREF, "\n";
print_r(E::TAGS);

class Foo {}
$f = new Foo;
echo $f::class, "\n";
echo Foo::class, "\n";

class Animal {
    public static function staticName(): string { return static::class; }
    public static function selfName(): string { return self::class; }
}
class Dog extends Animal {}

echo Animal::staticName(), "\n";
echo Dog::staticName(), "\n";
echo Animal::selfName(), "\n";
echo Dog::selfName(), "\n";

class K {
    public const KP = 100;
}
$k = new K;
echo $k::KP, "\n";

interface I {
    const VERSION = "1.0";
}
class IC implements I {}
echo IC::VERSION, "\n";
echo I::VERSION, "\n";

trait T {
    public const TC = "trait-const";
}
class WithT {
    use T;
}
echo WithT::TC, "\n";

class Already {}
$name = Already::class;
echo $name, "\n";

interface IA {}
echo IA::class, "\n";

define("APP_VER", "9.9");
echo APP_VER, "\n";
echo constant("APP_VER"), "\n";

class CC {
    const X = 42;
}
echo constant("CC::X"), "\n";

var_dump(defined("APP_VER"));
var_dump(defined("NOPE_DEFINED_AT_ALL"));
var_dump(defined("CC::X"));
var_dump(defined("CC::Y"));

class CK {
    const M = ["a" => 1, "b" => 2];
    const KEYS = ["a", "b", "c"];
}
print_r(CK::M);
print_r(CK::KEYS);

abstract class AC {
    const NAME = "abstract";
}
echo AC::NAME, "\n";
