<?php
// __METHOD__ is empty directly in a class body; __FUNCTION__ there names the
// function the class is declared in

namespace N;

class Foo {
    const X = __METHOD__;
    const F = __FUNCTION__;
    const C = __CLASS__;
    public $p = __METHOD__ . "|" . __FUNCTION__;
    public static $s = __METHOD__;
    function m($a = __METHOD__, $b = __FUNCTION__) { return [$a, $b, __METHOD__]; }
}

interface I {
    const M = __METHOD__;
    const F = __FUNCTION__;
}

function foo() {
    class Bar {
        const X = __METHOD__;
        const F = __FUNCTION__;
        public $p = __METHOD__ . "|" . __FUNCTION__;
        function m($a = __METHOD__) { return $a; }
    }
    return [__FUNCTION__, __METHOD__];
}

var_dump(foo());
var_dump(Foo::X, Foo::F, Foo::C, (new Foo)->p, Foo::$s, (new Foo)->m());
var_dump(I::M, I::F);
var_dump(Bar::X, Bar::F, (new Bar)->p, (new Bar)->m());
