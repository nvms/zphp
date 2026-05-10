<?php
abstract class Animal {
    public string $species = "unknown";
    protected int $legs = 4;
    public const KINGDOM = "Animalia";
    abstract public function sound(): string;
    public function describe(): string {
        return $this->species . " has " . $this->legs . " legs";
    }
}

final class Dog extends Animal {
    public string $breed;
    private static int $count = 0;
    public const TYPE = "canine";
    public function __construct(string $breed) {
        $this->species = "Dog";
        $this->breed = $breed;
        self::$count++;
    }
    public function sound(): string { return "Woof"; }
    public static function getCount(): int { return self::$count; }
}

$rc = new ReflectionClass("Dog");

echo $rc->getName(), "\n";
echo $rc->isAbstract() ? "y" : "n", "\n";
echo $rc->isFinal() ? "y" : "n", "\n";
echo $rc->isInterface() ? "y" : "n", "\n";
echo $rc->getParentClass()->getName(), "\n";

$ra = new ReflectionClass("Animal");
echo $ra->isAbstract() ? "y" : "n", "\n";
echo $ra->isFinal() ? "y" : "n", "\n";
echo var_export($ra->getParentClass(), true), "\n";

$methods = $rc->getMethods();
$names = [];
foreach ($methods as $m) $names[] = $m->getName();
sort($names);
print_r($names);

$pubMethods = $rc->getMethods(ReflectionMethod::IS_PUBLIC);
$pubNames = [];
foreach ($pubMethods as $m) $pubNames[] = $m->getName();
sort($pubNames);
print_r($pubNames);

$staticMethods = $rc->getMethods(ReflectionMethod::IS_STATIC);
$sNames = [];
foreach ($staticMethods as $m) $sNames[] = $m->getName();
print_r($sNames);

$props = $rc->getProperties();
$pnames = [];
foreach ($props as $p) $pnames[] = $p->getName();
sort($pnames);
print_r($pnames);

$pubProps = $rc->getProperties(ReflectionProperty::IS_PUBLIC);
$ppn = [];
foreach ($pubProps as $p) $ppn[] = $p->getName();
sort($ppn);
print_r($ppn);

$consts = $rc->getConstants();
ksort($consts);
print_r($consts);

echo $rc->hasMethod("sound") ? "y" : "n", "\n";
echo $rc->hasMethod("nope") ? "y" : "n", "\n";
echo $rc->hasProperty("breed") ? "y" : "n", "\n";
echo $rc->hasConstant("TYPE") ? "y" : "n", "\n";
echo $rc->hasConstant("KINGDOM") ? "y" : "n", "\n";

$m = $rc->getMethod("describe");
echo $m->getName(), "\n";
echo $m->isPublic() ? "y" : "n", "\n";
echo $m->isStatic() ? "y" : "n", "\n";
echo $m->isFinal() ? "y" : "n", "\n";
echo $m->getDeclaringClass()->getName(), "\n";

$params = $m->getParameters();
print_r(array_map(fn($p) => $p->getName(), $params));

$rt = $m->getReturnType();
echo $rt !== null ? $rt->getName() : "?", "\n";
echo $rt->allowsNull() ? "y" : "n", "\n";

$dog = new Dog("Lab");
echo $m->invoke($dog), "\n";

$mc = $rc->getMethod("__construct");
echo $mc->isConstructor() ? "y" : "n", "\n";
$ctorParams = $mc->getParameters();
echo count($ctorParams), "\n";
echo $ctorParams[0]->getName(), "\n";
echo $ctorParams[0]->getType()->getName(), "\n";

$snd = $rc->getMethod("sound");
echo $snd->getName(), "\n";
echo $snd->getReturnType()->getName(), "\n";
echo $snd->invoke($dog), "\n";

$s = $rc->getMethod("getCount");
echo $s->isStatic() ? "y" : "n", "\n";
echo $s->invoke(null), "\n";
echo $s->invoke(null), "\n";

$rcAnimal = new ReflectionClass("Animal");
$abs = $rcAnimal->getMethod("sound");
echo $abs->isAbstract() ? "y" : "n", "\n";

$rp = $rc->getProperty("breed");
echo $rp->getName(), "\n";
echo $rp->isPublic() ? "y" : "n", "\n";
echo $rp->isStatic() ? "y" : "n", "\n";
echo $rp->getValue($dog), "\n";

$rp = $rc->getProperty("species");
echo $rp->getValue($dog), "\n";

class WithDefault {
    public int $x = 42;
    public string $y = "hello";
}
$rcw = new ReflectionClass("WithDefault");
$rpx = $rcw->getProperty("x");
echo $rpx->getDefaultValue(), "\n";
echo $rcw->getProperty("y")->getDefaultValue(), "\n";

interface Iface { public function go(): void; }
class Impl implements Iface { public function go(): void {} }
$rci = new ReflectionClass("Impl");
$ifaces = $rci->getInterfaceNames();
print_r($ifaces);
echo $rci->implementsInterface("Iface") ? "y" : "n", "\n";

class Wrapper {
    public function multiply(int $a, int $b = 10): int {
        return $a * $b;
    }
}
$rcw2 = new ReflectionClass("Wrapper");
$mm = $rcw2->getMethod("multiply");
$ps = $mm->getParameters();
echo count($ps), "\n";
echo $ps[0]->getName(), " ", $ps[0]->isOptional() ? "opt" : "req", "\n";
echo $ps[1]->getName(), " ", $ps[1]->isOptional() ? "opt" : "req", "\n";
echo $ps[1]->getDefaultValue(), "\n";

$inst = new Wrapper;
echo $mm->invoke($inst, 5, 3), "\n";
echo $mm->invokeArgs($inst, [5, 3]), "\n";
echo $mm->invokeArgs($inst, [5]), "\n";
