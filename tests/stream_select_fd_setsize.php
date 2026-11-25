<?php
// stream_select() refuses descriptors at or past FD_SETSIZE with php's
// warning (php selects with select(2))
var_dump(PHP_FD_SETSIZE > 0);
if (PHP_OS_FAMILY === 'Windows' || !function_exists('posix_setrlimit')
    || !posix_setrlimit(POSIX_RLIMIT_NOFILE, PHP_FD_SETSIZE + 64, PHP_FD_SETSIZE + 64)) {
    echo "unsupported here\n";
    return;
}
$streams = [];
for ($i = 0; $i < PHP_FD_SETSIZE; $i++) {
    $streams[] = fopen(__FILE__, 'r');
}
[$reader, $writer] = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, STREAM_IPPROTO_IP);
set_error_handler(function ($no, $msg) {
    echo strtok($msg, "\n"), "\n";
    return true;
});
for ($i = 0; $i < 3; $i++) {
    $read = [$reader];
    $write = $except = null;
    var_dump(stream_select($read, $write, $except, 0));
}
var_dump(fwrite($writer, 'x'), fread($reader, 1));
