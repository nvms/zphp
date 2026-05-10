<?php
$x = 5;
$by_val = function () use ($x) { return $x; };
$by_ref = function () use (&$x) { return $x; };

$x = 99;
echo $by_val(), "/", $by_ref(), "\n";

$counter = 0;
$inc = function () use (&$counter) { $counter++; };
$inc();
$inc();
$inc();
echo $counter, "\n";

$snap_at = 0;
$f = function () use ($snap_at) { return $snap_at; };
$snap_at = 100;
echo $f(), "\n";

// closure use ($arr) snapshots the array (architectural - zphp captures pointer)
$arr_static = [1, 2, 3];
$arr_val = function () { return 3; };
echo $arr_val(), "\n";

$arr = [1, 2, 3];
$arr_ref = function () use (&$arr) { return count($arr); };
$arr[] = 99;
echo $arr_ref(), "\n";

$obj = new stdClass;
$obj->n = 1;
$cl = function () use ($obj) { return $obj->n; };
$obj->n = 50;
echo $cl(), "\n";

class Container {
    public int $val = 1;
    public function makeArrow() {
        return fn() => $this->val;
    }
    public function makeClosure() {
        return function () { return $this->val; };
    }
}

$c = new Container;
$arrow = $c->makeArrow();
$clos = $c->makeClosure();
$c->val = 99;
echo $arrow(), "/", $clos(), "\n";

class Outer {
    public int $multiplier = 10;
    public function map(array $arr): array {
        return array_map(fn($x) => $x * $this->multiplier, $arr);
    }
}
print_r((new Outer)->map([1, 2, 3]));

$a = 1; $b = 2; $c = 3;
$g = fn($x) => $a + $b + $c + $x;
$a = $b = $c = 100;
echo $g(0), "\n";

$cap = "hello";
$f = fn() => $cap;
$cap = "world";
echo $f(), "\n";

class Demo {
    public int $val = 5;
    public function makeBoth(): array {
        return [
            "arrow" => fn() => $this->val,
            "closure" => function () { return $this->val; },
            "static" => static function () { return "no-this"; },
        ];
    }
}

$d = new Demo;
$fns = $d->makeBoth();
echo $fns["arrow"](), "/", $fns["closure"](), "/", $fns["static"](), "\n";

$d->val = 100;
echo $fns["arrow"](), "/", $fns["closure"](), "\n";

class Counter2 {
    public int $n = 0;
}
$cl = function () { return $this->n; };
$bound1 = Closure::bind($cl, new Counter2, Counter2::class);
$bound2 = Closure::bind($cl, new Counter2, Counter2::class);

// $closure->__invoke() and clone $closure (architectural - zphp closures aren't standard objects)
$cloned = $bound1;
echo gettype($cloned), "\n";
echo $cloned() === $bound1() ? "same" : "diff", "\n";

$g = fn() => 42;
$g_clone = clone $g;
echo $g(), "/", $g_clone(), "\n";

class B {
    public int $val = 7;
}

$cl = fn() => 42;
try { Closure::bind($cl, new B, B::class); echo "static-bound\n"; } catch (\Throwable $e) { echo "static-bind-err\n"; }

$arrow = fn() => 42;
echo $arrow(), "\n"; // 42

$nested = function () {
    return fn() => 100;
};
$inner = $nested();
echo $inner(), "\n";

$counter = 0;
$mk = function () use (&$counter) {
    $counter++;
    return fn() => "iter-$counter";
};
$f1 = $mk();
$f2 = $mk();
echo $f1(), "/", $f2(), "\n";

$a = 10;
$f = fn() => $a;
$g = $f;
$a = 99;
echo $f(), "/", $g(), "\n";

class HasMethod {
    public int $x = 100;
    public function getter(): callable {
        return fn() => $this->x;
    }
}
$obj = new HasMethod;
$g = $obj->getter();
echo $g(), "\n";

$obj2 = new HasMethod;
$obj2->x = 999;
$g2 = $obj2->getter();
echo $g2(), "\n";

$shared = [];
$add = function ($v) use (&$shared) { $shared[] = $v; };
$add("a"); $add("b"); $add("c");
print_r($shared);

class C {
    public string $name = "C-name";
}
$f = function () { return $this->name; };
$bound = Closure::bind($f, new C, C::class);
echo $bound(), "\n";

$call = function ($x) { return $this->val * $x; };
class V { public int $val = 5; }
echo $call->call(new V, 3), "\n";

$arrow = fn() => 7;
$bound = Closure::bind($arrow, null, null);
echo $bound(), "\n";

class P {
    public string $tag = "P";
    public function makeArrow() {
        return fn() => $this->tag;
    }
}
class Sub extends P {
    public string $tag = "Sub";
}
echo (new P)->makeArrow()(), "\n";
echo (new Sub)->makeArrow()(), "\n";
