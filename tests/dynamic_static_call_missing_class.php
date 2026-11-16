<?php
// a static call through a variable class name and a variable method name
// fails on the missing class before it looks for the method
spl_autoload_register(function ($c) { echo "autoload $c\n"; });
$c = 'Missing';
$m = 'foo';
foreach ([fn() => $c::foo(), fn() => $c::$m(), fn() => $c::$m(...[1]), fn() => Missing::$m()] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
class Present { static function foo() { return 'present'; } }
trait T { static function t() { return 'trait'; } }
$p = 'Present';
var_dump($p::$m());
$t = 'T';
$n = 't';
var_dump(@$t::$n());
$s = 'self';
try {
    $s::$m();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
