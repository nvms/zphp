<?php
class A {
    public function __isset($n) { echo "isset $n\n"; return isset($this->$n) || $n === 'y'; }
    public function __get($n) { echo "get $n\n"; return $this->$n ?? "dflt"; }
}
$a = new A;
var_dump(isset($a->x));
var_dump(isset($a->y));
var_dump($a->x ?? 'none');
var_dump($a->y ?? 'none');
class B { public function __isset($n) { echo "B isset $n\n"; return true; } }
$b = new B;
var_dump($b->q ?? 'none');
class C { private $p = 5; public function __isset($n) { echo "C isset\n"; return true; } public function __get($n) { echo "C get\n"; return 9; } }
var_dump((new C)->p ?? 'none');
class D { public function __isset($n) { echo "D isset\n"; return $this->$n ?? false; } public function __get($n) { echo "D get\n"; return 7; } }
var_dump((new D)->z ?? 'none');
class Foo2 {
    public $prop;

    public function foo() {
        echo __METHOD__, "\n";
        return $this;
    }

    public function bar() {
        echo __METHOD__, "\n";
        return 'prop';
    }

    public function __isset($name) {
        echo __METHOD__, "\n";
        return false;
    }

    public function __set($name, $value) {
        echo __METHOD__, "\n";
        var_dump($value);
    }
}

$foo = new Foo2();
$foo->foo()->foo()->{$foo->bar()} ??= 42;
var_dump($foo);
$foo->foo()->baz ??= 42;

