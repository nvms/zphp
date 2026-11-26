<?php
// the http wrapper cuts a From or User-Agent value at its first newline and
// warns, so a setting can't inject headers into the request

$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
$addr = stream_socket_get_name($server, false);
$log = tempnam(sys_get_temp_dir(), 'zh');
$pid = pcntl_fork();
if ($pid === 0) {
    $out = fopen($log, 'w');
    for ($i = 0; $i < 4; $i++) {
        $conn = stream_socket_accept($server, 10);
        if (!$conn) break;
        while (($line = fgets($conn)) !== false) {
            if (preg_match('/^(From|User-Agent|Injected)/', $line)) fwrite($out, $line);
            if ($line === "\r\n") break;
        }
        fwrite($out, "--\n");
        fwrite($conn, "HTTP/1.0 200 OK\r\n\r\nok");
        fclose($conn);
    }
    exit(0);
}
fclose($server);
set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    return true;
});

ini_set('from', "me@example.com\r\nInjected-From: evil");
ini_set('user_agent', 'clean');
var_dump(file_get_contents("http://$addr/"));
ini_restore('from');
ini_set('user_agent', "agent\nInjected-UA: evil");
var_dump(file_get_contents("http://$addr/"));
$ctx = stream_context_create(['http' => ['user_agent' => "ctx\rInjected-Ctx: evil"]]);
var_dump(file_get_contents("http://$addr/", false, $ctx));
ini_set('user_agent', "\nonly");
var_dump(file_get_contents("http://$addr/"));

pcntl_waitpid($pid, $status);
echo file_get_contents($log);
unlink($log);
