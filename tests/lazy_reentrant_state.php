<?php
class ReentrantLazy { public int $value = 1; }
$r = new ReflectionClass(ReentrantLazy::class);
$attempt = 0;
$o = $r->newLazyGhost(function ($o) use ($r, &$attempt) {
    var_dump($r->isUninitializedLazyObject($o));
    $r->markLazyObjectAsInitialized($o);
    $r->getProperty('value')->skipLazyInitialization($o);
    $o->value = 8;
    if (++$attempt === 1) throw new Exception('retry');
});
try { var_dump($o->value); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
var_dump($r->isUninitializedLazyObject($o));
var_dump($o->value);
