<?php
// covers: static arrow functions, static:: late static binding across call chains,
// generators from instance method context

// static fn
$fn = static fn($x) => $x * 2;
echo $fn(5) . "\n";

$arr = [3, 1, 4, 1, 5];
usort($arr, static fn($a, $b) => $a - $b);
echo implode(',', $arr) . "\n";

$typed = static fn(int $x): int => $x + 1;
echo $typed(10) . "\n";

// static:: should not leak caller's $this class into explicit static calls
class Base {
    public static function getRepo() { return "base_repo"; }
    protected static function getOption($key) {
        return static::getRepo();
    }
    public static function get($key) {
        return self::getOption($key);
    }
}

class Caller {
    public function run() {
        return Base::get("test");
    }
}

echo (new Caller())->run() . "\n";

// static:: in inheritance chain
class Parent1 {
    public static function who() { return static::class; }
}

class Child1 extends Parent1 {}

echo Parent1::who() . "\n";
echo Child1::who() . "\n";

// generators called from instance method context
class GenClass {
    public static function gen() {
        yield 1;
        yield 2;
    }
}

class Instance {
    public function test() {
        return iterator_to_array(GenClass::gen());
    }
}

echo implode(',', (new Instance())->test()) . "\n";

// generator from constructor
class CtorGen {
    public $items;
    public function __construct() {
        $this->items = iterator_to_array(GenClass::gen());
    }
}

echo implode(',', (new CtorGen())->items) . "\n";
