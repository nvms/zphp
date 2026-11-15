<?php
// any expression in the class position of a static call names the class by
// its value

class Test {
    const NAME = 'Test2';
    public static function name() { return 'Test2'; }
}

class Test2 {
    public static function foo(...$a) { return static::class . ' ' . count($a); }
    public static function viaSelf() { return (self::class)::foo(1); }
}

var_dump(Test::NAME::foo());
var_dump(('Test' . '2')::foo(1, 2));
var_dump((Test::NAME)::foo(...[1, 2, 3]));
var_dump(Test2::viaSelf());
$o = new Test2;
var_dump(($o)::foo());
try {
    (Test::NAME . 'x')::foo();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
