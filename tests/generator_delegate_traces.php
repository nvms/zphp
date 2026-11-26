<?php
// a delegate iterator's methods and what a finished delegate generator
// releases are called from inside the generators waiting on them
class Foo {
    public function __destruct() {
        echo (new Exception)->getTraceAsString(), "\n";
    }
}
function baz() {
    yield 0;
    yield from bar();
}
function bar() {
    yield from foo();
    yield 5;
}
function foo() {
    $foo = new Foo();
    yield;
}
function main() {
    $gen = baz();
    foreach ($gen as $dummy) {
        echo "step\n";
    }
}
main();

function thrower() {
    try {
        yield from new class(new ArrayIterator([1, -2])) extends IteratorIterator {
            public function key(): mixed {
                if ($k = parent::key()) {
                    throw new Exception;
                }
                return $k;
            }
        };
    } catch (Exception $e) {
        echo $e->getTraceAsString(), "\n";
        yield 2;
    }
}
foreach (thrower() as $k => $v) {
    var_dump($v);
}

class Trace {
    public function __destruct() {
        debug_print_backtrace();
    }
}
function inner2() {
    $f = new Trace;
    yield 1;
    return 2;
}
function outer2() {
    $r = yield from inner2();
    echo "returned $r\n";
    yield $r;
}
foreach (outer2() as $v) {
    var_dump($v);
}

function delegated() {
    yield from new class extends ArrayIterator {
        public function __construct() { parent::__construct([1, 2]); }
        public function current(): mixed { debug_print_backtrace(); return parent::current(); }
    };
}
function waiting() {
    yield from delegated();
}
foreach (waiting() as $v) {
    var_dump($v);
}
