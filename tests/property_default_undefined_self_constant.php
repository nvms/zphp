<?php
// a property default reading self:: or parent:: is evaluated at the class's
// first use, as written (the error names self), with a [constant expression]
// frame at the line that needed it

class A {
    public $v = self::MISSING;
}
class P {
    const OK = 1;
}
class Q extends P {
    public $a = parent::OK;
    public $b = self::NOPE;
    public static $s = self::ALSO_MISSING;
}
class R {
    const X = 5;
    public $v = [self::X, 'k' => self::X * 2];
    public static $s = self::X + 1;
}

echo "declared\n";

function make($class) {
    return new $class;
}

foreach (['A', 'Q'] as $class) {
    try {
        make($class);
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
    }
}
try {
    echo Q::$s;
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
var_dump(new R, R::$s);
try {
    new A;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(new stdClass);
