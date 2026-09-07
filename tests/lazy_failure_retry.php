<?php
class LazyRetry {
    public int $id = 1;
    public int $value = 3;
    public array $items = [1];
}
$r = new ReflectionClass(LazyRetry::class);
$attempt = 0;
$o = $r->newLazyGhost(function ($o) use (&$attempt) {
    echo 'attempt:', ++$attempt, ':', $o->id, ':', $o->value, ':', count($o->items), "\n";
    $o->id = 99;
    $o->items[] = 2;
    $o->value = 12;
    if ($attempt === 1) throw new RuntimeException('retry');
});
$r->getProperty('id')->setRawValueWithoutLazyInitialization($o, 7);
try { echo $o->value; } catch (RuntimeException $e) { echo $e->getMessage(), "\n"; }
var_dump($o->id, $r->isUninitializedLazyObject($o));
var_dump($o->value, $r->isUninitializedLazyObject($o));
