<?php
// a protected property is checked against the class that first declared it,
// so sibling classes under that ancestor reach each other's

abstract class P {
    protected $foo;
}

class C1 extends P {
    protected $foo = 1;
}

class C2 extends P {
    protected $foo = 2;

    static function read($c) { return $c->foo; }
    static function write($c, $v) { $c->foo = $v; return $c->foo; }
    static function has($c) { return isset($c->foo); }
    static function drop($c) { unset($c->foo); return isset($c->foo); }
}

var_dump(C2::read(new C2));
var_dump(C2::read(new C1));
var_dump(C2::write(new C1, 5));
var_dump(C2::has(new C1));
var_dump(C2::drop(new C1));

// a private ancestor declaration starts a new chain
class Q {
    private $bar = 'q';
}

class D1 extends Q {
    protected $bar = 'd1';
}

class D2 extends Q {
    protected $bar = 'd2';

    static function read($c) {
        try {
            return $c->bar;
        } catch (Error $e) {
            return $e->getMessage();
        }
    }
}

var_dump(D2::read(new D1));

// asymmetric visibility follows the same rule
abstract class GP {
    abstract public mixed $baz { get; }
}

class E1 extends GP {
    public protected(set) mixed $baz = 1;
}

class E2 extends GP {
    public protected(set) mixed $baz = 2;

    static function bump($c) { return $c->baz += 1; }
}

var_dump(E2::bump(new E1));

class Unrelated {
    static function read($c) {
        try {
            return $c->foo;
        } catch (Error $e) {
            return $e->getMessage();
        }
    }
}

var_dump(Unrelated::read(new C1));
