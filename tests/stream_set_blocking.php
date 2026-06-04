<?php

// stream_set_blocking toggles O_NONBLOCK on the stream's fd. on a non-blocking
// stream with no pending data, fread returns "" (not false) - php treats EAGAIN
// as "nothing yet", not a hard error.

$pair = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
[$a, $b] = $pair;

// switching to non-blocking succeeds
echo "set nonblock: ", (stream_set_blocking($a, false) ? 'y' : 'n'), "\n"; // y

// nothing written to $b yet -> non-blocking read of $a yields "" not false
$r = fread($a, 16);
echo "empty read: ", var_export($r, true), "\n"; // ''

// write, then a non-blocking read returns the data
fwrite($b, "ping");
echo "data read: ", fread($a, 16), "\n"; // ping

// switch back to blocking succeeds
echo "set block: ", (stream_set_blocking($a, true) ? 'y' : 'n'), "\n"; // y

fclose($a);
fclose($b);
