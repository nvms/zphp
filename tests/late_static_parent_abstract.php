<?php
class Animal {
    public static function classNameSelf(): string { return self::class; }
    public static function classNameStatic(): string { return static::class; }
    public static function make(): static { return new static; }
    public function instSelf(): string { return self::class; }
    public function instStatic(): string { return static::class; }
}
class Dog extends Animal {}
class Beagle extends Dog {}

echo Animal::classNameSelf(), "\n";
echo Dog::classNameSelf(), "\n";
echo Animal::classNameStatic(), "\n";
echo Dog::classNameStatic(), "\n";
echo Beagle::classNameStatic(), "\n";

echo get_class(Animal::make()), "\n";
echo get_class(Dog::make()), "\n";
echo get_class(Beagle::make()), "\n";

$d = new Dog;
echo $d->instSelf(), " ", $d->instStatic(), "\n";

$b = new Beagle;
echo $b->instSelf(), " ", $b->instStatic(), "\n";

class Greeter {
    protected static string $greeting = "hello";
    public static function greet(): string { return static::$greeting; }
}
class FrenchGreeter extends Greeter {
    protected static string $greeting = "bonjour";
}
class GermanGreeter extends Greeter {
    protected static string $greeting = "hallo";
}
echo Greeter::greet(), "\n";
echo FrenchGreeter::greet(), "\n";
echo GermanGreeter::greet(), "\n";

class Box {
    public int $size = 10;
    public function describe(): string {
        return "Box(size=$this->size)";
    }
}
class BigBox extends Box {
    public int $size = 100;
    public function describe(): string {
        return parent::describe() . "/Big";
    }
}
$b = new BigBox;
echo $b->describe(), "\n";

class A {
    public function show(): string { return "A"; }
}
class B extends A {
    public function show(): string { return parent::show() . "B"; }
}
class C extends B {
    public function show(): string { return parent::show() . "C"; }
}
echo (new C)->show(), "\n";

class WithCtor {
    public function __construct(public string $name) {}
}
class SubCtor extends WithCtor {
    public function __construct(string $name, public int $age) {
        parent::__construct($name);
    }
}
$s = new SubCtor("alice", 30);
echo $s->name, "/", $s->age, "\n";

abstract class AbstractA {
    abstract public function go(): string;
    public function call(): string { return $this->go() . "!"; }
}
class ConcreteA extends AbstractA {
    public function go(): string { return "concrete"; }
}
echo (new ConcreteA)->call(), "\n";

try { new AbstractA; echo "no\n"; }
catch (\Error $e) { echo "abs-instantiate-err\n"; }

abstract class HasAbs {
    abstract public function impl(): int;
    public function done(): int { return $this->impl() + 1; }
}
class HalfDone extends HasAbs {
    public function impl(): int { return 10; }
}
echo (new HalfDone)->done(), "\n";

abstract class StillAbs extends HasAbs {}
class Final1 extends StillAbs {
    public function impl(): int { return 5; }
}
echo (new Final1)->done(), "\n";

try { new StillAbs; echo "no\n"; }
catch (\Error $e) { echo "abs-extends\n"; }

class Chain {
    public static function level(): int { return 0; }
    public static function call(): int { return static::level(); }
}
class Lvl1 extends Chain {
    public static function level(): int { return 1; }
}
class Lvl2 extends Lvl1 {
    public static function level(): int { return 2; }
}
echo Chain::call(), "\n";
echo Lvl1::call(), "\n";
echo Lvl2::call(), "\n";

class Q {
    public function name(): string { return static::class; }
}
class R extends Q {}
class T extends R {}
echo (new R)->name(), " ", (new T)->name(), " ", (new Q)->name(), "\n";

class Op {
    public static function map(array $a): array {
        return array_map([static::class, "transform"], $a);
    }
    public static function transform(int $n): int { return $n; }
}
class Doubler extends Op {
    public static function transform(int $n): int { return $n * 2; }
}
print_r(Op::map([1, 2, 3]));
print_r(Doubler::map([1, 2, 3]));

abstract class HasName {
    abstract public function name(): string;
    public function greet(): string {
        return "Hi, " . $this->name() . "!";
    }
}
class Named extends HasName {
    public function __construct(private string $myname) {}
    public function name(): string { return $this->myname; }
}
echo (new Named("Bob"))->greet(), "\n";

interface Shaped {
    public function area(): float;
}
class Square implements Shaped {
    public function __construct(public float $side) {}
    public function area(): float { return $this->side * $this->side; }
}
echo (new Square(3.0))->area(), "\n";

abstract class Base {
    public function __construct(public string $type) {}
    abstract public function what(): string;
}
class Derived extends Base {
    public function __construct(string $type, public int $extra) {
        parent::__construct($type);
    }
    public function what(): string { return "type=$this->type/extra=$this->extra"; }
}
echo (new Derived("X", 7))->what(), "\n";

class Inheritor {
    public static function whoAmI(): string {
        return static::class . "/" . self::class;
    }
}
class Sub1 extends Inheritor {}
echo Sub1::whoAmI(), "\n";

class HasCtorChain {
    public string $log = "A";
    public function __construct() { $this->log .= "+A"; }
}
class HasCtorChain2 extends HasCtorChain {
    public function __construct() { parent::__construct(); $this->log .= "+B"; }
}
class HasCtorChain3 extends HasCtorChain2 {
    public function __construct() { parent::__construct(); $this->log .= "+C"; }
}
echo (new HasCtorChain3)->log, "\n";
