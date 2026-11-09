<?php
class T {
    private $p;
    public function m() { $this->p = 1; return "m\n"; }
    public static function s() { return "s\n"; }
}
function run() {
    $v = 6;
    var_dump((fn() => fn() => $v)()());
    var_dump((fn() => function () use ($v) { return $v; })()());
    $mk = function ($a) { return function ($b) use ($a) { return fn($c) => $a + $b + $c; }; };
    var_dump($mk(1)(2)(3));
    $s = 'T::s';
    echo $s();
    $m = 'T::m';
    try { echo $m(); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
}
run();
$var = 6;
var_dump((fn() => fn() => $var)()());
