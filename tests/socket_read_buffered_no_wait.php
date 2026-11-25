<?php
// a read on a blocking socket that already took bytes from the stream's
// buffer returns them without waiting for more to arrive
[$a, $b] = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, STREAM_IPPROTO_IP);
fwrite($b, "Hello 1\n" . str_repeat('a', 300) . "\n");
var_dump(strlen(fread($a, 8)));
var_dump(strlen(fread($a, 256)));
var_dump(strlen(fread($a, 256)));
fwrite($b, "Hello 2\n");
var_dump(fread($a, 256));
fclose($b);
var_dump(fread($a, 256), feof($a));
