<?php
// the ssl://, tls:// and tlsv1.x:// transports: clients that shake hands as
// they connect, servers that shake hands as they accept, against a server
// in a forked child
$dir = __DIR__ . '/fixtures/tls';
// warnings name ephemeral ports
set_error_handler(function (int $level, string $message) {
    echo "warning: ", preg_replace(['/:\d+\b/', '/ in \S+ on line \d+/'], [':PORT', ''], $message), "\n";
    return true;
});

// a forked server answering $conns connections with $handler
function serve(string $transport, array $ssl, callable $handler, int $conns = 1): array
{
    $server = stream_socket_server("$transport://127.0.0.1:0", $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, stream_context_create(['ssl' => $ssl]));
    $name = stream_socket_get_name($server, false);
    $pid = pcntl_fork();
    if ($pid === 0) {
        // the child's warnings would race the parent's output
        set_error_handler(fn () => true);
        for ($i = 0; $i < $conns; $i++) {
            $conn = @stream_socket_accept($server, 10);
            if ($conn) {
                $handler($conn);
                @fclose($conn);
            }
        }
        exit(0);
    }
    fclose($server);
    return [$name, $pid];
}

function finish(int $pid): void
{
    pcntl_waitpid($pid, $status);
}

function meta($stream): array
{
    $meta = stream_get_meta_data($stream);
    unset($meta['crypto']['cipher_name'], $meta['crypto']['cipher_bits'], $meta['crypto']['cipher_version']);
    $meta['uri'] = preg_replace('/:\d+$/', ':PORT', $meta['uri']);
    return $meta;
}

$echo = function ($conn) {
    $line = fgets($conn);
    fwrite($conn, "echo: $line");
};

echo "-- ssl:// client and tls:// server\n";
[$name, $pid] = serve('tls', ['local_cert' => "$dir/server.pem"], $echo);
$client = stream_socket_client("ssl://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]]));
var_dump($errno, $errstr);
fwrite($client, "hello\n");
var_dump(fgets($client));
var_dump(fread($client, 10), feof($client));
var_dump(meta($client));
fclose($client);
finish($pid);

echo "-- each tlsv1.x transport\n";
foreach (['tlsv1.2', 'tlsv1.3'] as $transport) {
    [$name, $pid] = serve('tcp', [], function ($conn) use ($dir) {
        stream_context_set_option($conn, 'ssl', 'local_cert', "$dir/server.pem");
        if (stream_socket_enable_crypto($conn, true, STREAM_CRYPTO_METHOD_TLS_SERVER)) {
            fwrite($conn, stream_get_meta_data($conn)['crypto']['protocol'] . "\n");
        }
    });
    $client = stream_socket_client("$transport://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']]));
    var_dump(fgets($client));
    fclose($client);
    finish($pid);
}

echo "-- a client that fails verification\n";
[$name, $pid] = serve('tls', ['local_cert' => "$dir/self-signed.pem"], function ($conn) {});
var_dump(stream_socket_client("tls://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']])));
var_dump($errno, $errstr);
finish($pid);

echo "-- a server that hangs up\n";
[$name, $pid] = serve('tcp', [], function ($conn) {});
var_dump(stream_socket_client("ssl://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['verify_peer' => false]])));
var_dump($errno, $errstr);
finish($pid);

echo "-- fsockopen\n";
[$name, $pid] = serve('tls', ['local_cert' => "$dir/server.pem"], $echo);
[, $port] = explode(':', $name);
$client = fsockopen('ssl://127.0.0.1', (int) $port, $errno, $errstr, 5);
var_dump($client);
finish($pid);
// fsockopen has no context to verify with but the system's
[$name, $pid] = serve('tls', ['local_cert' => "$dir/server.pem"], $echo);
[, $port] = explode(':', $name);
var_dump(fsockopen('tls://localhost', (int) $port, $errno, $errstr, 5));
finish($pid);

echo "-- an accept whose handshake fails\n";
$server = stream_socket_server('tls://127.0.0.1:0', $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, stream_context_create(['ssl' => ['local_cert' => "$dir/server.pem"]]));
$name = stream_socket_get_name($server, false);
$pid = pcntl_fork();
if ($pid === 0) {
    $plain = stream_socket_client("tcp://$name", $errno, $errstr, 5);
    fwrite($plain, "GET / HTTP/1.0\r\n\r\n");
    fread($plain, 10);
    exit(0);
}
var_dump(stream_socket_accept($server, 5));
finish($pid);

echo "-- a blocking read that times out\n";
[$name, $pid] = serve('tls', ['local_cert' => "$dir/server.pem"], function ($conn) {
    fgets($conn);
});
$client = stream_socket_client("ssl://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]]));
stream_set_timeout($client, 0, 200000);
var_dump(fread($client, 10), stream_get_meta_data($client)['timed_out']);
fwrite($client, "done\n");
fclose($client);
finish($pid);

echo "-- a non-blocking read\n";
[$name, $pid] = serve('tls', ['local_cert' => "$dir/server.pem"], function ($conn) {
    fgets($conn);
    fwrite($conn, "late\n");
    fgets($conn);
});
$client = stream_socket_client("ssl://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]]));
stream_set_blocking($client, false);
var_dump(fread($client, 10));
fwrite($client, "go\n");
// post-handshake records (session tickets) wake a select with no data
$got = '';
for ($i = 0; $i < 20 && !str_contains($got, "\n"); $i++) {
    $read = [$client];
    $write = $except = null;
    if (stream_select($read, $write, $except, 5) > 0) $got .= fread($client, 10);
}
var_dump($got);
fwrite($client, "done\n");
fclose($client);
finish($pid);
