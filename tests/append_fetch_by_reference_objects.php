<?php
// `$obj[]` passed by reference fetches through offsetGet(null), which
// SplFixedArray refuses; a plain object can't be used as an array.
// reflection keeps an anonymous class's self as written

class AA implements ArrayAccess
{
    public function offsetGet($o): mixed { echo "offsetGet "; var_dump($o); return 5; }
    public function offsetSet($o, $v): void {}
    public function offsetExists($o): bool { return true; }
    public function offsetUnset($o): void {}
}

class Holder implements ArrayAccess
{
    public $inner;
    public function __construct() { $this->inner = new ArrayObject(); }
    public function offsetGet($o): mixed { return $this->inner; }
    public function offsetSet($o, $v): void {}
    public function offsetExists($o): bool { return true; }
    public function offsetUnset($o): void {}
}

function take(&$r) { var_dump($r); }
function takeTyped(SplFixedArray &$arr) { echo "not reached\n"; }

$aa = new AA;
take($aa[]);
var_dump($aa);
$h = new Holder;
take($h[]);
try {
    $f = new SplFixedArray(2);
    takeTyped($f[]);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    $o = new stdClass;
    take($o[]);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

class Named
{
    public function m(self $a): ?self { return null; }
}
$anon = new class {
    public function m(self $a): self|int { return 1; }
    public function n(): ?self { return null; }
};
foreach ([new ReflectionMethod(Named::class, 'm'), new ReflectionMethod($anon, 'm'), new ReflectionMethod($anon, 'n')] as $m) {
    $params = $m->getParameters();
    $param = $params[0] ?? null;
    echo $param ? $param->getType() . " " : "", $m->getReturnType(), "\n";
}
