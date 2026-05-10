<?php
class Box {
    public int $pub = 1;
    protected int $prot = 2;
    private int $priv = 3;

    public function getVars(): array {
        return get_object_vars($this);
    }
}
$b = new Box;
print_r(get_object_vars($b));
print_r($b->getVars());

class Child extends Box {
    public int $childPub = 10;
    private int $childPriv = 20;
    public function getVarsFromChild(): array {
        return get_object_vars($this);
    }
}
$c = new Child;
print_r(get_object_vars($c));
print_r($c->getVarsFromChild());

class A {
    private int $aPriv = 100;
    protected int $aProt = 200;
}
class B extends A {
    private int $bPriv = 1000;
    public function dump(): array {
        return get_object_vars($this);
    }
}
$b = new B;
print_r($b->dump());

echo property_exists("Box", "pub") ? "y" : "n", "\n";
echo property_exists("Box", "prot") ? "y" : "n", "\n";
echo property_exists("Box", "priv") ? "y" : "n", "\n";
echo property_exists("Box", "nope") ? "y" : "n", "\n";
echo property_exists(new Box, "pub") ? "y" : "n", "\n";
echo property_exists(new Box, "prot") ? "y" : "n", "\n";
echo property_exists(new Box, "priv") ? "y" : "n", "\n";

echo property_exists("Child", "pub") ? "y" : "n", "\n";
echo property_exists("Child", "prot") ? "y" : "n", "\n";
echo property_exists("Child", "priv") ? "y" : "n", "\n";
echo property_exists("Child", "childPub") ? "y" : "n", "\n";

$obj = new Box;
$obj->dyn = "added";
echo property_exists($obj, "dyn") ? "y" : "n", "\n";
echo property_exists("Box", "dyn") ? "y" : "n", "\n";

echo method_exists("Box", "getVars") ? "y" : "n", "\n";
echo method_exists("Box", "nope") ? "y" : "n", "\n";
echo method_exists(new Box, "getVars") ? "y" : "n", "\n";

class WithMethods {
    public function pubM(): void {}
    protected function protM(): void {}
    private function privM(): void {}
    public static function staticM(): void {}
}
echo method_exists("WithMethods", "pubM") ? "y" : "n", "\n";
echo method_exists("WithMethods", "protM") ? "y" : "n", "\n";
echo method_exists("WithMethods", "privM") ? "y" : "n", "\n";
echo method_exists("WithMethods", "staticM") ? "y" : "n", "\n";

$names = get_class_methods("WithMethods");
sort($names);
print_r($names);

$names = get_class_methods(new WithMethods);
sort($names);
print_r($names);

class Holder {
    public string $name = "alice";
    public int $age = 30;
    private string $secret = "hidden";
    public function dump() { return get_object_vars($this); }
}
print_r(get_object_vars(new Holder));
print_r((new Holder)->dump());

echo class_exists("Box") ? "y" : "n", "\n";
echo class_exists("DoesNotExist") ? "y" : "n", "\n";
echo class_exists("stdClass") ? "y" : "n", "\n";
echo class_exists("DoesNotExist", false) ? "y" : "n", "\n";

echo interface_exists("Iterator") ? "y" : "n", "\n";
echo interface_exists("DoesNotExist") ? "y" : "n", "\n";

echo class_exists("Box") && !interface_exists("Box") ? "y" : "n", "\n";

class HasParent {
    public int $x = 1;
}
class HasChild extends HasParent {
    public int $y = 2;
}
echo is_subclass_of(new HasChild, "HasParent") ? "y" : "n", "\n";
echo is_subclass_of("HasChild", "HasParent") ? "y" : "n", "\n";
echo is_a(new HasChild, "HasParent") ? "y" : "n", "\n";
echo is_a("HasChild", "HasParent", true) ? "y" : "n", "\n";
echo is_a("HasParent", "HasChild", true) ? "y" : "n", "\n";

print_r(class_parents(new HasChild));
print_r(class_parents("HasChild"));

class WithIface implements Iterator {
    public function rewind(): void {}
    public function current(): mixed { return null; }
    public function key(): mixed { return null; }
    public function next(): void {}
    public function valid(): bool { return false; }
}
print_r(class_implements(new WithIface));

$arr = get_class_methods("Box");
print_r($arr);

class Singleton {
    private function __construct() {}
}
$names = get_class_methods("Singleton");
print_r($names);

class FromOutside {
    public int $a = 1;
    protected int $b = 2;
    private int $c = 3;
}
$f = new FromOutside;
$keys = array_keys(get_object_vars($f));
sort($keys);
print_r($keys);
