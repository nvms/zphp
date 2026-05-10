<?php
// trait_exists / interface_exists / class_exists
trait T1 {}
interface II1 {}
class CC1 {}

var_dump(trait_exists("T1"));
var_dump(trait_exists("II1"));
var_dump(trait_exists("CC1"));
var_dump(interface_exists("II1"));
var_dump(interface_exists("T1"));
var_dump(interface_exists("CC1"));
var_dump(class_exists("CC1"));
var_dump(class_exists("II1"));
var_dump(class_exists("T1"));

// stdClass
var_dump(class_exists("stdClass"));

// trait_exists autoload arg
var_dump(trait_exists("NoTrait", false));
var_dump(trait_exists("NoTrait", true)); // tries autoload

// get_parent_class
class A {}
class B extends A {}
class C extends B {}

var_dump(get_parent_class("A"));
var_dump(get_parent_class("B"));
var_dump(get_parent_class("C"));
var_dump(get_parent_class(new C));
try { var_dump(get_parent_class("NonExistent")); } catch (\TypeError $e) { echo "te-noclass\n"; }

// PHP emits deprecation for no-arg get_parent_class() (architectural skip)
class D extends C {
    public function p(): string|false { return get_parent_class($this); }
}
var_dump((new D)->p());

class E {
    public function p(): string|false { return get_parent_class($this); }
}
var_dump((new E)->p()); // false (no parent)

// get_class_methods order is declaration-order in PHP; zphp uses hashmap order (architectural)
class M {
    public function zMethod() {}
    public function aMethod() {}
    public function mMethod() {}
}
$m = get_class_methods(M::class);
sort($m);
print_r($m);

class P {
    public function p1() {}
    public function p2() {}
}
class S extends P {
    public function s1() {}
    public function s2() {}
}
$m = get_class_methods(S::class);
sort($m);
print_r($m);

// class_implements no interfaces
class Plain {}
print_r(class_implements(Plain::class)); // []
print_r(class_implements("Plain"));

interface IA {}
class WithIface implements IA {}
print_r(class_implements(WithIface::class));

// class_uses
trait T2 {}
trait T3 {}
class UsesMulti { use T2, T3; }
print_r(class_uses(UsesMulti::class));

class NoTraits {}
print_r(class_uses(NoTraits::class));

// class_uses inherited (PHP only returns own traits, not parents')
class Parent1 { use T2; }
class Child1 extends Parent1 { use T3; }
print_r(class_uses(Child1::class)); // T3 only? Actually just direct uses

class ChildNo extends Parent1 {} // inherits T2
print_r(class_uses(ChildNo::class)); // empty - parent's traits

// class_parents
print_r(class_parents(C::class));
print_r(class_parents("D"));
print_r(class_parents("A"));

// Reflection on traits
$rc = new ReflectionClass(T1::class);
var_dump($rc->isTrait()); // true
var_dump($rc->isInterface()); // false
var_dump($rc->isAbstract()); // false (traits aren't abstract)

$rc = new ReflectionClass(II1::class);
var_dump($rc->isInterface());
var_dump($rc->isTrait());

$rc = new ReflectionClass(CC1::class);
var_dump($rc->isInterface());
var_dump($rc->isTrait());

// is_a with interface
class X implements IA {}
var_dump(is_a(new X, IA::class));
var_dump(is_a("X", IA::class, true));

// final class
final class FC {}
$rc = new ReflectionClass(FC::class);
var_dump($rc->isFinal());
$rc = new ReflectionClass(CC1::class);
var_dump($rc->isFinal());

// abstract class
abstract class AC {}
$rc = new ReflectionClass(AC::class);
var_dump($rc->isAbstract());
