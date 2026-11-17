<?php
// a keyword is an ordinary part of a namespaced name, and enum is a name
// unless a declaration follows it
namespace iter\fn {
    function test() { return __FUNCTION__; }
}
namespace enum {
    class Foo {}
}
namespace list\match\static {
    const VALUE = __NAMESPACE__;
}
namespace foo {
    class Bar {}
    class enum extends Bar {}
    // a lone fully qualified keyword stays the keyword
    define('foo\true', 'foo true');
    var_dump(true, \true, namespace\true, \null);
}
namespace {
    use iter\fn;
    class enum {}
    function enum() { return 'enum function'; }
    const enum = 'enum constant';
    enum Suit { case Hearts; }
    enum /* comment */ Size: int { case S = 1; }

    echo fn\test(), "\n";
    echo \iter\fn\test(), "\n";
    var_dump(new enum\Foo(), new \enum\Foo(), new enum(), enum(), enum);
    echo list\match\static\VALUE, "\n";
    var_dump(get_parent_class(new foo\enum()), Suit::Hearts, Size::S);
}
