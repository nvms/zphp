<?php
// Closure::bind, bindTo and call follow php's binding rules: what may be
// bound to what, the scope a binding leaves, and the warnings when refused
class A {
    private $x = 1;
    public static function make() { return static function () { return isset($this); }; }
    public function get() { return function () { return $this->x; }; }
    public function plain() { return function () { return 42; }; }
    public function counter() { return function () { static $n = 0; return ++$n; }; }
}
class B extends A {}

function show($label, $value) {
    echo $label, ": ";
    var_dump($value);
}

$a = new A;
$getter = $a->get();
show("bound", $getter());
show("rebound", $getter->bindTo(new B)());
show("static bind", A::make()->bindTo(new A));
show("unbind using this", $getter->bindTo(null));
show("unbind plain", $a->plain()->bindTo(null)());
show("internal scope", $getter->bindTo($a, 'stdClass'));
show("missing scope", $getter->bindTo($a, 'NoSuchClass'));
try {
    $getter->bindTo($a, []);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $getter->bindTo(5);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    Closure::bind(5, null);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $getter->call(null);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

$unscoped = function () { return [get_class($this), static::class]; };
$bound = $unscoped->bindTo(new B);
show("dummy scope", (new ReflectionFunction($bound))->getClosureScopeClass()->name);
show("called scope", $bound());
show("explicit scope", (new ReflectionFunction($unscoped->bindTo(new B, A::class)))->getClosureScopeClass()->name);
show("scope by object", Closure::bind(function () { return $this->x; }, new A, new A)());
show("call", (function ($y) { return $this->x + $y; })->call(new A, 10));
show("call on stdClass", (function () { return 1; })->call(new stdClass));

$counter = $a->counter();
$counter();
$counter();
$copy = $counter->bindTo($a);
show("copied static", $copy());
show("original static", $counter());

$fn = strlen(...);
show("function closure rebind", $fn->bindTo(null, A::class));
$method = $a->get(...);
show("method unbind", $method->bindTo(null));
show("method to other class", $method->bindTo(new stdClass));
show("method to subclass", get_class($method->bindTo(new B)));
