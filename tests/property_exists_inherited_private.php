<?php
// an ancestor's private property is no property of the child class, for an
// object as for a class name
class A {
    private $a = 1;
    protected $pa = 2;
    private static $sa = 3;
    // its own private property, seen from its scope on a subclass's object
    public function sees($o) { return property_exists($o, 'a'); }
}
class B extends A {
    private $b = 4;
}
$b = new B;
foreach (['a', 'pa', 'sa', 'b', 'nope', 'dyn'] as $p) {
    var_dump([$p, property_exists('B', $p), property_exists($b, $p), property_exists('A', $p), property_exists(new A, $p)]);
}
$o = new stdClass;
$o->dyn = 1;
var_dump(property_exists($o, 'dyn'), property_exists('stdClass', 'dyn'));
var_dump((new A)->sees($b), (new A)->sees(new A));
try {
    new ReflectionReference();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
