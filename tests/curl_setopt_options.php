<?php
// curl_setopt's option groups (long, string, nullable string, list, off_t),
// the write and header callbacks, and the constants php defines

foreach (['CURLOPT_HTTP_VERSION', 'CURL_HTTP_VERSION_1_1', 'CURLOPT_PROTOCOLS', 'CURLPROTO_HTTP', 'CURLOPT_REDIR_PROTOCOLS',
    'CURLOPT_BUFFERSIZE', 'CURLOPT_HEADERFUNCTION', 'CURLOPT_WRITEFUNCTION', 'CURLOPT_ACCEPT_ENCODING', 'CURLOPT_ENCODING',
    'CURLAUTH_ANY', 'CURLOPT_SAFE_UPLOAD', 'CURLOPT_RETURNTRANSFER', 'CURLOPT_MAXFILESIZE_LARGE', 'CURLOPT_RESOLVE'] as $name) {
    echo $name, ' ', defined($name) ? 'defined' : 'missing', "\n";
}
var_dump(CURLOPT_ENCODING === CURLOPT_ACCEPT_ENCODING, CURLOPT_SAFE_UPLOAD, CURLOPT_RETURNTRANSFER);
var_dump(defined('CURLSHE_OK'));

$ch = curl_init();
var_dump(curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1));
var_dump(curl_setopt($ch, CURLOPT_PROTOCOLS, CURLPROTO_HTTP | CURLPROTO_HTTPS | CURLPROTO_FILE));
var_dump(curl_setopt($ch, CURLOPT_BUFFERSIZE, "16384"));
var_dump(curl_setopt($ch, CURLOPT_ACCEPT_ENCODING, null));
var_dump(curl_setopt($ch, CURLOPT_MAXFILESIZE_LARGE, 1 << 40));
var_dump(curl_setopt($ch, CURLOPT_RESOLVE, ['example.test:80:127.0.0.1']));
var_dump(curl_setopt($ch, 19914, true));
var_dump(curl_setopt($ch, CURLOPT_SAFE_UPLOAD, true));
var_dump(curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 1));
foreach ([
    fn() => curl_setopt($ch, CURLOPT_HTTPHEADER, 'X-A: b'),
    fn() => curl_setopt($ch, CURLOPT_RESOLVE, 'x'),
    fn() => curl_setopt($ch, CURLOPT_USERAGENT, "a\0b"),
    fn() => curl_setopt($ch, CURLOPT_SAFE_UPLOAD, false),
    fn() => curl_setopt($ch, 99999, 1),
] as $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

$file = tempnam(sys_get_temp_dir(), 'curl');
file_put_contents($file, str_repeat("line\n", 3));
$url = 'file://' . (DIRECTORY_SEPARATOR === '\\' ? '/' . str_replace('\\', '/', $file) : $file);

// a write function receives the body; RETURNTRANSFER set later takes over
$ch = curl_init($url);
$chunks = [];
curl_setopt($ch, CURLOPT_WRITEFUNCTION, function ($h, $data) use (&$chunks, $ch) {
    $chunks[] = $data;
    var_dump($h === $ch);
    return strlen($data);
});
var_dump(curl_exec($ch));
var_dump(implode('', $chunks));
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
var_dump(curl_exec($ch));
curl_setopt($ch, CURLOPT_WRITEFUNCTION, function ($h, $data) { echo "[", strlen($data), "]\n"; return strlen($data); });
var_dump(curl_exec($ch));
// clearing the function goes back to printing
curl_setopt($ch, CURLOPT_WRITEFUNCTION, null);
var_dump(curl_exec($ch));

// a short count aborts the transfer
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_WRITEFUNCTION, fn($h, $data) => 0);
var_dump(curl_exec($ch), curl_errno($ch) === CURLE_WRITE_ERROR);

// an exception from the callback reaches the caller
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_WRITEFUNCTION, function ($h, $data) { throw new RuntimeException('stop'); });
try {
    curl_exec($ch);
} catch (RuntimeException $e) {
    echo 'caught ', $e->getMessage(), "\n";
}

// no RETURNTRANSFER: the body goes through the output layer
ob_start();
$ch = curl_init($url);
var_dump(curl_exec($ch));
$out = ob_get_clean();
var_dump($out);

// private data
$ch = curl_init();
curl_setopt($ch, CURLOPT_PRIVATE, ['id' => 7]);
var_dump(curl_getinfo($ch, CURLINFO_PRIVATE));
unlink($file);
