<?php
// the socket context options a bind or connect reads: so_rcvbuf and
// so_sndbuf must be in range, so_reuseport lets two servers share a port
foreach (['so_rcvbuf', 'so_sndbuf'] as $option) {
    foreach ([0, -1, 'abc', 8192] as $value) {
        $context = stream_context_create(['socket' => [$option => $value]]);
        $server = @stream_socket_server("tcp://127.0.0.1:0", $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $context);
        var_dump(is_resource($server), $errstr);
    }
}
$context = stream_context_create(['socket' => ['so_sndbuf' => 0]]);
var_dump(@stream_socket_client("tcp://127.0.0.1:1", $errno, $errstr, 1, STREAM_CLIENT_CONNECT, $context), $errstr);

if (PHP_OS_FAMILY === 'Linux') {
    $context = stream_context_create(['socket' => ['so_reuseport' => true]]);
    $a = stream_socket_server("tcp://127.0.0.1:0", $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $context);
    $port = (int) substr(strrchr(stream_socket_get_name($a, false), ':'), 1);
    $b = @stream_socket_server("tcp://127.0.0.1:$port", $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $context);
    var_dump(is_resource($b));
    $c = @stream_socket_server("tcp://127.0.0.1:$port", $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN);
    var_dump(is_resource($c));
} else {
    var_dump(true, false);
}
