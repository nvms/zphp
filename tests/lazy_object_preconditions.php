<?php
// what newLazyGhost, newLazyProxy and the resetAsLazy methods refuse, the
// destructor a reset runs, and the value a ghost's initializer may return

class C {
    public $a = 1;
    public function __destruct() { echo "C::__destruct\n"; }
}
class Sub extends DateTime {}
class Other {}

function attempt(callable $f): void {
    try { $f(); } catch (Throwable $e) { printf("%s: %s\n", $e::class, $e->getMessage()); }
}

$r = new ReflectionClass(C::class);
attempt(fn() => $r->newLazyGhost(function ($o) {}, -1));
attempt(fn() => $r->newLazyProxy(function ($o) {}, -1));
attempt(fn() => $r->newLazyGhost(function ($o) {}, ReflectionClass::SKIP_DESTRUCTOR));
attempt(fn() => (new ReflectionClass(DateTime::class))->newLazyGhost(function ($o) {}));
attempt(fn() => (new ReflectionClass(Sub::class))->newLazyProxy(function ($o) {}));
attempt(fn() => $r->resetAsLazyGhost(new Other, function ($o) {}));

$obj = new C;
attempt(fn() => $r->resetAsLazyGhost($obj, function ($o) {}, -1));
echo "reset:\n";
$r->resetAsLazyGhost($obj, function ($o) { echo "init\n"; });
attempt(fn() => $r->resetAsLazyGhost($obj, function ($o) {}));
var_dump($obj->a);

$skip = new C;
echo "reset skipping the destructor:\n";
$r->resetAsLazyProxy($skip, fn($o) => new C, ReflectionClass::SKIP_DESTRUCTOR);

$returns = $r->newLazyGhost(function ($o) { return 1; });
attempt(fn() => $returns->a);
var_dump($r->isUninitializedLazyObject($returns));

$running = $r->newLazyGhost(function ($o) use ($r) {
    attempt(fn() => $r->resetAsLazyGhost($o, function () {}));
});
$running->a;
echo "done\n";
