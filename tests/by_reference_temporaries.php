<?php
// what php does with values that are no variables where references are
// expected: a call's result passed or assigned by reference gives a notice,
// any other value passed by reference is an Error, and a function returning
// by reference that returns no variable gives a notice
set_error_handler(function ($no, $msg, $file, $line) {
    echo "[$no] $msg (line $line)\n";
    return true;
});

function takesRef(&$r) {
    $r = "changed";
    return "took";
}
function value() {
    return "value";
}
function &reference() {
    static $kept = "kept";
    return $kept;
}
function &literal() {
    return 42;
}
function &nothing() {
}
class K {
    const C = 1;
    public static $s = "static";
    public function m(&$x) {
        return $x;
    }
}

echo takesRef(value()), "\n";
echo reference(), "\n";
foreach ([fn () => takesRef(1), fn () => takesRef(K::C), fn () => takesRef($a = 2), fn () => (new K)->m("x"), fn () => str_replace("a", "b", "c", strlen("d"))] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
takesRef(K::$s);
echo K::$s, "\n";

$x = &value();
echo $x, "\n";
$y = &literal();
var_dump($y);
$z = &nothing();
var_dump($z);
$arr = [];
$arr['k'] = &value();
$obj = new stdClass;
$obj->p = &value();
var_dump($arr, $obj);

function &passThrough() {
    return value();
}
var_dump(passThrough());
echo count([1, 2]), " ", strlen("abc"), "\n";
