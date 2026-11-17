<?php
// reflection of a trait's abstract methods, an interface declaring hooked
// properties (php gives it the hooked object iterator), and the order of
// ReflectionClass's own constants
trait T {
    abstract public function f();
    abstract public function __construct();
    public function g() {}
}
foreach (['f', '__construct', 'g'] as $name) {
    $m = new ReflectionMethod('T', $name);
    var_dump($m->isAbstract(), Reflection::getModifierNames($m->getModifiers()));
}

interface Hooked {
    public mixed $x { get; }
}
interface Plain {
    public function m();
}
foreach (['Hooked', 'Plain'] as $name) {
    echo strtok((string) new ReflectionClass($name), "\n"), "\n";
}

var_dump(array_keys((new ReflectionClass('ReflectionClass'))->getConstants()));
