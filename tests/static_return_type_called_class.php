<?php
// a static return type takes an instance of the called class only
class A {
    public function fromSelf(): static { return new self; }
    public function fromStatic(): static { return new static; }
    public function either(): static|array { return new self; }
    public function maybe(): ?static { return null; }
    public static function make(): static { return new A; }
    public function same(): static { return $this; }
}
class B extends A {}
trait T {
    public function pass($arg): static { return $arg; }
}
class C { use T; }
class D extends C {}

function attempt(callable $f) {
    try {
        $r = $f();
        echo is_object($r) ? get_class($r) : var_export($r, true), "\n";
    } catch (TypeError $e) {
        echo str_replace(__FILE__, "FILE", $e->getMessage()), "\n";
    }
}
attempt(fn() => (new A)->fromSelf());
attempt(fn() => (new B)->fromSelf());
attempt(fn() => (new B)->fromStatic());
attempt(fn() => (new B)->either());
attempt(fn() => (new B)->maybe());
attempt(fn() => A::make());
attempt(fn() => B::make());
attempt(fn() => (new B)->same());
attempt(fn() => (new C)->pass(new D));
attempt(fn() => (new D)->pass(new C));
$unbound = function ($x): static { return $x; };
attempt(fn() => $unbound(new A));
$bound = Closure::bind($unbound, new B, B::class);
attempt(fn() => $bound(new B));
attempt(fn() => $bound(new A));
