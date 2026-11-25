<?php
// a local server socket keeps the context it was made with, and a timed
// out stream_socket_accept() reports with it (AcceptFailed)

$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
var_dump(stream_socket_accept($server, 0));
fclose($server);

$ctx = stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Silent], 'socket' => ['backlog' => 4]]);
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $ctx);
var_dump(stream_context_get_options($server)['socket']);
var_dump(stream_socket_accept($server, 0));
foreach (stream_last_errors() as $e) {
    echo $e->code->name, " ", $e->wrapperName, " ", var_export($e->terminating, true), " ", $e->message, "\n";
}
fclose($server);

$ctx = stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Exception]]);
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, $ctx);
try {
    stream_socket_accept($server, 0);
} catch (StreamException $e) {
    echo get_class($e), ": ", $e->getMessage(), " (", $e->getCode(), ")\n";
}
$client = stream_socket_client(stream_socket_get_name($server, false), $errno, $errstr, 1, STREAM_CLIENT_CONNECT, $ctx);
var_dump(array_keys(stream_context_get_options($client)));
$peer = stream_socket_accept($server, 1);
var_dump(is_resource($peer));
fclose($client);
fclose($peer);
fclose($server);
