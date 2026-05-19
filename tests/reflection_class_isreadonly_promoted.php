<?php
// regression: ReflectionClass::isReadonly (lowercase 'o') alias matches the
// existing isReadOnly. PHP 8.2+ documents lowercase form and most code calls
// it that way; zphp's case-sensitive method lookup required both registrations.
// also ReflectionParameter::isPromoted now distinguishes a same-named
// non-promoted property from an actually-promoted constructor parameter
class Counter {
    public int $count = 0;
    private ?string $name = null;
    public static int $total = 0;
    public function __construct(public readonly string $id, ?string $name = null) {
        $this->name = $name;
    }
}

$r = new ReflectionClass(Counter::class);
var_dump($r->isReadonly());
var_dump($r->isReadOnly());

readonly class V {
    public function __construct(public int $x) {}
}
$rv = new ReflectionClass(V::class);
var_dump($rv->isReadonly());
var_dump($rv->isReadOnly());

// promoted vs non-promoted detection
$ctor = $r->getConstructor();
foreach ($ctor->getParameters() as $p) {
    echo $p->getName() . " promoted=" . ($p->isPromoted() ? 'y' : 'n') . "\n";
}
