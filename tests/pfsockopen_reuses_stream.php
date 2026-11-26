<?php
// pfsockopen() and STREAM_CLIENT_PERSISTENT hand back the live persistent
// stream of the same address; closing it closes it for every holder, and a
// stream whose peer is gone is replaced
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
$address = stream_socket_get_name($server, false);
[$host, $port] = explode(':', $address);

$a = pfsockopen($host, (int) $port, $errno, $errstr, 5);
$b = pfsockopen($host, (int) $port, $errno, $errstr, 5);
var_dump($a === $b, (int) $a === (int) $b, $errno, $errstr);
$peer = stream_socket_accept($server, 5);
fwrite($b, "x");
var_dump(fread($peer, 1));
fclose($b);
try {
    fwrite($a, "y");
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
fclose($peer);

$c = stream_socket_client("tcp://$address", $errno, $errstr, 5, STREAM_CLIENT_CONNECT | STREAM_CLIENT_PERSISTENT);
$d = stream_socket_client("tcp://$address", $errno, $errstr, 5, STREAM_CLIENT_CONNECT | STREAM_CLIENT_PERSISTENT);
var_dump($c === $d, get_resource_type($c));
$e = stream_socket_client("tcp://$address", $errno, $errstr, 5);
var_dump($e === $c, get_resource_type($e));
$peer = stream_socket_accept($server, 5);
// the peer goes away: the next open finds the stream dead
fclose($peer);
usleep(100000);
$f = stream_socket_client("tcp://$address", $errno, $errstr, 5, STREAM_CLIENT_CONNECT | STREAM_CLIENT_PERSISTENT);
var_dump($f === $c, get_resource_type($c), get_resource_type($f));

// a different port is a different stream
$other = stream_socket_server('tcp://127.0.0.1:0');
[, $port2] = explode(':', stream_socket_get_name($other, false));
$g = pfsockopen($host, (int) $port2);
$h = pfsockopen($host, (int) $port);
var_dump($g === $h);
