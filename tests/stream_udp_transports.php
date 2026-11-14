<?php
// the datagram transports udp:// and udg://, and stream_socket_recvfrom /
// stream_socket_sendto over them
for ($port = 31400; $port < 31600; ++$port) {
    $uri = "udp://127.0.0.1:$port";
    $server = @stream_socket_server($uri, $errno, $errstr, STREAM_SERVER_BIND);
    if ($server) break;
}
var_dump(stream_get_meta_data($server)['stream_type']);
$client = stream_socket_client($uri);
var_dump(fwrite($client, "first\n"));
var_dump(fread($server, 100));
var_dump(stream_socket_sendto($client, "second"));
var_dump(stream_socket_recvfrom($server, 3, STREAM_PEEK));
var_dump(stream_socket_recvfrom($server, 100, 0, $from));
var_dump(preg_replace("/:\d+$/", ":PORT", $from));
var_dump(stream_socket_sendto($client, "third"));
var_dump(stream_socket_recvfrom($server, 100, STREAM_PEEK, $from));
var_dump(preg_replace('/:\d+$/', ':PORT', $from));
$reply_to = $from;
var_dump(fread($server, 100));
var_dump(stream_socket_sendto($server, "reply", 0, $reply_to));
var_dump(fread($client, 100));
var_dump(@stream_socket_sendto($server, "x", 0, "not an address"));
fclose($client);
fclose($server);

// a connected udp socket to a port nobody listens on: the write succeeds,
// the read fails
$fp = fsockopen("udp://127.0.0.1", 9);
var_dump(fwrite($fp, "\n"));
stream_set_timeout($fp, 1);
var_dump(fread($fp, 40));
fclose($fp);

// listening makes no sense for datagrams
var_dump(@stream_socket_server("udp://127.0.0.1:$port", $errno, $errstr));
var_dump($errstr);

$path = sys_get_temp_dir() . '/zphp-udg-' . getmypid() . '.sock';
@unlink($path);
$server = stream_socket_server("udg://$path", $errno, $errstr, STREAM_SERVER_BIND);
$client = stream_socket_client("udg://$path");
fwrite($client, "over a unix datagram socket\n");
var_dump(fread($server, 100));
var_dump(stream_get_meta_data($client)['stream_type']);
fclose($client);
fclose($server);
unlink($path);

$file = fopen('php://memory', 'r+');
var_dump(stream_socket_recvfrom($file, 10, STREAM_PEEK, $addr), $addr);
var_dump(stream_socket_sendto($file, "x"));
try {
    stream_socket_recvfrom($file, 0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(STREAM_OOB, STREAM_PEEK);
