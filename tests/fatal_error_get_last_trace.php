<?php
// a class redeclaration is a compile error (E_COMPILE_ERROR) wherever the
// class is bound, and a fatal error leaves error_get_last() the stack it
// stopped on
register_shutdown_function(function () {
    $e = error_get_last();
    $e['message'] = str_replace(__FILE__, 'FILE', $e['message']);
    $e['file'] = str_replace(__FILE__, 'FILE', $e['file']);
    foreach ($e['trace'] as &$frame) $frame['file'] = str_replace(__FILE__, 'FILE', $frame['file']);
    var_dump($e);
});

function declare_twice($n) {
    eval("class Foo {}; class Foo {}");
}
trigger_error('first', E_USER_WARNING);
declare_twice(1);
