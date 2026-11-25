<?php
// stream_socket_client() without STREAM_CLIENT_CONNECT makes the
// transport's stream without parsing the address or connecting
$s = stream_socket_client("tcp://127.0.0.1:1", $code, $message, 0, 0);
var_dump(is_resource($s), $code, $message);
$meta = stream_get_meta_data($s);
var_dump($meta['stream_type'], $meta['mode'], $meta['uri'], $meta['eof']);
var_dump(stream_socket_get_name($s, false));
fclose($s);
var_dump(get_resource_type(stream_socket_client("abc", $code, $message, 0, STREAM_CLIENT_PERSISTENT)));
var_dump(is_resource(stream_socket_client("udp://nowhere.invalid:9", $code, $message, 0, 0)));
var_dump(is_resource(stream_socket_client("unix:///nonexistent/socket", $code, $message, 0, 0)));
echo "done\n";
