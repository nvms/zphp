<?php
// syslog() without openlog() opens the log itself, so the built-in server
// closes it at the request's end like one openlog() opened: the socket a
// request's syslog() made is gone in the next request. linux only (it reads
// /proc/self/fd); elsewhere, or without /dev/log, the expected lines print
$router = <<<'PHP'
<?php
function sockets() {
    $sockets = [];
    foreach (scandir('/proc/self/fd') as $fd) {
        $link = @readlink("/proc/self/fd/$fd");
        if ($link !== false && str_starts_with($link, 'socket:')) {
            $sockets[$fd] = $link;
        }
    }
    return $sockets;
}
if (isset($_GET['syslog'])) {
    $before = sockets();
    syslog(LOG_DEBUG, 'zphp syslog test');
    echo json_encode(array_diff_assoc(sockets(), $before));
} else {
    echo json_encode(sockets());
}
PHP;

if (PHP_OS_FAMILY !== 'Linux' || !is_dir('/proc/self/fd') || !@stream_socket_client('udg:///dev/log')) {
    echo "int(1)\narray(0) {\n}\n";
    exit;
}

$dir = sys_get_temp_dir() . '/zphp_syslog_' . getmypid();
@mkdir($dir);
file_put_contents("$dir/index.php", $router);
$probe = stream_socket_server('tcp://127.0.0.1:0');
$addr = stream_socket_get_name($probe, false);
fclose($probe);
$proc = proc_open([PHP_BINARY, '-n', '-S', $addr, '-t', $dir, "$dir/index.php"], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
for ($i = 0; $i < 100; $i++) {
    if ($c = @fsockopen('127.0.0.1', (int) substr($addr, strrpos($addr, ':') + 1))) {
        fclose($c);
        break;
    }
    usleep(50000);
}

$opened = json_decode(file_get_contents("http://$addr/?syslog"), true);
var_dump(count($opened));
$next = json_decode(file_get_contents("http://$addr/"), true);
var_dump(array_intersect_assoc($opened, $next));

proc_terminate($proc);
proc_close($proc);
unlink("$dir/index.php");
rmdir($dir);
