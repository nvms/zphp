<?php
// a float key past the int range warns; a handler that frees the array
// leaves nothing to find

set_error_handler(function ($errno, $errstr) {
    global $ary;
    $ary = null;
    echo "[$errno] $errstr\n";
    return true;
});

$ary = [rand()];
var_dump(isset($ary[1.0E+42]));
$ary = [rand()];
var_dump(array_key_exists(1.0E+42, $ary));
$ary = [rand()];
var_dump(\array_key_exists(1.0E+42, $ary));

$ary = [5];
$copy = $ary;
var_dump(isset($ary[1.0E+42]), $copy);

var_dump(isset([1][1.0E+42]));
var_dump(array_key_exists(1.0E+42, [1]));
