<?php
// calls that pass their arguments as an array keep every one of them,
// however many there are

function count_args(...$a) { return count($a); }
class Many {
    public $n;
    function __construct(...$a) { $this->n = count($a); }
    function m(...$a) { return count($a); }
}

foreach ([0, 1, 16, 17, 40] as $n) {
    $args = $n ? range(1, $n) : [];
    $obj = new Many;
    echo $n, ": ", implode(" ", [
        call_user_func_array('count_args', $args),
        (new ReflectionFunction('count_args'))->invokeArgs($args),
        (new ReflectionMethod('Many', 'm'))->invokeArgs($obj, $args),
        (new ReflectionClass('Many'))->newInstanceArgs($args)->n,
    ]), "\n";
}
