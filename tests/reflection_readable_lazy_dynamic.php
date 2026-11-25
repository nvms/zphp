<?php
// isReadable() of a dynamic property on an uninitialized lazy object
// initializes it to see whether the property exists
#[AllowDynamicProperties]
class A {
    public $_;
    public function __construct() { $this->prop = 1; }
}
$rc = new ReflectionClass(A::class);
$proxy = $rc->newLazyProxy(function () { echo "init proxy\n"; return new A(); });
$ghost = $rc->newLazyGhost(function ($o) { echo "init ghost\n"; $o->__construct(); });
$rp = new ReflectionProperty(new A, 'prop');
var_dump($rp->isReadable(null, $proxy));
var_dump($rc->isUninitializedLazyObject($proxy));
var_dump($rp->isReadable(null, $ghost));
$missing = new ReflectionProperty(new class { public function __construct() { $this->other = 1; } }, 'other');
$lazy = $rc->newLazyGhost(function ($o) { echo "init again\n"; });
try {
    var_dump($missing->isReadable(null, $lazy));
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
