<?php
// a name in parentheses before `::` is an expression (a constant), not a
// class name
namespace App;

class Foo {
    public static function m() { return __METHOD__; }
}
const bar = 'App\Foo';
const Foo = 'stdClass';
var_dump((bar)::m());
var_dump(Foo::m());
try {
    var_dump((Foo)::m());
} catch (\Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    var_dump((nope)::m());
} catch (\Error $e) {
    echo $e->getMessage(), "\n";
}
