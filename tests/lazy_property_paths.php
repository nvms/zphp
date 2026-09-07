<?php
class LazyPaths {
    public ?int $id = null;
    public int $value = 3;
    public array $items = [1];
    public function noop() { return 'noop'; }
    public function value() { return $this->value; }
}
$r = new ReflectionClass(LazyPaths::class);
foreach (['read', 'write', 'isset', 'unset', 'coalesce', 'append', 'reflect', 'raw'] as $path) {
    $o = $r->newLazyGhost(function ($o) use ($path) { echo "init:$path\n"; $o->value = 9; });
    echo $o->noop(), "\n";
    $id = $r->getProperty('id');
    var_dump($id->isLazy($o));
    $id->skipLazyInitialization($o);
    var_dump($id->isLazy($o), $id->isInitialized($o), $o->id);
    $name = 'value';
    if ($path === 'read') var_dump($o->$name);
    if ($path === 'write') $o->$name = 4;
    if ($path === 'isset') var_dump(isset($o->$name));
    if ($path === 'unset') unset($o->$name);
    if ($path === 'coalesce') var_dump($o->$name ?? 5);
    if ($path === 'append') $o->items[] = 2;
    if ($path === 'reflect') var_dump($r->getProperty('value')->getValue($o));
    if ($path === 'raw') var_dump($r->getProperty('value')->getRawValue($o));
    var_dump($r->isUninitializedLazyObject($o));
}
// Warm property ICs with ordinary instances before reading a ghost.
function readValue($o) { return $o->value; }
for ($i = 0; $i < 3; $i++) readValue(new LazyPaths);
$o = $r->newLazyGhost(function ($o) { echo "warm-init\n"; $o->value = 17; });
var_dump(readValue($o));
foreach (['vars', 'json', 'clone', 'foreach', 'cast', 'initialized'] as $path) {
    $o = $r->newLazyGhost(function ($o) use ($path) { echo "whole:$path\n"; });
    if ($path === 'vars') get_object_vars($o);
    if ($path === 'json') json_encode($o);
    if ($path === 'clone') $copy = clone $o;
    if ($path === 'foreach') foreach ($o as $value) {}
    if ($path === 'cast') var_dump((array) $o);
    if ($path === 'initialized') var_dump($r->getProperty('value')->isInitialized($o));
    var_dump($r->isUninitializedLazyObject($o));
}
