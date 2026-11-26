<?php
// a named argument sent to a by-reference parameter: a value is php's
// "could not be passed by reference" Error when it is sent, before the call
// checks for missing arguments, and a call's result is the notice
set_error_handler(function ($no, $msg, $file, $line) {
    echo "notice: $msg on line $line\n";
    return true;
});

function test($a, &$e) { $e = 'set'; }
function f() { return 1; }
function &r() { static $s = 1; return $s; }
function v(&...$rest) { foreach ($rest as $k => &$x) $x = "v$k"; }
class C {
    function m($a, &$b) { $b = 'm'; }
    static function s(&$b, $c = 0) { $b = 's'; }
}
function show($label, $f) {
    try {
        $f();
        echo "$label ok\n";
    } catch (Throwable $e) {
        echo "$label ", $e::class, ': ', $e->getMessage(), "\n";
    }
}

show('positional literal', function () { test(1, 42); });
show('positional call', function () { test(1, f()); });
show('named literal', function () { test(e: 42); });
show('named literals', function () { test(a: 1, e: 42); });
show('named call', function () { test(a: 1, e: f()); });
show('named call missing', function () { test(e: f()); });
show('dynamic literal', function () { $n = 'test'; $n(e: 42); });
show('dynamic call', function () { $n = 'test'; $n(e: f()); });
show('declared later', function () { later(e: 42); });
show('declared later call', function () { later(e: f()); });
function later($a, &$e) {}

show('var', function () { test(a: 1, e: $x); var_dump($x); });
show('dim', function () { $arr = []; test(e: $arr['k'], a: 1); var_dump($arr); });
show('returned reference', function () { test(a: 1, e: r()); var_dump(r()); });
show('variadic literal', function () { v(x: 1); });
show('variadic var', function () { v(x: $q, y: $w); var_dump($q, $w); });
show('method literal', function () { (new C)->m(b: 2, a: 1); });
show('method call', function () { (new C)->m(b: strlen('x'), a: 1); });
show('static literal', function () { C::s(b: 2); });
show('static var', function () { C::s(c: 1, b: $z); var_dump($z); });
show('unknown name', function () { test(a: 1, zz: 3); });
show('native literal', function () { preg_match(subject: 'abc', pattern: '/b/', matches: 5); });
show('native var', function () { preg_match(subject: 'abc', pattern: '/b/', matches: $m); var_dump($m); });
show('callee read first', function () { $n = 'test'; $n(a: $n = 'nope', e: $y); var_dump($y, $n); });
show('mixed literal', function () { test(1, e: 2); });
show('mixed var', function () { test(1, e: $u); var_dump($u); });
show('after unpack', function () { $args = [1]; test(...$args, e: 4); });
show('constructor', function () { new class(b: 1) { function __construct(&$b) {} }; });
show('closure', function () { $c = function ($a, &$b) {}; $c(b: 1, a: 2); });
show('first-class callable', function () { $c = test(...); $c(e: 1, a: 2); });
show('array callable', function () { $c = [new C, 'm']; $c(b: 1, a: 2); });
show('string callable', function () { $c = 'C::s'; $c(b: 1); });
show('first-class callable positional', function () { $c = test(...); $c(2, 1); });
show('array callable positional', function () { $c = [new C, 'm']; $c(2, 1); });
show('string callable positional', function () { $c = 'C::s'; $c(1); });
show('partial named literal', function () { $p = test(?, e: 1); });
show('partial named call', function () { $p = test(a: 1, e: strlen('a')); });
