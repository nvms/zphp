<?php
abstract class Shape {
    abstract public function area(): float;
    public final function name(): string { return static::class; }
    private function _id(): int { return 0; }
    protected static function create(): static { return new static; }
}

class Circle extends Shape {
    public function __construct(public float $radius = 1.0) {}
    public function area(): float { return 3.14 * $this->radius ** 2; }
    public static function pi(): float { return 3.14159; }
}

interface Drawable { public function draw(): void; }
interface Named { public function getName(): string; }

class Square extends Shape implements Drawable, Named {
    public function __construct(public readonly float $side) {}
    public function area(): float { return $this->side ** 2; }
    public function draw(): void {}
    public function getName(): string { return "Square"; }
}

$rc = new ReflectionClass(Shape::class);
echo "isAbstract=", var_export($rc->isAbstract(), true), "\n";
echo "isFinal=", var_export($rc->isFinal(), true), "\n";
echo "isInstantiable=", var_export($rc->isInstantiable(), true), "\n";
echo "isCloneable=", var_export($rc->isCloneable(), true), "\n";

$rc = new ReflectionClass(Circle::class);
echo "Circle isAbstract=", var_export($rc->isAbstract(), true), "\n";
echo "Circle isInstantiable=", var_export($rc->isInstantiable(), true), "\n";
echo "Circle isCloneable=", var_export($rc->isCloneable(), true), "\n";

$rc = new ReflectionClass(Square::class);
print_r($rc->getInterfaceNames());

// methods
foreach (["area", "name", "_id", "create", "pi"] as $name) {
    if (!Circle::class === Shape::class && method_exists(Shape::class, $name)) {
        $rm = new ReflectionMethod(Shape::class, $name);
    } elseif (method_exists(Circle::class, $name)) {
        $rm = new ReflectionMethod(Circle::class, $name);
    } else continue;
    echo "$name: abstract=", $rm->isAbstract() ? 1 : 0;
    echo " final=", $rm->isFinal() ? 1 : 0;
    echo " static=", $rm->isStatic() ? 1 : 0;
    echo " private=", $rm->isPrivate() ? 1 : 0;
    echo " protected=", $rm->isProtected() ? 1 : 0;
    echo " public=", $rm->isPublic() ? 1 : 0;
    echo "\n";
}

// ReflectionParameter
function example(string $a, int $b = 5, ?string $c = null, string ...$rest): void {}
$rf = new ReflectionFunction("example");
foreach ($rf->getParameters() as $p) {
    echo $p->getName(),
         " optional=", $p->isOptional() ? 1 : 0,
         " variadic=", $p->isVariadic() ? 1 : 0,
         " hasDefault=", $p->isDefaultValueAvailable() ? 1 : 0,
         " allowsNull=", $p->allowsNull() ? 1 : 0;
    if ($p->isDefaultValueAvailable()) echo " default=", var_export($p->getDefaultValue(), true);
    echo "\n";
}

// ReflectionProperty::getDefaultValue
class Holder {
    public string $name = "default";
    public int $count = 42;
    public ?array $items = null;
    public bool $on;
    public readonly float $pi;
    public function __construct() { $this->pi = 3.14; }
}
$rc = new ReflectionClass(Holder::class);
foreach ($rc->getProperties() as $p) {
    echo $p->getName(),
         " hasDefault=", $p->hasDefaultValue() ? 1 : 0;
    if ($p->hasDefaultValue()) echo " default=", var_export($p->getDefaultValue(), true);
    echo " readonly=", $p->isReadOnly() ? 1 : 0;
    echo "\n";
}

// Closure - Reflection
$c = function(int $x): string { return (string)$x; };
$rf = new ReflectionFunction($c);
echo "isClosure=", $rf->isClosure() ? 1 : 0, "\n";

class Ctx { public int $v = 10; public function make() { return function() { return $this->v; }; } }
$o = new Ctx;
$bound = $o->make();
$rf = new ReflectionFunction($bound);
$scope = $rf->getClosureScopeClass();
echo "scope=", $scope ? $scope->getName() : "none", "\n";

// var_export of arrays/objects/enums
echo var_export([1, 2, "three"], true), "\n";
echo var_export(["a" => 1, "b" => [2, 3]], true), "\n";
$o = new stdClass; $o->x = 1; $o->y = "hi";
echo var_export($o, true), "\n";
class P { public int $a = 1; public string $b = "x"; }
echo var_export(new P, true), "\n";
enum Mode { case A; case B; }
echo var_export(Mode::A, true), "\n";
enum Status: string { case Active = "active"; case Off = "off"; }
echo var_export(Status::Active, true), "\n";
echo var_export(true, true), "\n";
echo var_export(null, true), "\n";
echo var_export(1.5, true), "\n";
echo var_export(1.0, true), "\n";

// var_dump deep nesting
$deep = ["a" => ["b" => ["c" => ["d" => 1]]]];
var_dump($deep);

// recursion
$rec = ["x" => 1];
$rec["self"] = &$rec;
@var_dump($rec);
@print_r($rec);
