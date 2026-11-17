<?php
// writing a property or building an array from a variable changes no
// reference count in php, so it adds no possible root; replacing a value
// something else still holds does
class A { public $b; }
class B { public $a; }

function roots(string $label) {
    echo $label, ": ", gc_status()['roots'], "\n";
}

$a = new A;
$x = new B;
$a->b = $x;
roots('property set from a variable');
$a->b->a = $a;
roots('nested property set');
$list = [$x, $a];
$list2 = array($a);
roots('array literals');
$a->b = new B;
roots('replaced a property another variable holds');
unset($x);
roots('unset a variable another holds');
