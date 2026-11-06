<?php
// object handles: the number var_dump shows and spl_object_id returns. a
// freed handle is the next one handed out, and objects are freed when php
// frees them
class A { public $b; function __construct($b = null) { $this->b = $b; } }
class D {
    public $a; public $b;
    function __construct(public $n) {}
    function __destruct() { echo "~{$this->n} "; }
}

// `new` takes its handle before its arguments run
var_dump(new A(new A));
$x = [new A, new A, new A];
unset($x);
$y = [new A, new A, new A];
foreach ($y as $o) echo spl_object_id($o), " ";
echo "\n";
unset($y, $o);

// a temporary passed to a function is freed as the call returns
var_dump(spl_object_id(new A), spl_object_id(new A));
echo var_export(new A, true), "\n";
var_dump(new stdClass);

// a dying object frees what it holds depth first, then its own handle
$t = new D('x'); $t->a = new D('c1'); $t->a->a = new D('g1'); $t->b = new D('c2'); $t->b->a = [new D('g2'), new D('g3')];
unset($t);
echo "\n";
var_dump(spl_object_id(new A));

// enum cases are created on first use
enum E { case P; case Q; case R; }
$keep = new A;
var_dump(spl_object_id(E::Q), spl_object_id(new A), spl_object_id(E::P), count(E::cases()), spl_object_id(E::R));

// closures, generators and fibers are objects
$f = function () {};
function g() { yield 1; }
$gen = g();
$fiber = new Fiber(function () {});
var_dump(spl_object_id($f), spl_object_id($gen), spl_object_id($fiber), spl_object_id(new A));
unset($f, $gen, $fiber);

// foreach over a Traversable holds an iterator object for the loop
$ao = new ArrayObject([1, 2]);
foreach ($ao as $v) echo spl_object_id(new A), " ";
echo spl_object_id(new A), "\n";
foreach ((function () { yield 1; })() as $v) echo spl_object_id(new A), " ";
echo spl_object_id(new A), "\n";

// a temporary a method is called on goes when the call returns
#[Attribute]
class Marker { function __construct(public $v = 0) {} }
#[Marker(5)]
class Tagged {}
var_dump((new ReflectionClass('Tagged'))->getAttributes()[0]->newInstance());

// shutdown: globals that hold the only reference go last-declared first
$first = new D('first');
$second = new D('second', );
$second->a = new D('second-child');
$shared = new D('shared');
$alias = $shared;
$GLOBALS['dynamic'] = new D('dynamic');
echo "end\n";
