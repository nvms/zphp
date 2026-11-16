<?php
// a method call spanning lines is on the line of the method name, in traces
// and in the errors it raises; a function call is on the line it starts

function line_of_call($a = null) {
    return debug_backtrace()[0]["line"];
}

class A {
    public function m($x = null) {
        return debug_backtrace()[0]["line"];
    }
    public static function s($x = null) {
        return (new Exception)->getTrace()[0]["line"];
    }
}

$o = new A;
var_dump($o
    ->m(
        1
    ));
var_dump(line_of_call(
    2
));
var_dump(A::
    s(
        3));
var_dump((new A(
))
    ->m());
var_dump($o?->
    m(1));

try {
    $n = null;
    $n
        ->m(
            1);
} catch (Error $e) {
    var_dump($e->getLine());
}

var_dump(line_of_call
(
    4
));
var_dump(\line_of_call
(
));
