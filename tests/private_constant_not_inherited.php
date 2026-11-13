<?php
// a private class constant isn't inherited: a subclass has no constant of
// that name; defined() is false for a constant the scope can't see

class A {
    public const X = 1;
    protected const Y = 2;
    private const Z = 3;

    public static function fromA() {
        var_dump(self::Z);
        try {
            var_dump(B::Z);
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
        var_dump(defined('A::Z'), defined('B::Z'));
    }
}
class B extends A {
    public static function check() {
        var_dump(self::X, self::Y);
        try {
            var_dump(self::Z);
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
        try {
            var_dump(constant('B::Z'));
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
        try {
            var_dump(constant('A::Z'));
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}

B::check();
A::fromA();
var_dump(defined('A::X'), defined('A::Y'), defined('A::Z'), defined('B::Z'), defined('B::Y'));
try {
    var_dump(A::Z);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
