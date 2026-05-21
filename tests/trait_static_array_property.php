<?php
// regression: each class that uses a trait gets its own copy of the trait's
// static properties. zphp shared array-valued static properties by pointer,
// so writes from one using-class leaked into the others.

trait Registry {
    private static array $items = [];
    public static function add($x): void { self::$items[] = $x; }
    public static function all(): array { return self::$items; }
}
class StoreA { use Registry; }
class StoreB { use Registry; }

StoreA::add('a1');
StoreA::add('a2');
StoreB::add('b1');

echo count(StoreA::all()), ' ', count(StoreB::all()), "\n";   // 2 1
print_r(StoreA::all());
print_r(StoreB::all());

// public array static prop, accessed directly
trait Bucket {
    public static array $data = [];
}
class X { use Bucket; }
class Y { use Bucket; }
X::$data[] = 1;
X::$data[] = 2;
Y::$data[] = 99;
echo count(X::$data), ' ', count(Y::$data), "\n";            // 2 1

// scalar static props were already independent - confirm still so
trait Counting {
    public static int $n = 0;
    public static function bump(): void { self::$n++; }
}
class P { use Counting; }
class Q { use Counting; }
P::bump(); P::bump(); P::bump();
Q::bump();
echo P::$n, ' ', Q::$n, "\n";                                // 3 1

// a trait static array with a non-empty default is also per-class
trait Defaults {
    public static array $cfg = ['mode' => 'default'];
}
class Service1 { use Defaults; }
class Service2 { use Defaults; }
Service1::$cfg['mode'] = 'custom';
echo Service1::$cfg['mode'], ' ', Service2::$cfg['mode'], "\n";  // custom default
