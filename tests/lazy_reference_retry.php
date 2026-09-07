<?php
class LazyReferencedItem {
    public int $id = 1;
    public int $value = 2;
}
$r = new ReflectionClass(LazyReferencedItem::class);
$o = $r->newLazyGhost(function ($o) {
    $o->id = 9;
    throw new Exception;
});
$r->getProperty('id')->skipLazyInitialization($o);
$id = &$o->id;
try { $o->value; } catch (Exception $e) {}
var_dump($id, $o->id);
