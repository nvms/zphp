<?php
// an http request with content and no Content-Type header sends
// application/x-www-form-urlencoded; the wrapper's notice about it is
// dropped, as php's opener runs without REPORT_ERRORS
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
$addr = stream_socket_get_name($server, false);
$client = sys_get_temp_dir() . '/zphp_http_post_client_' . getmypid() . '.php';
file_put_contents($client, '<?php
$ctx = stream_context_create(["http" => ["content" => "payload", "user_agent" => "Agent"]]);
var_dump(file_get_contents("http://' . $addr . '/", false, $ctx));
');
$proc = proc_open([PHP_BINARY, '-n', '-d', 'display_errors=1', '-d', 'error_reporting=-1', $client], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
$conn = stream_socket_accept($server, 30);
$request = '';
while (!str_contains($request, "\r\n\r\n") || !str_ends_with($request, 'payload')) {
    $chunk = fread($conn, 8192);
    if ($chunk === '' || $chunk === false) break;
    $request .= $chunk;
}
fwrite($conn, "HTTP/1.0 200 Ok\r\nContent-Length: 2\r\n\r\nok");
fclose($conn);
echo stream_get_contents($pipes[1]);
echo stream_get_contents($pipes[2]);
proc_close($proc);
unlink($client);
foreach (['GET / HTTP/1.1', 'Content-Length: 7', 'Content-Type: application/x-www-form-urlencoded', 'User-Agent: Agent'] as $line) {
    var_dump(str_contains($request, $line . "\r\n"));
}
