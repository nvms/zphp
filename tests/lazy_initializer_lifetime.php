<?php
class LazyLifetime {
    public int $value = 1;
    public function __destruct() { echo "object released\n"; }
}
class LazyCapture { public function __destruct() { echo "capture released\n"; } }
$r = new ReflectionClass(LazyLifetime::class);
$make = function () use ($r) {
    $capture = new LazyCapture;
    return $r->newLazyGhost(function ($o) use ($capture) { echo "initializer\n"; $o->value = 8; });
};
$o = $make();
echo "created\n";
var_dump($o->value);
unset($o);
echo "done\n";
$o = $make();
unset($o);
echo "discarded\n";
$o = $make();
$r->markLazyObjectAsInitialized($o);
echo "marked\n";
