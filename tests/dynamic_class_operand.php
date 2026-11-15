<?php
// the class operand of $c::X and $c::$p: a string loses one leading
// backslash, and anything but a string or an object is an Error

class A {
    public static $b = 42;
    const C = 1;
}

$n = '\A';
var_dump($n::C);
var_dump($n::$b);
var_dump(('\A' . '')::$b);
var_dump($n::{'C'});

foreach ([1, 1.5, null, true, []] as $bad) {
    try {
        var_dump($bad::$b);
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    try {
        var_dump($bad::C);
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// a nullsafe chain skips a static property or method after it, not a
// class constant
class N {
    public static $p = 'p';
    const C = 'c';
    static function m() { return 'm'; }
    function self() { return $this; }
}
$n = null;
var_dump($n?->self()::$p, $n?->self()::m());
try {
    var_dump($n?->self()::C);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    var_dump($n?->self()::{'C'});
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$o = new N;
var_dump($o?->self()::$p, $o?->self()::m(), $o?->self()::C, $o?->self()::{'C'});
