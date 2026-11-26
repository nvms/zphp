<?php
// a script's own Content-Length goes out once from php -S, so an http
// client sees it (and its file size notification) a single time
$dir = sys_get_temp_dir() . '/zphp-cl-' . getmypid();
@mkdir($dir);
file_put_contents("$dir/index.php", '<?php
header("Content-Type: text/plain");
header("Content-Length: 5");
echo "hello";
');
$port = 0;
for ($try = 0; $try < 20 && !$port; $try++) {
    $candidate = 20000 + (getmypid() * 3 + $try * 11) % 20000;
    $proc = proc_open([PHP_BINARY, '-S', "127.0.0.1:$candidate", '-t', $dir], [1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $pipes);
    for ($i = 0; $i < 100; $i++) {
        $s = @fsockopen('127.0.0.1', $candidate, $errno, $errstr, 0.1);
        if ($s) {
            fclose($s);
            $port = $candidate;
            break;
        }
        usleep(20000);
    }
    if (!$port) proc_terminate($proc);
}
$sizes = [];
$context = stream_context_create([], ['notification' => function ($code, $severity, $message, $message_code, $transferred, $max) use (&$sizes) {
    if ($code === STREAM_NOTIFY_FILE_SIZE_IS) $sizes[] = $max;
}]);
var_dump(file_get_contents("http://127.0.0.1:$port/", false, $context));
var_dump($sizes);
var_dump(array_values(array_filter(http_get_last_response_headers(), fn($h) => stripos($h, 'content-length:') === 0)));
proc_terminate($proc);
proc_close($proc);
unlink("$dir/index.php");
rmdir($dir);
