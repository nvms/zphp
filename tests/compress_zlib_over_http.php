<?php
// compress.zlib:// opens its inner url through that url's wrapper (here
// http://, from a local php -S server) and decompresses what it reads; the
// context's notifier sees the http stream's events once
$dir = sys_get_temp_dir() . '/zphp-gzhttp-' . getmypid();
@mkdir($dir);
file_put_contents("$dir/index.php", '<?php
$data = gzencode($_GET["text"] ?? "Hello World!\n");
if (isset($_GET["raw"])) $data = $_GET["text"];
header("Content-Type: application/gzip");
header("Content-Length: " . strlen($data));
echo $data;
');
$port = 0;
for ($try = 0; $try < 20 && !$port; $try++) {
    $candidate = 20000 + (getmypid() + $try * 7) % 20000;
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

$names = [
    STREAM_NOTIFY_CONNECT => "CONNECT",
    STREAM_NOTIFY_MIME_TYPE_IS => "MIME_TYPE_IS",
    STREAM_NOTIFY_FILE_SIZE_IS => "FILE_SIZE_IS",
    STREAM_NOTIFY_PROGRESS => "PROGRESS",
    STREAM_NOTIFY_COMPLETED => "COMPLETED",
];
$events = [];
$context = stream_context_create();
stream_context_set_params($context, ["notification" => function ($code, $severity, $message, $message_code, $transferred, $max) use (&$events, $names) {
    $name = $names[$code] ?? $code;
    $event = $name . " " . ($code === STREAM_NOTIFY_FILE_SIZE_IS ? $max : $transferred);
    if ($name === "PROGRESS" && str_starts_with(end($events) ?: "", "PROGRESS ")) array_pop($events);
    $events[] = $event;
}]);

$fp = fopen("compress.zlib://http://127.0.0.1:$port/", "r", false, $context);
var_dump(stream_get_contents($fp));
fclose($fp);
echo implode("\n", $events), "\n";

var_dump(file_get_contents("compress.zlib://http://127.0.0.1:$port/?text=" . urlencode(str_repeat("long line\n", 50))) === str_repeat("long line\n", 50));
var_dump(gzfile("compress.zlib://http://127.0.0.1:$port/?text=a%0Ab%0A"));
$gz = gzopen("compress.zlib://http://127.0.0.1:$port/?text=gzopen", "r");
var_dump(gzread($gz, 100));
gzclose($gz);

proc_terminate($proc);
proc_close($proc);
unlink("$dir/index.php");
rmdir($dir);
