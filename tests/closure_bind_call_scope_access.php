<?php
class A {
    public int $x = 1;
    private int $y = 2;
    protected int $z = 3;
}

$f = function () { return [$this->x, $this->y, $this->z]; };
$bound = Closure::bind($f, new A, A::class);
print_r($bound());

$bound2 = $f->bindTo(new A, A::class);
print_r($bound2());

$bound3 = $f->bindTo(new A, "A");
print_r($bound3());

class B {
    public function callIt(Closure $c): mixed {
        return $c();
    }
}

$cl = function () { return spl_object_id($this); };
$obj = new A;
$r = $cl->call($obj);
echo is_int($r) ? "y" : "n", "\n";

$cl = function () { return $this->x; };
echo $cl->call(new A), "\n";

class Pub {
    public string $name = "p";
}
class Priv {
    private string $secret = "hidden";
}

$reader = function () { return $this->secret; };
$bound = Closure::bind($reader, new Priv, Priv::class);
echo $bound(), "\n";

$bound = $reader->bindTo(new Priv, Priv::class);
echo $bound(), "\n";

$reader = function () { return $this->secret; };
try {
    $bound = Closure::bind($reader, new Priv, Pub::class);
    echo $bound(), "\n";
} catch (\Throwable $e) {
    echo "ex:", get_class($e), "\n";
}

$cl = function () { return self::class; };
$bound = Closure::bind($cl, null, A::class);
echo $bound(), "\n";

class Parent_ {
    public static function name(): string { return static::class; }
}
class Child_ extends Parent_ {}

$cl = function () { return static::name(); };
$bound = Closure::bind($cl, null, Parent_::class);
echo $bound(), "\n";
$bound = Closure::bind($cl, null, Child_::class);
echo $bound(), "\n";

$static_cl = static function () { return "static"; };
$bound = Closure::bind($static_cl, null);
echo $bound(), "\n";

class HasMethod {
    private int $val = 99;
    public function getReader(): Closure {
        return function () { return $this->val; };
    }
}
$h = new HasMethod;
$reader = $h->getReader();
echo $reader(), "\n";

$cl = function () { return get_class($this); };
echo $cl->call(new A), "\n";
echo $cl->call(new Priv), "\n";

$f = fn() => $this->x;
echo $f->call(new A), "\n";

class WithConst {
    public const X = 100;
    private const SECRET = 999;
}

$cl = function () { return self::SECRET; };
$bound = Closure::bind($cl, null, WithConst::class);
echo $bound(), "\n";

$cl = function () { return WithConst::X; };
echo $cl(), "\n";

class WithStaticProp {
    public static int $count = 0;
    public static function increment(): int { return ++self::$count; }
}

$cl = function () { return self::$count; };
$bound = Closure::bind($cl, null, WithStaticProp::class);
echo $bound(), "\n";

$cl = function () { self::$count = 42; };
$bound = Closure::bind($cl, null, WithStaticProp::class);
$bound();
echo WithStaticProp::$count, "\n";

$multiplier = 10;
$f = function (int $x) use ($multiplier) { return $x * $multiplier; };
echo $f(5), "\n";

class C {
    public string $prefix = "p:";
    public function buildFn(): Closure {
        return function (string $name): string { return $this->prefix . $name; };
    }
}
$fn = (new C)->buildFn();
echo $fn("test"), "\n";

class D {
    public function __invoke(): string { return "invoked"; }
}
$d = new D;
echo $d(), "\n";

$arr = [1, 2, 3, 4, 5];
$squared = array_map(fn($x) => $x ** 2, $arr);
print_r($squared);

class Counter {
    private int $n = 0;
    public function makeInc(): Closure {
        return function () { return ++$this->n; };
    }
}

$c = new Counter;
$inc = $c->makeInc();
echo $inc(), " ", $inc(), " ", $inc(), "\n";

$reader = function () { return $this->x; };
$bound1 = $reader->bindTo(new A, A::class);
$bound2 = $reader->bindTo(new A, A::class);
echo $bound1 === $bound2 ? "same" : "diff", "\n";

$cl = Closure::fromCallable("strtoupper");
echo $cl("hello"), "\n";

try {
    $o = new A;
    $cl = Closure::fromCallable([$o, "__construct"]);
    echo "no\n";
} catch (\TypeError $e) {
    echo "te\n";
}

class Inv {
    public function __invoke(int $x): int { return $x * 2; }
}
$cl = Closure::fromCallable(new Inv);
echo $cl(5), "\n";
