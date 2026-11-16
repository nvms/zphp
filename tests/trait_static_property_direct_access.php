<?php
// a trait's static properties have storage of their own: reaching one
// through the trait is deprecated and doesn't touch the classes using it

set_error_handler(function ($errno, $errstr, $file, $line) {
    echo "[$errno] $errstr (line $line)\n";
    return true;
});

trait T {
    public static $foo = 1;
    public static $list = [];
    protected static $hidden = 'h';

    public static function read() {
        return static::class . ' ' . self::$foo;
    }
}

class C {
    use T;
}

function test() {
    T::$foo = 42;
    var_dump(T::$foo);
}
test();
test();
var_dump(C::$foo);
C::$foo = 7;
var_dump(T::$foo, C::$foo);

T::$foo++;
T::$foo += 10;
T::$list[] = 'a';
var_dump(T::$foo, T::$list, isset(T::$foo), isset(T::$nope), C::$list);
$ref = &T::$foo;
$ref = 99;
var_dump(T::$foo);
try {
    var_dump(T::$hidden);
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    var_dump(T::$missing);
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
echo C::read(), "\n";
var_dump(class_exists('T'), trait_exists('T'), in_array('T', get_declared_classes()), (new ReflectionClass('T'))->isTrait());
echo T::read(), "\n";
