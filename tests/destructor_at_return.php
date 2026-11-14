<?php
// a function's locals are destroyed as it returns, before the caller uses
// the result
class D {
    function __construct(public $n) {}
    function __destruct() { echo "destroy {$this->n}\n"; }
}

function f() { $d = new D(1); echo "in f\n"; return 5; }
echo "result: " . f() . "\n";

function g() { $d = new D(2); }
echo "g: " . var_export(g(), true) . "\n";

function h() { $d = new D(3); return $d->n; }
var_dump(h());

function loop() {
    $s = 0;
    for ($i = 0; $i < 3; $i++) { $s += $i; }
    $d = new D(4);
    return $s;
}
echo "loop: " . loop() . "\n";

class M {
    function m() { $d = new D(5); return "m"; }
    static function s() { $d = new D(6); return "s"; }
}
$m = new M;
echo "method: " . $m->m() . "\n";
echo "static: " . M::s() . "\n";

class C {
    public $v;
    function __construct() { $d = new D(7); $this->v = 'c'; }
}
echo "ctor: " . (new C)->v . "\n";

// a temporary receiver is destroyed as the method returns
class R { function __destruct() { echo "destroy R\n"; } function m() { return "r"; } }
echo "temp: " . (new R)->m() . "\n";

// the returned object itself survives
function keep() { $d = new D(9); return $d; }
$k = keep();
echo "kept {$k->n}\n";
unset($k);

// nested calls: the inner frame's locals go first
function inner() { $d = new D(10); return 1; }
function outer() { $d = new D(11); return inner() + 1; }
echo "nested: " . outer() . "\n";

// a closure
$c = function () { $d = new D(12); return "closure"; };
echo $c() . "\n";

// a destructor that throws at return is thrown at the call
class Boom { function __destruct() { throw new Exception("boom"); } }
function boom() { $b = new Boom; return 1; }
try {
    echo "before " . boom() . "\n";
} catch (Exception $e) {
    echo "caught " . $e->getMessage() . "\n";
}

// an array callback's locals
echo implode(",", array_map(function ($x) { $d = new D(13 + $x); return $x; }, [0, 1])) . "\n";
echo "done\n";
