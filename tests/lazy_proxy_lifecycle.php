<?php
class ProxyLife {
    public int $value = 7;
    public static int $destroyed = 0;
    public function __destruct() { ++self::$destroyed; }
    public function __clone() { ++$this->value; }
}
$r = new ReflectionClass(ProxyLife::class);
$attempt = 0;
$p = $r->newLazyProxy(function () use (&$attempt) {
    ++$attempt;
    if ($attempt === 1) throw new RuntimeException('retry');
    if ($attempt === 2) return null;
    return new ProxyLife();
});
for ($i = 0; $i < 3; ++$i) {
    try { echo $p->value, "\n"; }
    catch (Throwable $e) { echo get_class($e), "\n"; }
    var_dump($r->isUninitializedLazyObject($p));
}
$c = clone $p;
echo $c->value, ':', $p->value, "\n";
var_dump($r->initializeLazyObject($c) !== $r->initializeLazyObject($p));
echo serialize($p), "\n";
unset($p);
echo ProxyLife::$destroyed, "\n";
unset($c);
echo ProxyLife::$destroyed, "\n";
$never = $r->newLazyProxy(fn () => new ProxyLife());
unset($never);
echo ProxyLife::$destroyed, "\n";
