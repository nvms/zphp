<?php
// abstract class with constructor
abstract class Shape {
    public function __construct(public string $name) {}
    abstract public function area(): float;
    public function describe(): string { return "{$this->name}: " . $this->area(); }
}
class Circle extends Shape {
    public function __construct(public float $r) { parent::__construct("circle"); }
    public function area(): float { return 3.14 * $this->r * $this->r; }
}
echo (new Circle(2))->describe(), "\n";

// can't instantiate abstract
try { $s = (new ReflectionClass(Shape::class))->newInstanceArgs(["x"]); } catch (\Error $e) { echo "cant\n"; }

// interface constants and inheritance
interface IA { const FOO = "fooA"; public function ping(): string; }
interface IB extends IA { const BAR = "bar"; }
class C1 implements IB { public function ping(): string { return "pong"; } }
echo C1::FOO, "|", C1::BAR, "\n";
echo IA::FOO, "|", IB::FOO, "|", IB::BAR, "\n";
$c = new C1;
echo $c::FOO, "\n";

// trait conflict by alias only
trait T1 { public function method(): string { return "t1"; } }
trait T2 { public function method(): string { return "t2"; } }
class CT {
    use T1, T2 { T1::method insteadof T2; T2::method as t2method; }
}
$o = new CT;
echo $o->method(), "|", $o->t2method(), "\n";

// trait with property
trait Counter {
    private int $count = 0;
    public function inc(): void { $this->count++; }
    public function get(): int { return $this->count; }
}
class Tally { use Counter; }
$t = new Tally;
$t->inc(); $t->inc(); $t->inc();
echo $t->get(), "\n";

// trait with abstract + static
trait WithStatic {
    public static function whoami(): string { return static::class; }
}
class StatA { use WithStatic; }
class StatB extends StatA { use WithStatic; }
echo StatA::whoami(), "|", StatB::whoami(), "\n";

// static::class vs self::class
class Animal {
    public function selfName(): string { return self::class; }
    public function staticName(): string { return static::class; }
}
class Dog extends Animal {}
$d = new Dog;
echo $d->selfName(), "|", $d->staticName(), "\n"; // Animal|Dog

// late binding with new static
class Tree { public static function make(): static { return new static(); } }
class Oak extends Tree {}
echo get_class(Tree::make()), "|", get_class(Oak::make()), "\n";

// constructor promotion with default
class Coord { public function __construct(public int $x = 0, public int $y = 0, public int $z = 0) {} }
$c = new Coord(y: 5);
echo $c->x, ",", $c->y, ",", $c->z, "\n";

// readonly + clone with mutation in __clone
class Pos {
    public function __construct(public readonly int $x, public readonly int $y) {}
    public function __clone(): void { /* readonly props can be mutated in __clone */ }
}
$p1 = new Pos(1, 2);
$p2 = clone $p1;
echo $p1->x, ",", $p2->y, "\n";

// final method in interface (PHP doesn't allow but test)
interface IF1 { public function action(): void; }
class CF1 implements IF1 { public function action(): void { echo "act!"; } }
(new CF1)->action();
echo "\n";

// abstract method with type hint signature
abstract class Filter { abstract public function apply(string $s): string; }
class UpperFilter extends Filter { public function apply(string $s): string { return strtoupper($s); } }
echo (new UpperFilter)->apply("hello"), "\n";

// invokable nested
class Pipeline {
    private array $steps;
    public function __construct(array $steps) { $this->steps = $steps; }
    public function __invoke(mixed $x): mixed {
        foreach ($this->steps as $s) $x = $s($x);
        return $x;
    }
}
$p = new Pipeline([fn($x) => $x + 1, fn($x) => $x * 2, fn($x) => "result:$x"]);
echo $p(3), "\n";

// __set on dynamic property
class Lazy {
    private array $cache = [];
    public function __get($k) { return $this->cache[$k] ?? null; }
    public function __set($k, $v) { $this->cache[$k] = $v; }
}
$l = new Lazy;
$l->foo = 1;
$l->bar = 2;
echo $l->foo, "|", $l->bar, "\n";

// __toString
class Box {
    public function __construct(public int $n) {}
    public function __toString(): string { return "Box[$this->n]"; }
}
echo new Box(42), "\n";
echo "wrapped:" . (new Box(7)), "\n";

// instanceof with class string
class A1 {}
class B1 extends A1 {}
$b = new B1;
$cls = "A1";
var_dump($b instanceof $cls);
var_dump($b instanceof A1);

// is_subclass_of / is_a
var_dump(is_a($b, A1::class));
var_dump(is_a('B1', A1::class, true));
var_dump(is_subclass_of($b, A1::class));
var_dump(is_subclass_of($b, B1::class)); // false (not strict subclass)
var_dump(is_subclass_of('B1', A1::class));

// class_implements / class_parents / class_uses
print_r(class_implements(C1::class)); // IA, IB
print_r(class_parents(B1::class)); // A1
print_r(class_uses(CT::class));

// get_class with no arg in method
class Self2 {
    public function name(): string { return get_class($this); }
}
echo (new Self2)->name(), "\n";

// return-by-ref through method not fully supported (architectural)

// chained method calls
class Builder {
    private array $parts = [];
    public function add(string $s): self { $this->parts[] = $s; return $this; }
    public function build(): string { return implode("-", $this->parts); }
}
echo (new Builder)->add("a")->add("b")->add("c")->build(), "\n";

// late static + self
class Base3 {
    public static function id(): string { return self::class . "/" . static::class; }
}
class Sub3 extends Base3 {}
echo Base3::id(), "|", Sub3::id(), "\n";
