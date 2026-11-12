<?php
// the http:// wrapper against a local server: the request it sends,
// $http_response_header and the wrapper data, redirects, chunked bodies,
// errors and the context options that shape the request

$responses = [
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Folded: one\r\n  two\r\n\r\nhello body",
    "HTTP/1.1 302 Found\r\nLocation: /next?q=1\r\n\r\n",
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nchunk\r\n6\r\ned bod\r\n1\r\ny\r\n0\r\n\r\n",
    "HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\n\r\ngone",
    "HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\n\r\ngone",
    "HTTP/1.1 200 OK\r\n\r\nposted",
    "HTTP/1.0 200 OK\r\nBad Header\r\n\r\nx",
];

$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
$addr = stream_socket_get_name($server, false);
$log = tempnam(sys_get_temp_dir(), 'zh');
$pid = pcntl_fork();
if ($pid === 0) {
    $out = fopen($log, 'w');
    foreach ($responses as $response) {
        $conn = stream_socket_accept($server, 10);
        if (!$conn) break;
        $len = 0;
        while (($line = fgets($conn)) !== false) {
            fwrite($out, $line);
            if (preg_match('/^Content-Length: (\d+)/i', $line, $m)) $len = (int) $m[1];
            if ($line === "\r\n") break;
        }
        if ($len > 0) fwrite($out, fread($conn, $len) . "\n");
        fwrite($conn, $response);
        fclose($conn);
    }
    exit(0);
}
fclose($server);

$url = "http://$addr";
$fp = fopen("$url/first", 'r');
var_dump(stream_get_contents($fp));
$meta = stream_get_meta_data($fp);
var_dump($meta['wrapper_type'], $meta['wrapper_data']);
var_dump($http_response_header === $meta['wrapper_data']);
fclose($fp);

var_dump(file_get_contents("$url/redirect"));
var_dump($http_response_header);
var_dump(http_get_last_response_headers() === $http_response_header);

var_dump(@file_get_contents("$url/missing"));
echo preg_replace('/:\d+/', ':PORT', error_get_last()['message']), "\n";
$ctx = stream_context_create(['http' => ['ignore_errors' => true]]);
var_dump(file_get_contents("$url/missing", false, $ctx));

$ctx = stream_context_create(['http' => [
    'method' => 'POST',
    'header' => "Content-Type: text/plain\r\nX-Custom: yes",
    'content' => 'payload',
    'user_agent' => 'zphp-test',
]]);
var_dump(file_get_contents("$url/post", false, $ctx));
var_dump(@file_get_contents("$url/bad"));
var_dump(@fopen("$url/x", 'w'));

pcntl_waitpid($pid, $status);
echo preg_replace('/:\d+/', ':PORT', file_get_contents($log));
unlink($log);
