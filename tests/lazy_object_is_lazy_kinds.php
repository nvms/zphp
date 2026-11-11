<?php
// ReflectionProperty::isLazy is false for properties a lazy object has no
// slot for: static, virtual and dynamic ones

#[AllowDynamicProperties]
class C {
    public static $staticProp;
    public int $typed;
    public $untyped;
    public $virtual { get { return 1; } }
}
$r = new ReflectionClass(C::class);
$obj = $r->newLazyGhost(function ($o) {});
$obj2 = new C;
$obj2->dynamic = 1;
foreach (['staticProp', 'typed', 'untyped', 'virtual'] as $p) {
    printf("%s: %d\n", $p, $r->getProperty($p)->isLazy($obj));
}
printf("dynamic: %d\n", (new ReflectionProperty($obj2, 'dynamic'))->isLazy($obj));
