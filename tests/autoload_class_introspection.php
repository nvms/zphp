<?php
// autoloader registration / unregister (architectural - eval not implemented for in-loader class def)
$loaded = [];
$cb = function ($class) use (&$loaded) {
    $loaded[] = $class;
};
spl_autoload_register($cb);

// class_exists with autoload=false skips autoloader
var_dump(class_exists("Nope1", false));
echo count($loaded), "\n";

// class_exists default invokes autoloader
class_exists("Nope2");
print_r($loaded);

// unregister
spl_autoload_unregister($cb);
$loaded = [];
class_exists("Nope3");
echo count($loaded), "\n";

// get_declared_classes returns array
$classes = get_declared_classes();
echo gettype($classes), " ", count($classes) > 0 ? "non-empty" : "empty", "\n";
echo in_array("stdClass", $classes) ? "has-stdclass" : "no", "\n";

// get_declared_interfaces
$interfaces = get_declared_interfaces();
echo gettype($interfaces), "\n";
echo in_array("Iterator", $interfaces) ? "has-iter" : "no", "\n";
echo in_array("Countable", $interfaces) ? "has-count" : "no", "\n";

// interface_exists
var_dump(interface_exists("Iterator"));
var_dump(interface_exists("Countable"));
var_dump(interface_exists("NonExistentInterface"));
var_dump(interface_exists("stdClass"));

// trait_exists
trait T1 {
    public function thing(): string { return "T1"; }
}
var_dump(trait_exists("T1"));
var_dump(trait_exists("stdClass"));
var_dump(trait_exists("nonexistenttrait"));

// enum_exists
enum E { case A; case B; }
var_dump(enum_exists("E"));
var_dump(enum_exists("stdClass"));

// class_exists case-insensitive
class FooClass {}
var_dump(class_exists("FooClass"));
var_dump(class_exists("fooclass"));
var_dump(class_exists("FOOCLASS"));

// is_subclass_of
class P {}
class C extends P {}
var_dump(is_subclass_of("C", "P"));
var_dump(is_subclass_of(new C, "P"));
var_dump(is_subclass_of("P", "C"));

// is_a()
var_dump(is_a(new C, "P"));
var_dump(is_a(new C, "C"));
var_dump(is_a("C", "P", true));
var_dump(is_a(new stdClass, "stdClass"));

// get_class on object
$obj = new stdClass;
echo get_class($obj), "\n";
echo get_class(new C), "\n";

// get_parent_class
echo get_parent_class(new C), "\n";
var_dump(get_parent_class(new P));

// class_implements
interface IFoo {}
interface IBar {}
class Impl implements IFoo, IBar {}
print_r(class_implements(new Impl));

// class_parents
class GP {}
class PC extends GP {}
class CC extends PC {}
print_r(class_parents(new CC));

// get_object_vars
class WithProps {
    public int $a = 1;
    public string $b = "x";
    private int $c = 3;
}
print_r(get_object_vars(new WithProps));

class SelfV {
    public int $a = 1;
    private int $b = 2;
    public function vars(): array {
        return get_object_vars($this);
    }
}
print_r((new SelfV)->vars());

// method_exists
class HasMethod {
    public function go(): void {}
    public static function makeIt(): void {}
}
var_dump(method_exists("HasMethod", "go"));
var_dump(method_exists("HasMethod", "makeIt"));
var_dump(method_exists(new HasMethod, "nonexistent"));

// property_exists
class HasProps {
    public int $x = 1;
    private int $y = 2;
}
var_dump(property_exists("HasProps", "x"));
var_dump(property_exists("HasProps", "y"));
var_dump(property_exists("HasProps", "nope"));

// get_class_methods (only public from outside)
class WithMethods {
    public function pub(): void {}
    protected function prot(): void {}
    private function priv(): void {}
}
$ms = get_class_methods("WithMethods");
sort($ms);
print_r($ms);

// abstract / interface / trait class checks
abstract class AbsC {}
var_dump(class_exists("AbsC"));

// final
final class FinalC {}
var_dump(class_exists("FinalC"));

// new on abstract
try { new AbsC; echo "no\n"; }
catch (\Error $e) { echo "abs-err\n"; }
