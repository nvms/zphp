<?php
// a port outside 0..65535 is refused instead of wrapping to a 16-bit one
set_error_handler(function ($no, $msg) {
    echo "warning: ", preg_replace('/\d{5,}/', 'N', $msg), "\n";
    return true;
});

$srv = stream_socket_server("tcp://127.0.0.1:0");
$name = stream_socket_get_name($srv, false);
$port = (int) substr($name, strrpos($name, ':') + 1);
$wrapped = $port + 65536;

$c = stream_socket_client("tcp://127.0.0.1:$wrapped", $errno, $errstr, 1);
var_dump($c, $errno, $errstr === "Failed to parse port of address \"127.0.0.1:$wrapped\"");
var_dump(fsockopen("127.0.0.1", $wrapped, $errno, $errstr, 1));
var_dump($errstr === "Failed to parse port of address \"127.0.0.1:$wrapped\"");
foreach (["tcp://[::1]:$wrapped", "tcp://127.0.0.1:-1", "tcp://127.0.0.1:99999999999999999999", "tcp://127.0.0.1:-99999999999999999999", "udp://127.0.0.1:70000"] as $target) {
    var_dump(stream_socket_client($target, $errno, $errstr, 1));
    echo preg_replace('/\d{5,}/', 'N', $errstr), "\n";
}
var_dump(stream_socket_server("tcp://127.0.0.1:65536", $errno, $errstr));
echo $errstr, "\n";

$udp = stream_socket_server("udp://127.0.0.1:0", $errno, $errstr, STREAM_SERVER_BIND);
$client = stream_socket_client("udp://127.0.0.1:1");
var_dump(stream_socket_sendto($client, "x", 0, "127.0.0.1:65536"));
var_dump(stream_socket_sendto($client, "x", 0, "127.0.0.1:-5"));

// ports in range, with the leading text strtol skips, still work
$c = stream_socket_client("tcp://127.0.0.1: $port", $errno, $errstr, 1);
var_dump(stream_socket_get_name($c, true) === "127.0.0.1:$port");
$c = stream_socket_client("tcp://127.0.0.1:+$port", $errno, $errstr, 1);
var_dump(stream_socket_get_name($c, true) === "127.0.0.1:$port");
