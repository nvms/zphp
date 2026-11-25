<?php
// a class expression that can't name a class fails as php fetches the class,
// before the method name or any argument is evaluated
function p($s) { echo "eval $s\n"; return $s; }
class K {
    public static function m(...$a) { echo "K::m(", implode(', ', $a), ")\n"; return new static; }
    public function __destruct() { echo "K destroyed\n"; }
}
function k() { return 'K'; }
function obj() { return new K; }
$null = null;
$int = 5;
$name = 'K';
foreach ([
    fn() => $null::$int(),
    fn() => $null::{p('m')}(),
    fn() => $null::m(p('arg')),
    fn() => new $int(p('arg')),
    fn() => (p(1))::m(p(2)),
    fn() => $int::m(...[p('spread')]),
    fn() => $null::{p('m')}(...[p('spread')]),
    fn() => $name::m(p('x')),
    fn() => (k())::m(p('y')),
    fn() => new $name(p('ctor')),
] as $i => $f) {
    echo "-- $i\n";
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
// a call's result used as the class keeps the object its owner holds
class Holder {
    private $kept = [];
    public function get() { return $this->kept[0] ??= new K; }
    public function check() { return $this->get()::class . ' ' . get_class($this->get()::m('again')); }
}
$h = new Holder;
echo $h->check(), "\n";
echo $h->check(), "\n";
var_dump($h->get() instanceof K);
