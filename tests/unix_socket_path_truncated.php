<?php
// a unix socket path longer than sockaddr_un holds is cut to fit with a
// notice, as php's parse_unix_address does, and the call goes on with it
$path = '/nonexistent-zphp-dir/' . str_repeat('s', 150) . '.sock';
set_error_handler(function ($no, $msg) use ($path) {
    echo $no, ": ", str_replace($path, 'PATH', $msg), "\n";
    return true;
});
var_dump(stream_socket_client("unix://$path", $code, $message, 1));
var_dump($code > 0);
var_dump(stream_socket_server("unix://$path", $code, $message));
var_dump($code > 0);
// a path that fits is used as is
var_dump(stream_socket_client('unix:///nonexistent-zphp-dir/short.sock', $code, $message, 1));
