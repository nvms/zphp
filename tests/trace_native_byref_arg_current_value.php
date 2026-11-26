<?php
// a trace made while a native runs shows a by-reference argument as the
// native has left it so far, since the frame holds the reference
ini_set("zend.exception_string_param_max_len", "15");
function thrower($no, $str) { throw new Exception('warned'); }
set_error_handler('thrower');

function client() {
    $code = 5;
    $message = 'unset';
    try {
        stream_socket_client('tcp://999.999.999.999:9999', $code, $message, 0.2);
    } catch (Exception $e) {
        echo str_replace(__FILE__, 'FILE', $e->getTraceAsString()), "\n";
    }
}
client();

$code = 'before';
$message = [1];
try {
    stream_socket_client('tcp://999.999.999.999:9999', $code, $message, 0.2);
} catch (Exception $e) {
    echo str_replace(__FILE__, 'FILE', $e->getTraceAsString()), "\n";
}

$r = 'ref';
$alias = &$r;
$m = 7;
try {
    stream_socket_client('tcp://999.999.999.999:9999', $alias, $m, 0.2);
} catch (Exception $e) {
    echo str_replace(__FILE__, 'FILE', $e->getTraceAsString()), "\n";
}

$arr = ['k' => 'v'];
try {
    stream_socket_client('tcp://999.999.999.999:9999', $arr['k'], $arr['m'], 0.2);
} catch (Exception $e) {
    echo str_replace(__FILE__, 'FILE', $e->getTraceAsString()), "\n";
}

$m = 'kept';
try {
    preg_match('/(/', 'abc', $m);
} catch (Exception $e) {
    echo str_replace(__FILE__, 'FILE', $e->getTraceAsString()), "\n";
}
