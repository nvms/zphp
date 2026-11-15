<?php
// $a .= $b converts the variable first, then the value, and keeps the
// variable's value as it was read while a warning's handler runs

set_error_handler(function ($no, $msg) {
    global $g;
    echo "handler: $msg\n";
    $g = 0x123;
    return true;
});

$g = str_repeat('a', 1);
$g .= [0];
var_dump($g);

$g = [1];
$g .= 'tail';
var_dump($g);

$g = [1];
$g .= [2];
var_dump($g);

function local() {
    set_error_handler(function ($no, $msg) use (&$v) {
        echo "local handler: $msg\n";
        $v = 'replaced';
        return true;
    });
    $v = str_repeat('b', 2);
    $v .= [0];
    var_dump($v);
    $v = [];
    $v .= '';
    var_dump($v);
    restore_error_handler();
}
local();
