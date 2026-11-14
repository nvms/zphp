<?php
// forward_static_call passes the caller's static:: to a static method of a
// class it extends, and needs a class scope

class A {
    const NAME = 'A';
    public static function test(...$args) {
        echo static::class, " ", static::NAME, " ", implode(',', $args), "\n";
    }
}

class B extends A {
    const NAME = 'B';
    public static function test(...$args) {
        echo "B::test\n";
        forward_static_call(['A', 'test'], 'more', 'args');
        forward_static_call('A::test', 'string');
        forward_static_call_array(['A', 'test'], ['from', 'array']);
        forward_static_call('test', 'plain', 'function');
        forward_static_call(['Other', 'test'], 'unrelated');
        call_user_func(['A', 'test'], 'call_user_func');
    }
}

class C extends B {
    const NAME = 'C';
}

class Other {
    public static function test(...$args) { echo static::class, " ", implode(',', $args), "\n"; }
}

function test(...$args) {
    echo "function ", implode(',', $args), "\n";
}

B::test();
C::test();

function outside() {
    try {
        forward_static_call(['A', 'test']);
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        forward_static_call_array(['A', 'test'], []);
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
outside();
try {
    forward_static_call(['A', 'test']);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
