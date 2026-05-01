<?php

// final class can be instantiated
final class Sealed {
    public function __construct(public string $name) {}
}
$s = new Sealed('a');
echo $s->name . "\n";

// final method can't be overridden, but extending the class is fine if not final
class Base {
    final public function locked(): string { return 'base'; }
    public function open(): string { return 'base-open'; }
}
class Child extends Base {
    public function open(): string { return 'child-open'; }
}
$c = new Child();
echo $c->locked() . "\n";
echo $c->open() . "\n";

// final readonly class composition
final readonly class Immutable {
    public function __construct(public string $tag) {}
}
$im = new Immutable('frozen');
echo $im->tag . "\n";
try { $im->tag = 'thawed'; } catch (Error $e) { echo "ro\n"; }

// extending a final class is rejected at class-definition time
// (this is an uncatchable fatal in PHP, so we test it indirectly via
// reflection on a class that exists)
$rc = new ReflectionClass(Sealed::class);
echo ($rc->isFinal() ? "final" : "open") . "\n";

$rc2 = new ReflectionClass(Base::class);
echo ($rc2->isFinal() ? "final" : "open") . "\n";

// final method via reflection
$rm = new ReflectionMethod(Base::class, 'locked');
echo ($rm->isFinal() ? "final" : "open") . "\n";
