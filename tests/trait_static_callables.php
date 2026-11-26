<?php
// a trait's static methods as callables: found like a class's, deprecated
// where php's get_static_method runs (dynamic calls, first-class callables)
set_error_handler(function ($no, $msg, $file, $line) {
    echo "E$no: $msg (line $line)\n";
    return true;
});

trait Foo {
    public static function myMethod(string $foo) {
        echo "Called ", __METHOD__, " ", static::class, " ", $foo, PHP_EOL;
    }
    public function inst() {}
    private static function priv() {}
}

var_dump(is_callable('Foo::myMethod'));
var_dump(is_callable(['Foo', 'myMethod']));
var_dump(is_callable('foo::MYMETHOD'));
var_dump(is_callable('Foo::priv'));
call_user_func('Foo::myMethod', 'a');
call_user_func(['Foo', 'myMethod'], 'b');
$f = 'Foo::myMethod';
$f('c');
$f = ['Foo', 'myMethod'];
$f('c2');
$c = Closure::fromCallable('Foo::myMethod');
$c('d');
$c = Foo::myMethod(...);
var_dump($c);
$c('e');
$c('e2');
try { $c = Foo::inst(...); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $c = Foo::priv(...); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $c = Foo::nope(...); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(new ReflectionFunction(Foo::myMethod(...))->getName());

const C = Foo::myMethod(...);
var_dump(C);
(C)('f');

// a throwing handler stops the callable from being made
set_error_handler(function ($no, $msg) {
    throw new ErrorException($msg);
});
try {
    $c = Foo::myMethod(...);
    echo "not reached\n";
} catch (ErrorException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
