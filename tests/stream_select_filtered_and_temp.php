<?php
// stream_select takes filtered streams (php 8.6) and php://temp streams,
// which php casts by moving them to a temporary file that is always ready
$temp = fopen('php://temp', 'r+');
fwrite($temp, 'SGVsbG8gV29ybGQ=');
stream_filter_append($temp, 'convert.base64-decode');
rewind($temp);
$read = [$temp];
$write = [$temp];
$except = [$temp];
var_dump(stream_select($read, $write, $except, 5), count($read), count($write), count($except));
var_dump(fread($temp, 1024));

$plain = fopen('php://temp', 'r+');
$read = [$plain];
$write = null;
$except = null;
var_dump(stream_select($read, $write, $except, 5), count($read));

[$a, $b] = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
stream_set_blocking($a, false);
stream_filter_append($a, 'convert.base64-decode');
fwrite($b, 'SGVs');
var_dump(fread($a, 1024));
$read = [$a];
$write = null;
$except = null;
var_dump(stream_select($read, $write, $except, 0, 1000), count($read));
fwrite($b, 'bG8=');
$read = [$a];
var_dump(stream_select($read, $write, $except, 1), count($read));
var_dump(fread($a, 1024));

// a filtered socket waits with the rest
$read = [$a, $temp];
var_dump(stream_select($read, $write, $except, 0, 1000), array_keys($read));

$mem = fopen('php://memory', 'r+');
$read = [$mem];
try {
    @stream_select($read, $write, $except, 0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
