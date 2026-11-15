<?php
// Fiber::suspend() reached through native code the fiber's loop called:
// a generator resumed by foreach or by its methods, a callback of an
// internal function, an Iterator's methods, a magic method

function gen() {
    echo "gen start\n";
    $x = Fiber::suspend('in gen');
    echo "gen got $x\n";
    yield 1;
    $y = Fiber::suspend('in gen again');
    echo "gen got $y\n";
    yield 2;
}

$f = new Fiber(function () {
    foreach (gen() as $v) echo "value $v\n";
    return 'done';
});
var_dump($f->start());
var_dump($f->resume('a'));
var_dump($f->resume('b'));
var_dump($f->isTerminated(), $f->getReturn());

// generator methods
$f = new Fiber(function () {
    $g = gen();
    var_dump($g->current());
    $g->next();
    var_dump($g->current());
});
var_dump($f->start());
var_dump($f->resume('c'));
var_dump($f->resume('d'));

// callbacks of internal functions
$f = new Fiber(function () {
    $r = array_map(fn ($x) => Fiber::suspend($x) * 2, [1, 2, 3]);
    var_dump($r);
    usort($r, function ($a, $b) {
        Fiber::suspend("cmp $a $b");
        return $b <=> $a;
    });
    var_dump($r);
});
$v = $f->start();
while (!$f->isTerminated()) {
    echo "suspended with ", var_export($v, true), "\n";
    $v = $f->resume(is_int($v) ? $v * 10 : null);
}

class It implements Iterator {
    private $i = 0;
    function current(): mixed { return Fiber::suspend("current {$this->i}"); }
    function key(): mixed { return $this->i; }
    function next(): void { $this->i++; }
    function rewind(): void { $this->i = 0; }
    function valid(): bool { return $this->i < 2; }
}
$f = new Fiber(function () {
    foreach (new It as $k => $v) echo "$k => $v\n";
});
var_dump($f->start());
var_dump($f->resume('A'));
var_dump($f->resume('B'));

class Magic {
    function __get($name) { return Fiber::suspend("get $name"); }
    function __call($name, $args) { return Fiber::suspend("call $name"); }
}
$f = new Fiber(function () {
    $m = new Magic;
    echo "prop: ", $m->foo, "\n";
    echo "call: ", $m->bar(1), "\n";
});
var_dump($f->start());
var_dump($f->resume('P'));
var_dump($f->resume('C'));

// resumed from a different depth than it was started at
function startIt($f) { return $f->start(); }
function resumeDeep($f, $n, $v) { return $n ? resumeDeep($f, $n - 1, $v) : $f->resume($v); }
$f = new Fiber(function () {
    $a = array_map(function ($x) {
        $got = Fiber::suspend($x);
        return "$x:$got";
    }, ['p', 'q', 'r']);
    var_dump($a);
});
var_dump(startIt($f));
var_dump(resumeDeep($f, 5, 'deep'));
var_dump($f->resume('top'));
var_dump(resumeDeep($f, 2, 'mid'));

// throw() into a nested suspension, caught inside the generator
function catching() {
    try {
        Fiber::suspend('waiting');
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
    }
    yield 'after';
}
$f = new Fiber(function () {
    foreach (catching() as $v) echo "$v\n";
});
var_dump($f->start());
$f->throw(new Exception('boom'));
var_dump($f->isTerminated());

// an uncaught one leaves through the callback and the fiber
$f = new Fiber(function () {
    array_map(function ($x) { Fiber::suspend($x); }, [1]);
});
$f->start();
try {
    $f->throw(new Exception('out'));
} catch (Exception $e) {
    echo "outside: ", $e->getMessage(), "\n";
}
var_dump($f->isTerminated());

// a generator running in a suspended fiber can't be resumed elsewhere
function plain() { Fiber::suspend(); yield 1; }
$g = plain();
$f = new Fiber(function () use ($g) { $g->current(); });
$f->start();
try {
    $g->next();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$f->resume();
echo "end\n";
