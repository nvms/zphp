<?php
// regression: is_callable()'s third by-ref parameter receives the resolved
// callable name. previously only the plain-string and Class::method-string
// forms populated it; the [$obj, 'method'], ['Class', 'method'] and bare
// __invoke object forms left it untouched.
class C {
    public function m() {}
    public static function s() {}
    public function __invoke() {}
}
function freestanding() {}
$c = new C;

$name = 'UNSET';
is_callable('freestanding', false, $name);
echo $name, "\n";                       // freestanding

$name = 'UNSET';
is_callable('C::s', false, $name);
echo $name, "\n";                       // C::s

$name = 'UNSET';
is_callable([$c, 'm'], false, $name);
echo $name, "\n";                       // C::m

$name = 'UNSET';
is_callable(['C', 's'], false, $name);
echo $name, "\n";                       // C::s

$name = 'UNSET';
is_callable($c, false, $name);
echo $name, "\n";                       // C::__invoke

// the name is filled even when the callable does not resolve
$name = 'UNSET';
$ok = is_callable([$c, 'missing'], false, $name);
echo var_export($ok, true), " ", $name, "\n";   // false C::missing

// works without the optional third arg (no crash)
var_dump(is_callable([$c, 'm']));
var_dump(is_callable('freestanding'));
