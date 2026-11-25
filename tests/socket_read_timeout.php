<?php
// a read on a blocking socket waits as long as stream_set_timeout() says;
// one that times out returns nothing and stream_get_meta_data() says so
$server = stream_socket_server('tcp://127.0.0.1:0');
$client = stream_socket_client('tcp://' . stream_socket_get_name($server, false));
$peer = stream_socket_accept($server);
var_dump(stream_get_meta_data($client)['timed_out']);
var_dump(stream_set_timeout($client, 0, 20000));
$start = microtime(true);
var_dump(fread($client, 10));
var_dump(microtime(true) - $start < 5);
var_dump(stream_get_meta_data($client)['timed_out']);
fwrite($peer, "hello");
var_dump(stream_get_meta_data($client)['timed_out']);
var_dump(fread($client, 5));
var_dump(stream_get_meta_data($client)['timed_out']);
var_dump(fgets($client));
var_dump(stream_get_meta_data($client)['timed_out'], feof($client));
