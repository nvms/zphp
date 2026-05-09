<?php
// Closure binding with private access
class Counter {
    private int $n = 0;
    private array $history = [];
    public static function getInc(): Closure {
        return function () {
            $this->n++;
            $this->history[] = $this->n;
            return $this->n;
        };
    }
}
$inc = Closure::bind(Counter::getInc(), new Counter, Counter::class);
echo $inc(), ":", $inc(), ":", $inc(), "\n"; // 1:2:3

// invokable class with args
class Memo {
    private array $cache = [];
    public function __invoke(string $k, callable $cb): mixed {
        return $this->cache[$k] ??= $cb();
    }
}
$m = new Memo();
echo $m("a", fn() => 1), "|", $m("a", fn() => 999), "|", $m("b", fn() => 2), "\n"; // 1|1|2

// generator delegation
function counter1to3() { yield 1; yield 2; yield 3; }
function counter4to6() { yield 4; yield 5; yield 6; }
function combined() {
    yield from counter1to3();
    yield 0;
    yield from counter4to6();
}
foreach (combined() as $v) echo "$v ";
echo "\n";

// generator key preservation
function keyed1() { yield "a" => 1; yield "b" => 2; }
function keyed2() { yield "c" => 3; yield "d" => 4; }
function bothKeyed() {
    yield from keyed1();
    yield from keyed2();
}
foreach (bothKeyed() as $k => $v) echo "$k=$v ";
echo "\n";

// generator send / receive
function echoer() {
    while (true) {
        $x = yield;
        if ($x === null) return;
        echo "got:$x|";
    }
}
$g = echoer();
$g->send("a");
$g->send("b");
$g->send("c");
$g->send(null);
echo "\n";

// Closure::call vs ->bindTo
class Vec { public int $x = 1; public int $y = 2; }
$cl = function () { return $this->x + $this->y; };
$v = new Vec;
echo $cl->call($v), "\n"; // 3
$bound = $cl->bindTo($v);
echo $bound(), "\n"; // 3

// match true with enum
enum Stat { case Active; case Inactive; case Pending; }
$s = Stat::Active;
$r = match($s) {
    Stat::Active => "on",
    Stat::Inactive => "off",
    default => "wait",
};
echo $r, "\n";

// readonly with object
class Box {
    public function __construct(public readonly array $items) {}
}
$b = new Box([1, 2, 3]);
try { $b->items = []; echo "no\n"; } catch (\Error $e) { echo "ro\n"; }

// generator return value
function g7() { yield 1; yield 2; return "done"; }
$g = g7();
foreach ($g as $v) echo "$v ";
echo "|", $g->getReturn(), "\n";

// fiber suspend with values
$f = new Fiber(function () {
    $a = Fiber::suspend("first");
    $b = Fiber::suspend("got:$a");
    return "end:$a:$b";
});
echo $f->start(), "|"; // first
echo $f->resume("X"), "|"; // got:X
echo $f->resume("Y"), "|"; // end (return)
echo $f->getReturn() ?? "null", "\n"; // end:X:Y

// fiber with throw
$f = new Fiber(function () {
    try {
        Fiber::suspend("before");
        echo "never\n";
    } catch (RuntimeException $e) {
        return "caught:" . $e->getMessage();
    }
});
echo $f->start(), "|";
$f->throw(new RuntimeException("from caller"));
echo $f->getReturn() ?? "null", "\n";

// nullable types
function findMaybe(int $key): ?string {
    $map = [1 => "a", 2 => "b"];
    return $map[$key] ?? null;
}
echo findMaybe(1) ?? "nf", "\n";
echo findMaybe(99) ?? "nf", "\n";

// type juggling in array keys
$arr = [];
$arr["1"] = "string-1";  // becomes int 1
$arr[1] = "int-1"; // overwrites
$arr["01"] = "string-01"; // stays string (leading zero)
$arr[true] = "bool-true"; // becomes int 1
print_r($arr);

// PHP emits "Implicit conversion from float to int" deprecation; skipped (architectural gap)

// array_keys with mixed
print_r(array_keys(["a" => 1, 0 => 2, "b" => 3, 5 => 4]));

// list-style structure with references modifying source
$arr = [1, 2, 3];
foreach ($arr as $k => &$v) $v *= 10;
unset($v);
print_r($arr);

// foreach with same var name rebind
foreach ([1, 2, 3] as $a) echo "$a ";
foreach ([4, 5, 6] as $a) echo "$a ";
echo "\n";
