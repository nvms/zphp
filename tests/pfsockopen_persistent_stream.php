<?php
// pfsockopen() opens php's "persistent stream" resource; fsockopen() a
// plain stream

$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
$address = stream_socket_get_name($server, false);
[$host, $port] = explode(':', $address);

$persistent = pfsockopen($host, (int) $port, $errno, $errstr, 5);
$plain = fsockopen($host, (int) $port, $errno, $errstr, 5);
var_dump(get_resource_type($persistent), get_resource_type($plain));
ob_start();
var_dump($persistent);
echo preg_replace('/resource\(\d+\)/', 'resource(N)', ob_get_clean());
fwrite($persistent, "x");
$peer = stream_socket_accept($server, 5);
var_dump(fread($peer, 1));
fclose($persistent);
var_dump(get_resource_type($persistent));
