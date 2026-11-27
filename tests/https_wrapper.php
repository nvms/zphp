<?php
// https:// through the http wrapper over a TLS socket: the ssl context
// options, notifications, redirects, and a proxy's CONNECT tunnel, against
// servers in a forked child
$dir = __DIR__ . '/fixtures/tls';
set_error_handler(function (int $level, string $message) {
    echo "warning: ", preg_replace(['/:\d+\b/', '/ in \S+ on line \d+/'], [':PORT', ''], $message), "\n";
    return true;
});

function serve(callable $handler, int $conns = 1): array
{
    $server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr);
    [, $port] = explode(':', stream_socket_get_name($server, false));
    $pid = pcntl_fork();
    if ($pid === 0) {
        set_error_handler(fn () => true);
        for ($i = 0; $i < $conns; $i++) {
            $conn = stream_socket_accept($server, 10);
            if ($conn) {
                $handler($conn);
                fclose($conn);
            }
        }
        exit(0);
    }
    fclose($server);
    return [$port, $pid];
}

function head($conn): string
{
    $head = '';
    while (!str_contains($head, "\r\n\r\n")) {
        $chunk = fread($conn, 1024);
        if ($chunk === '' || $chunk === false) break;
        $head .= $chunk;
    }
    return $head;
}

function ports(string $s): string
{
    return preg_replace('/:\d+\b/', ':PORT', $s);
}

// a TLS server that answers with the request it got
$tls = function ($conn) use ($dir) {
    stream_context_set_option($conn, 'ssl', 'local_cert', "$dir/server.pem");
    if (!stream_socket_enable_crypto($conn, true, STREAM_CRYPTO_METHOD_TLS_SERVER)) return;
    $request = head($conn);
    fwrite($conn, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: " . strlen($request) . "\r\nConnection: close\r\n\r\n" . $request);
};

$notify = function ($code, $severity, $message, $message_code, $transferred, $max) {
    echo "notify $code $severity ", var_export($message, true), " $message_code $transferred $max\n";
};

echo "-- file_get_contents\n";
[$port, $pid] = serve($tls);
$context = stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]], ['notification' => $notify]);
echo ports(file_get_contents("https://localhost:$port/path?x=1", false, $context));
var_dump($http_response_header);
pcntl_waitpid($pid, $status);

echo "-- fopen and the stream's meta data\n";
[$port, $pid] = serve($tls);
$stream = fopen("https://localhost:$port/meta", 'r', false, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]]));
$meta = stream_get_meta_data($stream);
var_dump(array_keys($meta), $meta['crypto']['protocol'], $meta['wrapper_type'], $meta['stream_type'], ports($meta['uri']));
var_dump(fgets($stream));
echo ports(stream_get_contents($stream));
var_dump(feof($stream));
fclose($stream);
pcntl_waitpid($pid, $status);

echo "-- get_headers\n";
[$port, $pid] = serve($tls);
var_dump(get_headers("https://localhost:$port/", true, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]])));
pcntl_waitpid($pid, $status);

echo "-- verification failures\n";
[$port, $pid] = serve($tls);
var_dump(file_get_contents("https://127.0.0.1:$port/", false, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem", 'peer_name' => 'nope.test']])));
pcntl_waitpid($pid, $status);
[$port, $pid] = serve($tls);
var_dump(file_get_contents("https://localhost:$port/", false, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem", 'verify_peer_name' => false, 'peer_name' => 'nope.test']])) !== false);
pcntl_waitpid($pid, $status);

echo "-- a redirect from https to http\n";
[$plain_port, $plain_pid] = serve(function ($conn) {
    head($conn);
    fwrite($conn, "HTTP/1.0 200 OK\r\n\r\nplain body");
});
[$port, $pid] = serve(function ($conn) use ($dir, $plain_port) {
    stream_context_set_option($conn, 'ssl', 'local_cert', "$dir/server.pem");
    if (!stream_socket_enable_crypto($conn, true, STREAM_CRYPTO_METHOD_TLS_SERVER)) return;
    head($conn);
    fwrite($conn, "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:$plain_port/next\r\nContent-Length: 0\r\n\r\n");
});
var_dump(file_get_contents("HTTPS://localhost:$port/", false, stream_context_create(['ssl' => ['cafile' => "$dir/ca.pem"]])));
pcntl_waitpid($pid, $status);
pcntl_waitpid($plain_pid, $status);

echo "-- a proxy's CONNECT tunnel\n";
[$port, $pid] = serve(function ($conn) use ($tls) {
    $connect = head($conn);
    fwrite($conn, "HTTP/1.1 200 Connection established\r\n\r\n");
    $tls($conn);
    file_put_contents(sys_get_temp_dir() . '/zphp_https_connect_' . getmypid(), $connect);
});
$context = stream_context_create([
    'http' => ['proxy' => "tcp://127.0.0.1:$port", 'header' => "X-First: 1\r\nProxy-Authorization: Basic Zm9vOmJhcg==\r\nX-Last: 2"],
    'ssl' => ['cafile' => "$dir/ca.pem"],
], ['notification' => $notify]);
echo file_get_contents('https://localhost/through/proxy', false, $context);
pcntl_waitpid($pid, $status);
$file = sys_get_temp_dir() . '/zphp_https_connect_' . $pid;
echo file_get_contents($file);
unlink($file);
// the tunnel's peer name was the context's only while it was set up
var_dump(array_keys(stream_context_get_options($context)['ssl']));

echo "-- a proxy that refuses\n";
[$port, $pid] = serve(function ($conn) {
    head($conn);
    fwrite($conn, "HTTP/1.1 403 Forbidden\r\n\r\n");
});
var_dump(file_get_contents('https://localhost/', false, stream_context_create(['http' => ['proxy' => "tcp://127.0.0.1:$port"], 'ssl' => ['cafile' => "$dir/ca.pem"]])));
pcntl_waitpid($pid, $status);

echo "-- the https wrapper\n";
var_dump(in_array('https', stream_get_wrappers()));
