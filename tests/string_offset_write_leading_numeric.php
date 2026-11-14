<?php
// a leading-numeric string offset in a nested write warns and uses its
// number, as zend_check_string_offset does; a non-numeric one is an error

$s = "abc";
$s['1x'] = 'Z';
var_dump($s);

$ar = ["0", "hello"];
$ar[0]['0idx'] = "9";
$ar[1][' 2 '] = "L";
$ar[1]['4 apples'] = "O";
var_dump($ar);

$o = new stdClass;
$o->p = "hello";
$o->p['1y'] = 'E';
var_dump($o->p);

try {
    $ar[1]['x'] = 'Q';
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    $o->p['nope'] = 'Q';
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

set_error_handler(function ($no, $msg) { throw new ErrorException($msg, 0, $no); });
try {
    $ar[1]['3z'] = 'W';
} catch (ErrorException $e) {
    echo "handler threw: ", $e->getMessage(), "\n";
}
var_dump($ar[1]);
