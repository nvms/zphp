<?php
// ReflectionConstant keeps the name as given in its name property, and
// reports the constant's own name from its methods
namespace Foo {
    const C = 42;
}
namespace {
    const C = 43;
    foreach (['C', '\C', 'Foo\C', '\Foo\C', 'PHP_VERSION_ID', '\E_ALL'] as $name) {
        $r = new ReflectionConstant($name);
        var_dump($r->name, $r->getName(), $r->getNamespaceName(), $r->getShortName(), $r->getValue() !== null);
    }
    var_dump(new ReflectionConstant('\C'));
    try {
        new ReflectionConstant('\Missing');
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
}
