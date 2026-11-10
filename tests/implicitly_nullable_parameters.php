<?php
// a parameter whose default is null takes null whatever its declared type,
// and its type reads as nullable

interface X {}
interface Y {}
class Foo {}

function a(Foo $v = null) { var_dump($v); }
function b(int $v = null) { var_dump($v); }
function c(X&Y $v = null) { var_dump($v); }
function d(int|string $v = null) { var_dump($v); }
function e(true $v = null) { var_dump($v); }
function f(?int $v = null) { var_dump($v); }

a(null);
b(null);
c(null);
d(null);
e(null);
f(null);
try {
    c(1);
} catch (TypeError $e) {
    echo preg_replace('/, called in .*/', '', $e->getMessage()), "\n";
}
try {
    d([]);
} catch (TypeError $e) {
    echo preg_replace('/, called in .*/', '', $e->getMessage()), "\n";
}
echo (new ReflectionParameter('a', 0))->getType(), "\n";
var_dump((new ReflectionParameter('b', 0))->allowsNull());
