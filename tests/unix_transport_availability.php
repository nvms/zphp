<?php
// unix and udg sockets: php's windows build has neither transport, so there
// both fail with "Unable to find the socket transport"; elsewhere a missing
// socket file is the error
foreach (['unix', 'udg'] as $t) {
    $c = @stream_socket_client("$t:///nonexistent-zphp-dir/x.sock", $errno, $errstr, 1);
    var_dump($c, $errstr);
    $s = @stream_socket_server("$t:///nonexistent-zphp-dir/x.sock", $errno, $errstr, $t === 'udg' ? STREAM_SERVER_BIND : STREAM_SERVER_BIND | STREAM_SERVER_LISTEN);
    var_dump($s, $errstr);
}
var_dump(in_array('unix', stream_get_transports()), in_array('udg', stream_get_transports()));
