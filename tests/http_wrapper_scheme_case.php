<?php
// the http wrapper takes the scheme in any case: "HTTPS://" and "hTtPs://"
// start TLS (php 8.5.13; earlier they sent the request in plaintext) and
// "HTTP://" is plain http
$serverCode = <<<'PHP'
<?php
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
echo stream_socket_get_name($server, false), "\n";
fclose(STDOUT);
$log = [];
for ($i = 0; $i < 4; $i++) {
    $conn = stream_socket_accept($server, 10);
    if (!$conn) break;
    $first = fread($conn, 1);
    if ($first === "\x16") {
        $log[] = "TLS handshake";
    } else {
        $request = $first;
        while (($line = fgets($conn)) !== false) {
            $request .= $line;
            if ($line === "\r\n") break;
        }
        $log[] = "plaintext: " . strtok($request, "\r\n");
        fwrite($conn, "HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok");
    }
    fclose($conn);
}
file_put_contents($argv[1], implode("\n", $log) . "\n");
PHP;

$script = tempnam(sys_get_temp_dir(), 'zs');
$log = tempnam(sys_get_temp_dir(), 'zl');
file_put_contents($script, $serverCode);
$proc = proc_open([PHP_BINARY, '-n', $script, $log], [1 => ['pipe', 'w']], $pipes);
$addr = trim(fgets($pipes[1]));

$ctx = stream_context_create(['ssl' => ['verify_peer' => false, 'verify_peer_name' => false]]);
var_dump(@file_get_contents("HTTPS://$addr/upper", false, $ctx));
var_dump(@file_get_contents("hTtPs://$addr/mixed", false, $ctx));
var_dump(file_get_contents("HTTP://$addr/plain"));
$fp = fopen("Http://$addr/fopen", 'r');
var_dump(stream_get_contents($fp));
fclose($fp);

proc_close($proc);
echo file_get_contents($log);
unlink($log);
unlink($script);
