<?php
// the built-in web server (-S) without a router routes each request as php's
// does: files are sent, a directory serves its index.php or index.html, a
// script runs with what followed it in PATH_INFO, and anything else is the
// server's 404 page, even with no index.php in the document root
$dir = sys_get_temp_dir() . '/zphp_cli_server_' . getmypid();
@mkdir($dir);
@mkdir("$dir/sub");
@mkdir("$dir/html");
file_put_contents("$dir/a.txt", "hello static\n");
file_put_contents("$dir/html/index.html", "<p>index html</p>\n");
file_put_contents("$dir/s.php", '<?php echo "script ", $_SERVER["SCRIPT_NAME"], " ", $_SERVER["PATH_INFO"] ?? "-", " ", $_SERVER["PHP_SELF"], "\n";');
file_put_contents("$dir/sub/index.php", '<?php echo "sub index ", $_SERVER["SCRIPT_NAME"], "\n";');

$port = 0;
$proc = null;
for ($attempt = 0; $attempt < 5 && !$proc; $attempt++) {
    $port = 21000 + (getmypid() * 7 + $attempt * 131) % 20000;
    $cmd = [PHP_BINARY, '-n', '-S', "127.0.0.1:$port", '-t', $dir];
    $p = proc_open($cmd, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    for ($i = 0; $i < 100; $i++) {
        $s = @fsockopen('127.0.0.1', $port, $errno, $errstr, 0.1);
        if ($s) {
            fclose($s);
            $proc = $p;
            break;
        }
        $status = proc_get_status($p);
        if (!$status['running']) break;
        usleep(50000);
    }
    if (!$proc) proc_terminate($p);
}
if (!$proc) {
    echo "the server did not start\n";
    exit(1);
}

$ctx = stream_context_create(['http' => ['ignore_errors' => true]]);
foreach (['/', '/a.txt', '/s.php', '/s.php/extra/info', '/sub/', '/sub', '/html/', '/missing', '/missing/deeper.php', '/x%3Cy', '/sub/../a.txt'] as $path) {
    $body = file_get_contents("http://127.0.0.1:$port$path", false, $ctx);
    echo $path, " => ", http_get_last_response_headers()[0], "\n", $body, "\n";
}
$delete = stream_context_create(['http' => ['ignore_errors' => true, 'method' => 'DELETE']]);
file_get_contents("http://127.0.0.1:$port/a.txt", false, $delete);
echo "DELETE /a.txt => ", http_get_last_response_headers()[0], "\n";

proc_terminate($proc);
proc_close($proc);
foreach (['a.txt', 'html/index.html', 's.php', 'sub/index.php'] as $f) unlink("$dir/$f");
rmdir("$dir/sub");
rmdir("$dir/html");
rmdir($dir);
