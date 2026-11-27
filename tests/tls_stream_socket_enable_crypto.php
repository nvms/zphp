<?php
// stream_socket_enable_crypto() on both ends of a loopback connection in
// one process: non-blocking handshakes stepped in turn, the ssl context
// options, and php's warnings for each way a handshake fails
$dir = __DIR__ . '/fixtures/tls';

function pair(array $server_ssl, array $client_ssl, int $client_method = STREAM_CRYPTO_METHOD_TLS_CLIENT, int $server_method = STREAM_CRYPTO_METHOD_TLS_SERVER): array
{
    $server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, stream_context_create(['ssl' => $server_ssl]));
    $name = stream_socket_get_name($server, false);
    $client = stream_socket_client("tcp://$name", $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => $client_ssl]));
    $conn = stream_socket_accept($server, 5);
    stream_set_blocking($client, false);
    stream_set_blocking($conn, false);
    $a = $b = 0;
    $stalled = 0;
    for ($i = 0; $i < 2000; $i++) {
        if ($a === 0) $a = stream_socket_enable_crypto($client, true, $client_method);
        if ($b === 0) $b = stream_socket_enable_crypto($conn, true, $server_method);
        if ($a !== 0 && $b !== 0) break;
        // one side gave up: the other can wait no longer
        if (($a === false || $b === false) && ++$stalled > 50) break;
        usleep(1000);
    }
    echo 'client: ', var_export($a, true), ', server: ', var_export($b, true), "\n";
    return [$client, $conn, $server];
}

echo "-- a verified handshake\n";
[$client, $conn] = pair(['local_cert' => "$dir/server.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']);
$meta = stream_get_meta_data($client);
var_dump(array_keys($meta), $meta['crypto']['protocol'], array_keys($meta['crypto']), $meta['stream_type']);
var_dump(stream_socket_get_crypto_status($client));
fwrite($client, "ping");
stream_set_blocking($conn, true);
var_dump(fread($conn, 4));
fwrite($conn, "pong");
stream_set_blocking($client, true);
var_dump(fread($client, 4));
// a second enable on a live session does nothing
var_dump(stream_socket_enable_crypto($client, true, STREAM_CRYPTO_METHOD_TLS_CLIENT));
// turning crypto off reports false, and the meta data no longer has it
var_dump(stream_socket_enable_crypto($client, false));
var_dump(isset(stream_get_meta_data($client)['crypto']));

echo "-- the context's crypto_method\n";
$server = stream_socket_server('tcp://127.0.0.1:0', $errno, $errstr, STREAM_SERVER_BIND | STREAM_SERVER_LISTEN, stream_context_create(['ssl' => ['local_cert' => "$dir/server.pem", 'crypto_method' => STREAM_CRYPTO_METHOD_TLSv1_2_SERVER]]));
$client = stream_socket_client('tcp://' . stream_socket_get_name($server, false), $errno, $errstr, 5, STREAM_CLIENT_CONNECT, stream_context_create(['ssl' => ['verify_peer' => false, 'crypto_method' => STREAM_CRYPTO_METHOD_TLS_CLIENT]]));
$conn = stream_socket_accept($server, 5);
stream_set_blocking($client, false);
stream_set_blocking($conn, false);
$a = $b = 0;
for ($i = 0; $i < 2000 && ($a === 0 || $b === 0); $i++) {
    if ($a === 0) $a = stream_socket_enable_crypto($client, true);
    if ($b === 0) $b = stream_socket_enable_crypto($conn, true);
    usleep(1000);
}
var_dump($a, $b, stream_get_meta_data($client)['crypto']['protocol']);

echo "-- a server without a certificate\n";
pair([], ['verify_peer' => false]);

echo "-- a self-signed certificate\n";
pair(['local_cert' => "$dir/self-signed.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']);
pair(['local_cert' => "$dir/self-signed.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost', 'allow_self_signed' => true]);

echo "-- peer names\n";
pair(['local_cert' => "$dir/server.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'example.com']);
pair(['local_cert' => "$dir/server.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'example.com', 'verify_peer_name' => false]);
pair(['local_cert' => "$dir/cn-only.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'cn.zphp.test']);
pair(['local_cert' => "$dir/cn-only.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'other.zphp.test']);
// the address the client connected to is the name it checks
pair(['local_cert' => "$dir/server.pem"], ['cafile' => "$dir/ca.pem"]);

echo "-- local certificates\n";
pair(['local_cert' => "$dir/missing.pem"], ['verify_peer' => false]);
pair(['local_cert' => "$dir/server-cert.pem", 'local_pk' => "$dir/server-key-encrypted.pem", 'passphrase' => 'secret'], ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']);
pair(['local_cert' => "$dir/server-cert.pem", 'local_pk' => "$dir/server-key-encrypted.pem", 'passphrase' => 'wrong'], ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost']);

echo "-- ciphers and security levels\n";
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'ciphers' => 'NO-SUCH-CIPHER']);
pair(['local_cert' => "$dir/server.pem", 'security_level' => 1], ['verify_peer' => false, 'security_level' => 0]);

echo "-- fingerprints\n";
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => '07ff682d97edac7d4f762d0866952b1493d7d5fa']);
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => ['sha256' => '6E1D504434663984E776EABABFEF3F290471257DEE877554BC3C3C7A16DFCBC5']]);
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => ['nope' => 'abc']]);
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => str_repeat('0', 40)]);
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => 'abc']);
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => []]);
pair(['local_cert' => "$dir/server.pem"], ['verify_peer' => false, 'peer_fingerprint' => 5]);

echo "-- captured certificates\n";
[$client] = pair(['local_cert' => "$dir/server.pem"], ['cafile' => "$dir/ca.pem", 'peer_name' => 'localhost', 'capture_peer_cert' => true, 'capture_peer_cert_chain' => true]);
$options = stream_context_get_options($client)['ssl'];
var_dump(get_class($options['peer_certificate']), count($options['peer_certificate_chain']), get_class($options['peer_certificate_chain'][0]));

echo "-- streams without crypto\n";
$file = fopen(__FILE__, 'r');
var_dump(stream_socket_enable_crypto($file, true, STREAM_CRYPTO_METHOD_TLS_CLIENT));
var_dump(stream_socket_enable_crypto($file, false));
var_dump(stream_socket_get_crypto_status($file));
try {
    stream_socket_enable_crypto($client, true);
} catch (ValueError $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
if (DIRECTORY_SEPARATOR === '/') {
    [$left] = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
    var_dump(stream_socket_enable_crypto($left, true, STREAM_CRYPTO_METHOD_TLS_CLIENT));
}
print_r(stream_get_transports());
var_dump(STREAM_CRYPTO_METHOD_TLS_CLIENT, STREAM_CRYPTO_METHOD_ANY_SERVER, STREAM_CRYPTO_PROTO_TLSv1_3, STREAM_CRYPTO_STATUS_WANT_WRITE);
