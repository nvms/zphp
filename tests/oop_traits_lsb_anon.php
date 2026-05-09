<?php
// abstract class instantiation guard
abstract class A {
    abstract public function foo(): int;
}
try { new A; } catch (Error $e) { echo "abs:", $e->getMessage(), "\n"; }

// trait with abstract method
trait T {
    abstract protected function name(): string;
    public function greet(): string { return "hi " . $this->name(); }
}
class P {
    use T;
    protected function name(): string { return "P"; }
}
echo (new P)->greet(), "\n";

// trait method conflict resolution with insteadof and as
trait T1 { public function hello() { return "T1"; } public function bye() { return "T1bye"; } }
trait T2 { public function hello() { return "T2"; } }
class C {
    use T1, T2 {
        T1::hello insteadof T2;
        T2::hello as helloT2;
        T1::bye as protected byeProt;
    }
}
$c = new C;
echo $c->hello(), " ", $c->helloT2(), "\n";

// interface constants
interface IConst {
    const VERSION = "1.0";
    const MAX = 100;
}
class Impl implements IConst {}
echo Impl::VERSION, " ", Impl::MAX, " ", IConst::VERSION, "\n";

// inheritance with interface constants
interface IExt extends IConst { const EXTRA = "extra"; }
class Impl2 implements IExt {}
echo Impl2::VERSION, " ", Impl2::EXTRA, "\n";

// late static binding (static:: vs self::)
class Base {
    public static function create(): static { return new static; }
    public function selfClass(): string { return self::class; }
    public function staticClass(): string { return static::class; }
    public static function staticName(): string { return static::class; }
    public static function selfName(): string { return self::class; }
}
class Child extends Base {}
$b = new Base;
$c = new Child;
echo $b->selfClass(), "/", $b->staticClass(), "\n";
echo $c->selfClass(), "/", $c->staticClass(), "\n";
echo Base::staticName(), "/", Child::staticName(), "\n";
echo Base::selfName(), "/", Child::selfName(), "\n";
echo get_class(Base::create()), "/", get_class(Child::create()), "\n";

// anonymous class with extends/implements
interface Greeter { public function hi(): string; }
abstract class Shouter { abstract public function shout(): string; }
$o = new class extends Shouter implements Greeter {
    public function hi(): string { return "anon"; }
    public function shout(): string { return "ANON!"; }
};
echo $o->hi(), " ", $o->shout(), "\n";
echo $o instanceof Greeter ? "is-greeter " : "no-greeter ";
echo $o instanceof Shouter ? "is-shouter\n" : "no-shouter\n";

// class with __invoke
class Multi {
    public function __construct(private int $factor) {}
    public function __invoke(int $x): int { return $x * $this->factor; }
}
$double = new Multi(2);
$triple = new Multi(3);
echo $double(5), " ", $triple(5), "\n";
echo is_callable($double) ? "yes\n" : "no\n";
echo array_map($double, [1, 2, 3])[2], "\n";

// callable type hint
function takeCallable(callable $f) { return $f(); }
echo takeCallable(fn() => "lambda"), "\n";
echo takeCallable(fn() => "ok"), "\n";
function takeArgful(callable $f, $a) { return $f($a); }
echo takeArgful("strtoupper", "hi") === "HI" ? "ok\n" : "fail\n";
echo takeArgful($double, 7), "\n";

// abstract class with concrete methods
abstract class Tool {
    public function describe(): string { return "tool: " . $this->name(); }
    abstract public function name(): string;
}
class Hammer extends Tool { public function name(): string { return "hammer"; } }
echo (new Hammer)->describe(), "\n";

// asort/ksort stability (PHP 8 stable)
$a = [
    "z" => ["g" => 2, "n" => "Carol"],
    "a" => ["g" => 1, "n" => "Alice"],
    "b" => ["g" => 1, "n" => "Bob"],
    "y" => ["g" => 2, "n" => "Dave"],
];
uasort($a, fn($x, $y) => $x["g"] <=> $y["g"]);
foreach ($a as $k => $v) echo "$k=$v[n] ";
echo "\n";

// usort stability (PHP 8 guarantees stable)
$arr = [["g" => 2, "n" => "Carol"], ["g" => 1, "n" => "Alice"], ["g" => 1, "n" => "Bob"], ["g" => 2, "n" => "Dave"]];
usort($arr, fn($x, $y) => $x["g"] <=> $y["g"]);
foreach ($arr as $v) echo $v["n"], " ";
echo "\n";

// generator with throw catching
function genWithCatch() {
    try {
        yield 1;
        yield 2;
        yield 3;
    } catch (Exception $e) {
        yield "caught:" . $e->getMessage();
        yield "after-catch";
    }
}
$g = genWithCatch();
echo $g->current(), "\n";
$g->throw(new Exception("hi"));
echo $g->current(), "\n";
$g->next();
echo $g->current(), "\n";
var_dump($g->valid());
$g->next();
var_dump($g->valid());

// ArrayObject foreach with ARRAY_AS_PROPS
$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3], ArrayObject::ARRAY_AS_PROPS);
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
echo $ao->a, " ", $ao->b, "\n";
$ao->d = 4;
echo $ao["d"], "\n";

// ArrayIterator
$ai = new ArrayIterator(["x" => 10, "y" => 20]);
foreach ($ai as $k => $v) echo "$k=$v ";
echo "\n";
echo $ai->count(), "\n";

// str_pad with too-short output (no truncation in PHP)
echo str_pad("abcdefgh", 5, "*"), "|\n";  // returns "abcdefgh" - no truncation
echo str_pad("hi", 0, "*"), "|\n";
echo str_pad("hi", -5, "*"), "|\n"; // negative width: returns as-is

// var_export of deep nested
echo var_export(["a" => ["b" => ["c" => [1, 2, 3]]]], true), "\n";
