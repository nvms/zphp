<?php
// declared types print in php's order: classes and intersections as
// written, then the built-in types in a fixed order, iterable as
// Traversable|array

interface X {}
interface Y {}
class C {}

function a((X&Y)|null $v) {}
function b(null|(X&Y) $v) {}
function c(int|(X&Y) $v) {}
function d(C|(X&Y)|int $v) {}
function e(int|string|bool|null $v) {}
function f(?iterable $v) {}
function g(iterable|int $v) {}
function h(float|int|false $v) {}
function i(): string|int|null { return []; }

foreach (['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] as $fn) {
    try {
        $fn(in_array($fn, ["f", "g"]) ? new C : []);
    } catch (TypeError $e) {
        echo preg_replace('/, called in .*/', '', $e->getMessage()), "\n";
    }
}
try {
    i();
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
