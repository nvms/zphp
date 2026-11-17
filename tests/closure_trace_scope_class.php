<?php
// a closure's frame in a trace names the closure's scope, not its object's
// class
class A {
    public function make() {
        return function () { throw new Exception('in closure'); };
    }
}
class B extends A {}
function show(Closure $c) {
    try {
        $c();
    } catch (Exception $e) {
        $f = $e->getTrace()[0];
        echo ($f['class'] ?? '-'), ($f['type'] ?? '-'), "\n";
    }
}
$c = (new A)->make();
show($c);
show($c->bindTo(new B));
show($c->bindTo(new B, B::class));
show($c->bindTo(new B, null));
show(Closure::bind($c, null, B::class));
show((new B)->make());
