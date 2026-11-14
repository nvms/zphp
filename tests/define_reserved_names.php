<?php
// __COMPILER_HALT_OFFSET__ can never be defined, and "_" is a deprecated
// class alias

set_error_handler(function ($no, $msg) { echo "[$no] $msg\n"; return true; });

var_dump(define('__COMPILER_HALT_OFFSET__', 1));
var_dump(define('__COMPILER_HALT_OFFSET__1', 1));
var_dump(defined('__COMPILER_HALT_OFFSET__'));
var_dump(__COMPILER_HALT_OFFSET__1);

var_dump(class_alias('stdClass', '_'));
var_dump(get_class(new _));
var_dump(class_alias('stdClass', '__'));
