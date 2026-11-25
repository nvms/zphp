<?php
// stream_socket_accept() and stream_socket_client() refuse a timeout that
// isn't finite
$server = stream_socket_server("tcp://127.0.0.1:0");
foreach ([NAN, -NAN, INF, -INF] as $value) {
    try {
        stream_socket_accept($server, $value);
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
    try {
        stream_socket_client("tcp://127.0.0.1:1", timeout: $value);
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
fclose($server);
