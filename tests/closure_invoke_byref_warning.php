<?php
// a closure's __invoke called through a callback array warns under that
// name when a by-reference parameter gets a value
set_error_handler(function ($no, $msg) { echo $msg, "\n"; return true; });
$test = function (&$arg, $other) { $arg = 1; return 'called'; };
var_dump(call_user_func([$test, '__invoke'], null, 2));
var_dump(call_user_func([$test, '__INVOKE'], null, 2));
var_dump(call_user_func($test, null, 2));
var_dump(call_user_func_array([$test, '__invoke'], [null, 2]));
