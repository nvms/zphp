<?php
// `$a = &$b` frees what $a held right away, and a reference cycle left
// behind is found by the cycle collector

class D {
    public function __construct(public $n) {}
    public function __destruct() { echo "destroyed {$this->n}\n"; }
}

$a = new D(1);
$b = 1;
$a = &$b;
echo "after the global rebind\n";
var_dump($GLOBALS['a']);

function rebind() {
    $a = new D(2);
    $b = 1;
    $a = &$b;
    echo "after the local rebind\n";
    $c = [new D(3)];
    $c = &$b;
    echo "after the array rebind\n";
}
rebind();

unset($a, $b);
$a = [[]];
$a[0][0] = &$a[0];
$b = 1;
$a = &$b;
var_dump(gc_collect_cycles());

unset($a, $b);
$a = [];
$a[0] = &$a;
$a[1] = [];
$a[1][0] = &$a[1];
$b = 1;
$a = &$b;
var_dump(gc_collect_cycles());

function cycles() {
    $a = [];
    $a[0] = &$a;
    $b = 1;
    $a = &$b;
    var_dump(gc_collect_cycles());
}
cycles();
echo "done\n";
