<?php
// covers: php://memory + php://temp, data:// wrapper, compress.zlib://,
//   gzcompress/gzuncompress, stream filters, stream_get_contents,
//   file_get_contents over wrappers

echo "=== php://memory round-trip ===\n";
$f = fopen('php://memory', 'r+');
fwrite($f, "hello memory stream\n");
fwrite($f, "second line\n");
rewind($f);
echo stream_get_contents($f);
fclose($f);

echo "\n=== php://temp round-trip ===\n";
$f = fopen('php://temp', 'r+');
fwrite($f, "temp content\n");
rewind($f);
echo stream_get_contents($f);
fclose($f);

echo "\n=== data:// wrapper ===\n";
$plain = "data:text/plain,hello%20there";
echo "decoded: " . file_get_contents($plain) . "\n";

$b64 = "data:text/plain;base64," . base64_encode("encoded payload");
echo "base64: " . file_get_contents($b64) . "\n";

echo "\n=== gzcompress/uncompress round-trip ===\n";
$payload = str_repeat("abcDEF123 ", 100);
$compressed = gzcompress($payload, 6);
echo "original: " . strlen($payload) . " bytes\n";
echo "compressed: " . strlen($compressed) . " bytes\n";
echo "ratio: " . round(strlen($compressed) / strlen($payload), 3) . "\n";
$decompressed = gzuncompress($compressed);
echo "round-trip ok: " . ($decompressed === $payload ? "yes" : "no") . "\n";

echo "\n=== gzencode (gzip format) ===\n";
$gz = gzencode("plaintext content");
echo "starts with gzip magic: " . (substr($gz, 0, 2) === "\x1f\x8b" ? "yes" : "no") . "\n";
echo "decoded: " . gzdecode($gz) . "\n";

echo "\n=== compress.zlib:// wrapper round-trip ===\n";
$tmp = tempnam(sys_get_temp_dir(), 'gz') . '.gz';
file_put_contents('compress.zlib://' . $tmp, "wrapper writes the gzip");
echo "file size > 0: " . (filesize($tmp) > 0 ? "yes" : "no") . "\n";
$first_bytes = bin2hex(substr(file_get_contents($tmp), 0, 2));
echo "gzip magic: $first_bytes\n";
echo "decoded via wrapper: " . file_get_contents('compress.zlib://' . $tmp) . "\n";
unlink($tmp);

echo "\n=== chunked reads via fread ===\n";
$f = fopen('php://memory', 'r+');
fwrite($f, str_repeat("x", 1000));
rewind($f);
$total = 0;
while (!feof($f)) {
    $chunk = fread($f, 128);
    if ($chunk === '' || $chunk === false) break;
    $total += strlen($chunk);
}
echo "total read: $total\n";
fclose($f);

echo "\n=== fseek + ftell ===\n";
$f = fopen('php://memory', 'r+');
fwrite($f, "0123456789ABCDEFGHIJ");
fseek($f, 5);
echo "tell at 5: " . ftell($f) . "\n";
echo "read 5 from pos: " . fread($f, 5) . "\n";
echo "tell after read: " . ftell($f) . "\n";
fseek($f, 0, SEEK_END);
echo "tell at end: " . ftell($f) . "\n";
fclose($f);

echo "\n=== file_get_contents with offset/length ===\n";
$tmp = tempnam(sys_get_temp_dir(), 'fgc');
file_put_contents($tmp, "the quick brown fox jumps over the lazy dog");
$slice = file_get_contents($tmp, false, null, 4, 5);
echo "[4..9): $slice\n";
unlink($tmp);

echo "\n=== array via php://temp + serialize ===\n";
$data = ['nums' => [1,2,3], 'name' => 'Alice', 'nested' => ['ok' => true]];
$f = fopen('php://temp', 'r+');
fwrite($f, serialize($data));
rewind($f);
$loaded = unserialize(stream_get_contents($f));
fclose($f);
echo "round-trip ok: " . ($loaded == $data ? "yes" : "no") . "\n";
echo "nested.ok: " . var_export($loaded['nested']['ok'], true) . "\n";

echo "\ndone\n";
