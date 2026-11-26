<?php
// a relative Location is joined to the request path the way php's http
// wrapper does it: truncated after the last slash, then joined with another

$froms = ['/dir/page', '/a', '', '/x/y/z'];
$tos = ['dir/page', 'a', 'other', '../foo'];
$responses = [];
foreach ($froms as $from) {
    foreach ($tos as $to) {
        $responses[] = "HTTP/1.0 302 Found\r\nLocation: $to\r\n\r\n";
        $responses[] = "HTTP/1.0 200 OK\r\n\r\nok";
    }
}

$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
$addr = stream_socket_get_name($server, false);
$log = tempnam(sys_get_temp_dir(), 'zh');
$pid = pcntl_fork();
if ($pid === 0) {
    $out = fopen($log, 'w');
    foreach ($responses as $response) {
        $conn = stream_socket_accept($server, 10);
        if (!$conn) break;
        while (($line = fgets($conn)) !== false) {
            if (str_starts_with($line, 'GET ')) fwrite($out, $line);
            if ($line === "\r\n") break;
        }
        fwrite($conn, $response);
        fclose($conn);
    }
    exit(0);
}
fclose($server);

foreach ($froms as $from) {
    foreach ($tos as $to) {
        file_get_contents("http://$addr$from");
    }
}
pcntl_waitpid($pid, $status);
$lines = file($log);
unlink($log);
$i = 0;
foreach ($froms as $from) {
    foreach ($tos as $to) {
        echo "'$from' + '$to': ", trim($lines[$i * 2 + 1]), "\n";
        $i++;
    }
}
