<?php
// define()'s third argument: true also warns that it is ignored
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) { echo "$no: $msg\n"; return true; });
var_dump(define('my_Constant', 5, true));
try {
    var_dump(MY_CONSTANT);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(define('OTHER', 6, false));
var_dump(define('THIRD', 7, 1));
var_dump(define('FOURTH', 8, 0));
