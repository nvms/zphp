<?php
// recursive function with static var must accumulate across calls
function fib_count($n) {
    static $count = 0;
    $count++;
    if ($n < 2) return [$n, $count];
    [$a] = fib_count($n - 1);
    [$b] = fib_count($n - 2);
    return [$a + $b, $count];
}
[$result, $calls] = fib_count(5);
echo "fib=$result calls=$calls\n";

// static var basic
function counter() {
    static $c = 0;
    return ++$c;
}
echo counter(), " ", counter(), " ", counter(), "\n";

// static array - persists
function memo($k, $v = null) {
    static $store = [];
    if ($v !== null) $store[$k] = $v;
    return $store[$k] ?? null;
}
memo('a', 1);
memo('b', 2);
echo memo('a'), " ", memo('b'), "\n";

// static in method shared across instances (PHP behavior)
class Counter {
    public function inc() {
        static $n = 0;
        return ++$n;
    }
}
$a = new Counter;
$b = new Counter;
echo $a->inc(), " ", $b->inc(), " ", $a->inc(), "\n";

// static in closure - shared across calls of same closure instance
$f = function() {
    static $n = 0;
    return ++$n;
};
echo $f(), " ", $f(), " ", $f(), "\n";

// each closure instance from a factory has its OWN static state
function make_counter() {
    return function() {
        static $n = 0;
        return ++$n;
    };
}
$c1 = make_counter();
$c2 = make_counter();
echo $c1(), $c1(), $c2(), $c1(), $c2(), "\n";

// static array literal init - mutation persists
function arr() {
    static $a = [1, 2, 3];
    $a[] = count($a);
    return $a;
}
print_r(arr());
print_r(arr());
