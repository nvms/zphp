<?php
// a typed property __sleep names that is uninitialized is left out of the
// serialization, a lazy object's (serialized without initializing) included

class C {
    public int $a;
    public ?string $b = null;
    private int $c;
    public function __sleep() { return ['a', 'b', 'c']; }
}
var_dump(serialize(new C));
$o = new C;
$o->a = 1;
var_dump(serialize($o));

$r = new ReflectionClass(C::class);
$lazy = $r->newLazyGhost(function ($o) { echo "initializer\n"; $o->a = 2; }, ReflectionClass::SKIP_INITIALIZATION_ON_SERIALIZE);
var_dump(serialize($lazy));
$lazy = $r->newLazyGhost(function ($o) { echo "initializer\n"; $o->a = 2; });
var_dump(serialize($lazy));
