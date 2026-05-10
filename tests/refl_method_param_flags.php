<?php
// ReflectionMethod flags
abstract class Base {
    abstract public function abs(): void;
    public static function st(): int { return 1; }
    final public function fi(): int { return 2; }
    public function plain(): int { return 3; }
    final public static function fs(): int { return 4; }
    private function priv(): void {}
}

class Sub extends Base {
    public function abs(): void {}
}

$rc = new ReflectionClass(Base::class);
foreach (['abs', 'st', 'fi', 'plain', 'fs', 'priv'] as $m) {
    $rm = $rc->getMethod($m);
    echo "$m: abstract=", $rm->isAbstract() ? "y" : "n",
         " static=", $rm->isStatic() ? "y" : "n",
         " final=", $rm->isFinal() ? "y" : "n",
         " public=", $rm->isPublic() ? "y" : "n",
         " private=", $rm->isPrivate() ? "y" : "n",
         "\n";
}

// ReflectionParameter
function fpType(int $a, ?string $b, array $c = [1,2], ?int $d = null, mixed $e = "hi"): bool { return true; }
$rf = new ReflectionFunction('fpType');
foreach ($rf->getParameters() as $p) {
    echo $p->getName(),
         " optional=", $p->isOptional() ? "y" : "n",
         " allowsNull=", $p->allowsNull() ? "y" : "n";
    $t = $p->getType();
    if ($t) {
        echo " type=", (string)$t, " name=", $t->getName(), " builtin=", $t->isBuiltin() ? "y" : "n";
    } else {
        echo " no-type";
    }
    echo "\n";
}

// ReflectionType __toString and getName for various
function ft(int $a, ?string $b, mixed $c, array $d, string|int $f = 1): MixedReturn|null { return null; }
class MixedReturn {}
$rf = new ReflectionFunction('ft');
foreach ($rf->getParameters() as $p) {
    $t = $p->getType();
    echo $p->getName(), ":";
    if ($t === null) {
        echo "null";
    } else {
        echo (string)$t;
        if (method_exists($t, "getName")) echo " name:", $t->getName();
        if (method_exists($t, "isBuiltin")) echo " builtin:", $t->isBuiltin() ? "y" : "n";
    }
    echo "\n";
}

// ReflectionNamedType::isBuiltin for various
class Custom {}
function fb(int $a, string $b, array $c, bool $d, float $e, mixed $f, Custom $g, ?Custom $h, callable $i, iterable $j): void {}
$rf = new ReflectionFunction('fb');
foreach ($rf->getParameters() as $p) {
    $t = $p->getType();
    if ($t instanceof ReflectionNamedType) {
        echo $p->getName(), ":", $t->getName(), ":", $t->isBuiltin() ? "y" : "n", "\n";
    }
}

// attribute target
#[Attribute(Attribute::TARGET_CLASS)]
class ClassOnly {
    public function __construct(public string $name = "x") {}
}

#[ClassOnly("ok")]
class C {}

try {
    $rc = new ReflectionClass(C::class);
    $attrs = $rc->getAttributes();
    echo count($attrs), "\n";
    $inst = $attrs[0]->newInstance();
    echo $inst->name, "\n";
} catch (\Throwable $e) { echo "err:", $e->getMessage(), "\n"; }

// #[Override] on missing parent method
class P1 { public function foo(): void {} }
class P2 extends P1 {
    #[\Override]
    public function foo(): void {} // valid
}
echo "override-ok\n";

// enum implements interface, called via interface ref
interface Describable {
    public function describe(): string;
}
enum Color: string implements Describable {
    case Red = "red";
    case Blue = "blue";
    public function describe(): string {
        return "color:" . $this->value;
    }
}
function takeIface(Describable $d): string { return $d->describe(); }
echo takeIface(Color::Red), "|", takeIface(Color::Blue), "\n";

$arr = [Color::Red, Color::Blue];
foreach ($arr as $c) echo $c->describe(), " ";
echo "\n";

// enum static method
enum Action { case Start; case Stop;
    public static function default(): self { return self::Start; }
}
echo Action::default()->name, "\n";

// readonly enum const
enum Level: int {
    const MAX = 10;
    case Low = 1;
    case High = 9;
    public function isMax(): bool { return $this->value >= self::MAX - 1; }
}
echo Level::High->isMax() ? "y" : "n", "\n";
echo Level::Low->isMax() ? "y" : "n", "\n";

// match with enum and default
$c = Color::Red;
$msg = match (true) {
    $c === Color::Red => "warm",
    $c === Color::Blue => "cool",
};
echo $msg, "\n";

// __invoke on enum (not allowed by PHP)
enum Switchy {
    case On;
    case Off;
}
echo Switchy::On->name, "\n";
