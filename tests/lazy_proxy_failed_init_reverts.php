<?php
// php 8.6 reverts what a failed proxy factory wrote, as it does for a ghost:
// the properties stay lazy and keep nothing of the attempt
class C {
    public $a = 1;
    public int $b = 2;
    public $c;
}
$r = new ReflectionClass(C::class);
$p = $r->newLazyProxy(function ($obj) {
    $obj->a = 3;
    $obj->b = 4;
    $obj->dyn = 5;
    throw new Exception('fail');
});
try { $r->initializeLazyObject($p); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
var_dump($p);
var_dump((array) $p);
foreach ($p as $k => $v) echo "$k\n";
var_dump($r->isUninitializedLazyObject($p));
$r->getProperty('a')->skipLazyInitialization($p);
var_dump($p);
$r->markLazyObjectAsInitialized($p);
var_dump($p);
