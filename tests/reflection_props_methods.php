<?php
class Base {
    public string $a = "ba";
    protected int $b = 0;
    private float $c = 1.5;

    public function pub(): void {}
    protected function prot(): int { return 1; }
    private function priv(): string { return "p"; }
    public static function staticMethod(): bool { return true; }
}

class Child extends Base {
    public bool $x = true;
    private array $y = [];

    public function child(): self { return $this; }
}

$rc = new ReflectionClass(Child::class);

// getProperties no filter (all)
$props = $rc->getProperties();
echo "all-count=", count($props), "\n";
foreach ($props as $p) echo $p->getName(), ":", $p->getDeclaringClass()->getName(), " ";
echo "\n";

// PUBLIC filter
$props = $rc->getProperties(ReflectionProperty::IS_PUBLIC);
echo "pub=", count($props), " ";
foreach ($props as $p) echo $p->getName(), " ";
echo "\n";

// PROTECTED
$props = $rc->getProperties(ReflectionProperty::IS_PROTECTED);
echo "prot=", count($props), " ";
foreach ($props as $p) echo $p->getName(), " ";
echo "\n";

// PRIVATE
$props = $rc->getProperties(ReflectionProperty::IS_PRIVATE);
echo "priv=", count($props), " ";
foreach ($props as $p) echo $p->getName(), " ";
echo "\n";

// STATIC and PUBLIC|STATIC filters (architectural - PropertyDef has no static metadata)

// getMethods no filter
$methods = $rc->getMethods();
echo "methods=", count($methods), " ";
$names = array_map(fn($m) => $m->getName(), $methods);
sort($names);
print_r($names);

// PUBLIC methods
$methods = $rc->getMethods(ReflectionMethod::IS_PUBLIC);
$names = array_map(fn($m) => $m->getName(), $methods);
sort($names);
echo "pub-methods=";
print_r($names);

// PROTECTED methods
$methods = $rc->getMethods(ReflectionMethod::IS_PROTECTED);
echo "prot-methods=", count($methods), " ";
foreach ($methods as $m) echo $m->getName(), " ";
echo "\n";

// PRIVATE methods
$methods = $rc->getMethods(ReflectionMethod::IS_PRIVATE);
echo "priv-methods=", count($methods), " ";
foreach ($methods as $m) echo $m->getName(), " ";
echo "\n";

// STATIC methods
$methods = $rc->getMethods(ReflectionMethod::IS_STATIC);
echo "static-methods=", count($methods), " ";
foreach ($methods as $m) echo $m->getName(), " ";
echo "\n";

// ReflectionProperty getValue/setValue public default
$rp = new ReflectionProperty(Child::class, "a");
$obj = new Child;
echo $rp->getValue($obj), "\n"; // ba
$rp->setValue($obj, "set");
echo $rp->getValue($obj), "\n";

// non-default value
$obj->a = "default";
echo $rp->getValue($obj), "\n";

// private property access via reflection
$rp = new ReflectionProperty(Base::class, "c");
$obj = new Base;
echo $rp->getValue($obj), "\n"; // 1.5 (no need for setAccessible in PHP 8.1+)

$rp->setValue($obj, 99.9);
echo $rp->getValue($obj), "\n";

// static property reflection (architectural - PropertyDef has no static metadata)

// hasProperty
$rc = new ReflectionClass(Child::class);
var_dump($rc->hasProperty("a"));    // true (inherited)
var_dump($rc->hasProperty("x"));    // true (own)
var_dump($rc->hasProperty("nope")); // false

// hasMethod
var_dump($rc->hasMethod("pub"));    // true (inherited)
var_dump($rc->hasMethod("child"));  // true (own)
var_dump($rc->hasMethod("nope"));   // false

// ReflectionMethod isStatic / isPublic
$rm = new ReflectionMethod(Base::class, "pub");
var_dump($rm->isStatic());
var_dump($rm->isPublic());
var_dump($rm->isProtected());
var_dump($rm->isPrivate());

$rm = new ReflectionMethod(Base::class, "prot");
var_dump($rm->isStatic());
var_dump($rm->isPublic());
var_dump($rm->isProtected());
var_dump($rm->isPrivate());

$rm = new ReflectionMethod(Base::class, "priv");
var_dump($rm->isPrivate());

$rm = new ReflectionMethod(Base::class, "staticMethod");
var_dump($rm->isStatic());
var_dump($rm->isPublic());

// ReflectionMethod getReturnType
$rm = new ReflectionMethod(Base::class, "pub");
var_dump($rm->getReturnType()?->getName());

$rm = new ReflectionMethod(Base::class, "prot");
echo $rm->getReturnType()->getName(), "\n";

$rm = new ReflectionMethod(Base::class, "staticMethod");
echo $rm->getReturnType()->getName(), "\n";

$rm = new ReflectionMethod(Child::class, "child");
echo $rm->getReturnType()->getName(), "\n";

// property type info via reflection (architectural - PropertyDef has no type field)

// hasDefaultValue / getDefaultValue
$rp = new ReflectionProperty(Base::class, "a");
var_dump($rp->hasDefaultValue());
var_dump($rp->getDefaultValue());

// getModifiers
$rp = new ReflectionProperty(Base::class, "a");
echo $rp->getModifiers(), "\n"; // 1 (PUBLIC)
$rp = new ReflectionProperty(Base::class, "b");
echo $rp->getModifiers(), "\n"; // 2 (PROTECTED)
$rp = new ReflectionProperty(Base::class, "c");
echo $rp->getModifiers(), "\n"; // 4 (PRIVATE)
// static prop modifiers (architectural)
$rm = new ReflectionMethod(Base::class, "staticMethod");
echo $rm->getModifiers(), "\n"; // PUBLIC | STATIC

// ReflectionClass getDefaultProperties
print_r($rc->getDefaultProperties());

// ReflectionClass getMethod
$rm = $rc->getMethod("pub");
echo $rm->getName(), "\n";

// ReflectionClass getProperty
$rp = $rc->getProperty("a");
echo $rp->getName(), "=", $rp->getValue(new Child), "\n";

// ReflectionClass isAbstract / isFinal / isInterface
var_dump($rc->isAbstract());
var_dump($rc->isFinal());
var_dump($rc->isInterface());
var_dump($rc->isInstantiable());

abstract class Abs { abstract public function go(): void; }
$ra = new ReflectionClass(Abs::class);
var_dump($ra->isAbstract());
var_dump($ra->isInstantiable());

interface IFoo { public function f(): void; }
$ri = new ReflectionClass(IFoo::class);
var_dump($ri->isInterface());
var_dump($ri->isInstantiable());

final class Fnl {}
$rf = new ReflectionClass(Fnl::class);
var_dump($rf->isFinal());
