<?php
// a static method called on a trait itself runs, with the trait as its
// class, after php 8.1's deprecation; a missing one goes to the trait's
// __callStatic
set_error_handler(function ($no, $str) {
    echo "[$no] $str\n";
    return true;
});

trait T {
    public static function foo($x) {
        echo "foo($x) in ", static::class, " / ", self::class, "\n";
        return $x * 2;
    }
    public static function __callStatic($name, $args) {
        echo "__callStatic($name, ", implode(', ', $args), ")\n";
        return 'magic';
    }
}

class C {
    use T;
}

var_dump(T::foo(21));
var_dump(T::bar(1, 2));
var_dump(C::foo(1));
var_dump(C::baz());

trait OnlyMagic {
    public static function __callStatic($name, $args) {
        return strtoupper($name);
    }
}
var_dump(OnlyMagic::shout());

set_error_handler(function ($no, $str) {
    throw new ErrorException($str, 0, $no);
});
try {
    T::foo(5);
} catch (ErrorException $e) {
    echo "thrown: ", $e->getMessage(), "\n";
}
