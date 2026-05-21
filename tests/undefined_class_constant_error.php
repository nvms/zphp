<?php
// regression: reading an undefined constant on a class that genuinely exists
// is a fatal Error in PHP, not a silent null. zphp's get_static_prop pushed
// null on a miss; a dedicated get_class_const opcode now throws.

class Config { const X = 1; const Y = 'hello'; }

// defined class constants resolve normally
echo Config::X, " ", Config::Y, "\n";

// undefined class constant on an existing class throws a catchable Error
try {
    echo Config::MISSING;
    echo "unreachable\n";
} catch (Error $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

// enum cases resolve; a missing case throws
enum Suit { case Hearts; case Spades; }
echo Suit::Hearts->name, "\n";
try {
    Suit::Diamonds;
} catch (Error $e) {
    echo "enum: ", $e->getMessage(), "\n";
}

// backed enum value access
enum Status: string { case On = 'on'; case Off = 'off'; }
echo Status::On->value, "\n";

// interface constants resolve; a miss throws
interface HasVersion { const VER = 'v1'; }
class Impl implements HasVersion {}
echo Impl::VER, "\n";
try {
    echo Impl::NO_SUCH_CONST;
} catch (Error $e) {
    echo "iface: ", $e->getMessage(), "\n";
}

// inherited constants resolve
class Base { const TAG = 'base'; }
class Child extends Base {}
echo Child::TAG, "\n";

// late static binding through a constant
class P { const N = 'p'; static function get() { return static::N; } }
class Q extends P { const N = 'q'; }
echo Q::get(), "\n";

// self:: inside a method
class S { const A = 10; function f() { return self::A; } }
echo (new S)->f(), "\n";

// static properties and ::class are unaffected
class WithStatic { public static $v = 42; }
echo WithStatic::$v, "\n";
echo Config::class, "\n";

// class constant used inside an expression
class Limits { const MAX = 100; }
echo Limits::MAX * 2, "\n";
