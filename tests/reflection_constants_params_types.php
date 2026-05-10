<?php
class C {
    public const A = 1;
    public const B = "hello";
    public const C = [1, 2, 3];
}

$rc = new ReflectionClass(C::class);
$consts = $rc->getConstants();
print_r($consts);

$consts2 = $rc->getReflectionConstants();
echo gettype($consts2), " count=", count($consts2), "\n";

foreach ($consts2 as $rc_c) {
    echo $rc_c->getName(), "=", var_export($rc_c->getValue(), true), "\n";
}

class Methods {
    public function noArgs(): void {}
    public function oneArg(int $a): int { return $a; }
    public function withDefault(int $a, int $b = 5): int { return $a + $b; }
    public function variadic(int ...$xs): int { return array_sum($xs); }
    public function nullable(?int $a, ?string $b): string { return ""; }
    public function complex(int $a, string $b = "x", int $c = 0, ?array $d = null): void {}
}

$rc = new ReflectionClass(Methods::class);

foreach (["noArgs", "oneArg", "withDefault", "variadic", "nullable", "complex"] as $name) {
    $rm = $rc->getMethod($name);
    echo $name, ": params=", $rm->getNumberOfParameters(),
        " required=", $rm->getNumberOfRequiredParameters(), "\n";
}

$rm = $rc->getMethod("complex");
$params = $rm->getParameters();
foreach ($params as $p) {
    echo $p->getName(), " pos=", $p->getPosition(), " optional=", $p->isOptional() ? "y" : "n";
    echo " hasdef=", $p->isDefaultValueAvailable() ? "y" : "n";
    if ($p->isDefaultValueAvailable()) {
        echo " def=", var_export($p->getDefaultValue(), true);
    }
    echo " allowsnull=", $p->allowsNull() ? "y" : "n";
    echo " variadic=", $p->isVariadic() ? "y" : "n";
    echo "\n";
}

function topLevel(int $x, string $y = "z"): bool {
    return true;
}

$rf = new ReflectionFunction("topLevel");
echo $rf->getName(), " params=", $rf->getNumberOfParameters(), "\n";

foreach ($rf->getParameters() as $p) {
    echo $p->getName(), " optional=", $p->isOptional() ? "y" : "n", "\n";
}

$cl = function (int $a, int $b = 10): int { return $a + $b; };
$rf = new ReflectionFunction($cl);
echo "closure: params=", $rf->getNumberOfParameters(),
    " required=", $rf->getNumberOfRequiredParameters(), "\n";

class WithType {
    public function method1(int $x): string { return ""; }
    public function method2(?string $y): ?int { return null; }
    public function method3(int|string $z): mixed { return null; }
}

$rc = new ReflectionClass(WithType::class);

foreach (["method1", "method2", "method3"] as $m) {
    $rm = $rc->getMethod($m);
    $rt = $rm->getReturnType();
    if ($rt instanceof ReflectionNamedType) {
        echo $m, " ret=", $rt->getName(), " nullable=", $rt->allowsNull() ? "y" : "n", "\n";
    } elseif ($rt instanceof ReflectionUnionType) {
        echo $m, " union=", "u", "\n";
    } else {
        echo $m, " ret=", get_class($rt), "\n";
    }

    foreach ($rm->getParameters() as $p) {
        $pt = $p->getType();
        if ($pt instanceof ReflectionNamedType) {
            echo "  ", $p->getName(), ": ", $pt->getName(), " nullable=", $pt->allowsNull() ? "y" : "n", "\n";
        } else {
            echo "  ", $p->getName(), ": multi\n";
        }
    }
}

class WithDocs {
    public int $x = 1;
}

$rc = new ReflectionClass(WithDocs::class);
echo $rc->getName(), "\n";
echo $rc->getShortName(), "\n";

class CC {
    public function __construct(int $a, string $b = "x") {}
}
$rc = new ReflectionClass(CC::class);
$ctor = $rc->getConstructor();
echo $ctor === null ? "null" : $ctor->getName(), "\n";

class NoCtor {}
$rc = new ReflectionClass(NoCtor::class);
$ctor = $rc->getConstructor();
echo $ctor === null ? "null" : "has", "\n";

$rc = new ReflectionClass(C::class);
echo "isFinal=", $rc->isFinal() ? "y" : "n", "\n";
echo "isAbstract=", $rc->isAbstract() ? "y" : "n", "\n";

abstract class Abst { abstract public function go(): void; }
$rc = new ReflectionClass(Abst::class);
echo "abs-final=", $rc->isFinal() ? "y" : "n", "\n";
echo "abs-abstract=", $rc->isAbstract() ? "y" : "n", "\n";

final class Fnl {}
$rc = new ReflectionClass(Fnl::class);
echo "fnl-final=", $rc->isFinal() ? "y" : "n", "\n";

interface IFoo {
    public function f(): void;
}
class Impl implements IFoo {
    public function f(): void {}
}
$rc = new ReflectionClass(Impl::class);
foreach ($rc->getInterfaceNames() as $i) echo $i, " ";
echo "\n";

class Sub extends C {}
$rc = new ReflectionClass(Sub::class);
$consts = $rc->getConstants();
print_r($consts);
