<?php
// a first-class callable of an unqualified name in a namespace keeps, at
// each site, the function it first found by falling back to the global one,
// even once the namespaced function is declared
namespace Foo;

function foo(\Closure $c = strrev(...)) {
    $d = strrev(...);
    var_dump($c("abc"), $d("abc"));
    $e = strrev(...);
    var_dump($e("abc"), $d === $e);
    var_dump(new \ReflectionFunction($d)->getName());
}

function bar() {
    // first run after the declaration: the namespaced function
    $d = strrev(...);
    var_dump($d("abc"));
    var_dump(new \ReflectionFunction($d)->getName());
}

function baz(\Closure $c = strrev(...)) {
    var_dump($c("abc"));
}

foo();
if (random_int(1, 2) > 0) {
    function strrev(string $value) {
        return 'not the global one';
    }
}
foo();
bar();
baz();
var_dump(\strrev(...)("abc"));
var_dump(namespace\strrev(...)("abc"));
$n = 'Foo\strrev';
var_dump($n(...)("x"));
