<?php
// `-S host:port -t docroot [router]` starts php's built-in web server, which
// announces the port it got; get_headers() reads a response's headers, an
// error status included, and groups repeated headers in associative mode

$root = sys_get_temp_dir() . '/zphp_cli_server_' . getmypid();
@mkdir($root);
file_put_contents("$root/router.php", <<<'PHP'
<?php
header('X-Method: ' . $_SERVER['REQUEST_METHOD']);
header('X-Twice: one');
header('X-Twice: two', false);
if (isset($_GET['missing'])) http_response_code(404);
echo $_SERVER['REQUEST_METHOD'], ' ', $_SERVER['REQUEST_URI'], ' ', file_get_contents('php://input');
PHP);

$log = "$root/server.log";
$proc = proc_open([PHP_BINARY, '-n', '-t', $root, '-S', 'localhost:0', 'router.php'], [0 => ['pipe', 'r'], 1 => ['file', $log, 'w'], 2 => ['file', $log, 'w']], $pipes, $root);
$address = null;
for ($i = 0; $i < 200 && $address === null; $i++) {
    usleep(50000);
    if (preg_match('@Development Server \(http://(\S+?:\d+)\) started@', (string) @file_get_contents($log), $m)) $address = $m[1];
}
if ($address === null) {
    echo "the server did not start\n";
} else {
    for ($i = 0; $i < 100 && !($fp = @fsockopen("tcp://$address")); $i++) usleep(50000);
    if ($fp) fclose($fp);

    echo file_get_contents("http://$address/a/b?x=1"), "\n";
    $post = stream_context_create(['http' => ['method' => 'POST', 'header' => 'Content-Type: text/plain', 'content' => 'body']]);
    echo file_get_contents("http://$address/post", false, $post), "\n";

    $clean = function ($headers) {
        $keep = [];
        foreach ($headers as $k => $v) {
            $line = is_int($k) ? $v : $k;
            if (is_string($line) && preg_match('/^(HTTP\/|X-[MT])/', $line)) $keep[$k] = $v;
        }
        return isset($keep[0]) && !isset($keep['X-Method']) ? array_values($keep) : $keep;
    };
    $head = stream_context_create(['http' => ['method' => 'HEAD']]);
    var_dump($clean(get_headers("http://$address/", false, $head)));
    var_dump($clean(get_headers("http://$address/?missing=1", true)));
}
proc_terminate($proc);
proc_close($proc);
@unlink("$root/router.php");
@unlink($log);
@rmdir($root);

// only url wrappers answer
var_dump(@get_headers(__FILE__), error_get_last()['message']);
var_dump(@get_headers('php://memory'), get_headers('data:,abc', true));
