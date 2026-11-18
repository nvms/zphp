<?php
// a failed connect clears the error outputs first and writes them after its
// warnings: a lookup failure warns with the resolver's reason, which is the
// error message too

$code = 99;
$msg = 'old';
set_error_handler(function ($no, $str) {
    global $code, $msg;
    $str = preg_replace('/failed: .*/', 'failed: REASON', $str);
    $str = preg_replace('/\(php_network.*\)$/', '(LOOKUP)', $str);
    echo "warning: $str\n";
    var_dump($code, $msg === '' ? 'empty' : 'set');
    return true;
});
var_dump(stream_socket_client('tcp://256.1.1.1:1', $code, $msg, 1));
var_dump($code, str_starts_with($msg, 'php_network_getaddresses: getaddrinfo for 256.1.1.1 failed: '));

$c = 5;
$m = 'x';
var_dump(fsockopen('256.1.1.1', 80, $c, $m, 1));
var_dump($c, str_starts_with($m, 'php_network_getaddresses: getaddrinfo for 256.1.1.1 failed: '));
