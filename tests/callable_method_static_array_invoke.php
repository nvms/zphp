<?php
class Calc {
    public function add(int $a, int $b): int { return $a + $b; }
    public function mul(int $a, int $b): int { return $a * $b; }
    public static function neg(int $x): int { return -$x; }
    public static function abs(int $x): int { return $x < 0 ? -$x : $x; }
}

$c = new Calc;
echo $c->add(2, 3), "\n";
echo $c->mul(4, 5), "\n";
echo Calc::neg(10), "\n";

$fn = [$c, "add"];
echo $fn(7, 3), "\n";
echo call_user_func($fn, 1, 2), "\n";
echo call_user_func_array($fn, [10, 20]), "\n";

$fn = ["Calc", "neg"];
echo $fn(15), "\n";
echo call_user_func($fn, 25), "\n";

$fn = "Calc::abs";
echo call_user_func($fn, -42), "\n";

$add = $c->add(...);
echo $add(2, 3), "\n";
echo $add(10, 20), "\n";

$neg = Calc::neg(...);
echo $neg(100), "\n";

$abs = "Calc::abs"(...);
echo $abs(-5), "\n";

$str = strtoupper(...);
echo $str("hello"), "\n";

$rev = strrev(...);
echo $rev("abc"), "\n";

class Map {
    public function trans(int $x): int { return $x * 10; }
}
$m = new Map;
$tr = $m->trans(...);
$nums = [1, 2, 3, 4, 5];
print_r(array_map($tr, $nums));

$add = fn($a, $b) => $a + $b;
echo $add(1, 2), "\n";

$multiplier = function ($factor) {
    return function ($x) use ($factor) { return $x * $factor; };
};
$x10 = $multiplier(10);
$x100 = $multiplier(100);
echo $x10(5), " ", $x100(5), "\n";

$cl = Closure::fromCallable([$c, "add"]);
echo $cl(3, 4), "\n";

$cl = Closure::fromCallable("strtolower");
echo $cl("HELLO"), "\n";

$cl = Closure::fromCallable(["Calc", "neg"]);
echo $cl(50), "\n";

class WithInvoke {
    public function __invoke(int $x): int { return $x + 100; }
}
$inv = new WithInvoke;
$cl = Closure::fromCallable($inv);
echo $cl(5), "\n";

function myFunc(int $x): int { return $x * 7; }
$arr = [1, 2, 3];
print_r(array_map("myFunc", $arr));

$cl = myFunc(...);
print_r(array_map($cl, [10, 20, 30]));

class Person {
    public function __construct(public string $name) {}
    public function greet(): string { return "hello, " . $this->name; }
}

$p1 = new Person("alice");
$p2 = new Person("bob");
$gp1 = $p1->greet(...);
$gp2 = $p2->greet(...);
echo $gp1(), "\n";
echo $gp2(), "\n";

echo is_callable($gp1) ? "y" : "n", "\n";
echo is_callable([$p1, "greet"]) ? "y" : "n", "\n";
echo is_callable("Calc::abs") ? "y" : "n", "\n";
echo is_callable("strtolower") ? "y" : "n", "\n";
echo is_callable("doesNotExist") ? "y" : "n", "\n";
echo is_callable([$p1, "nope"]) ? "y" : "n", "\n";
echo is_callable(fn($x) => $x) ? "y" : "n", "\n";

class Inv2 {
    public function __invoke(): string { return "called"; }
}
echo is_callable(new Inv2) ? "y" : "n", "\n";
echo (new Inv2)(), "\n";

$result = array_map(fn($x) => $x ** 2, [1, 2, 3]);
print_r($result);

class Multi {
    public function process(array $items): array {
        return array_map([$this, "transform"], $items);
    }
    public function transform(int $x): int { return $x + 1; }
}

$m = new Multi;
print_r($m->process([1, 2, 3]));

function compose(callable ...$fns): callable {
    return fn($x) => array_reduce($fns, fn($acc, $f) => $f($acc), $x);
}

$pipeline = compose(
    fn($x) => $x + 1,
    fn($x) => $x * 2,
    fn($x) => $x - 3
);
echo $pipeline(5), "\n";

$cb = function ($n) { return $n + 10; };
echo $cb(5), "\n";

class Static_ {
    public static function transform(int $x): int { return $x * 100; }
}
$static_cb = Static_::transform(...);
print_r(array_map($static_cb, [1, 2, 3]));

$arr_cb_static = ["Static_", "transform"];
echo $arr_cb_static(5), "\n";

class Caller {
    public function dynamicCall(string $method, array $args): mixed {
        return [$this, $method](...$args);
    }
    public function go(int $x): int { return $x * 2; }
}
$c = new Caller;
echo $c->dynamicCall("go", [21]), "\n";

class HasMagic {
    public function __call(string $name, array $args): string {
        return "magic:$name(" . implode(",", $args) . ")";
    }
}
$hm = new HasMagic;
echo $hm->whatever(1, 2, 3), "\n";
echo $hm->anything("a", "b"), "\n";
