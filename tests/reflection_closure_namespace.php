<?php
namespace Foo;

// a closure is in no namespace: its short name is its whole name
class Bar {
    public function baz() {
        return function () {};
    }
}

function named() {}

$r = new \ReflectionFunction((new Bar())->baz());
var_dump($r->getShortName(), $r->getNamespaceName(), $r->inNamespace());
$r = new \ReflectionFunction(function () {});
var_dump($r->getShortName(), $r->getNamespaceName(), $r->inNamespace());
// a closure made from a function keeps the function's namespace
$r = new \ReflectionFunction(named(...));
var_dump($r->getName(), $r->getShortName(), $r->getNamespaceName(), $r->inNamespace());
$r = new \ReflectionFunction('Foo\named');
var_dump($r->getShortName(), $r->getNamespaceName(), $r->inNamespace());
