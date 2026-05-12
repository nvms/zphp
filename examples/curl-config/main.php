<?php
// covers: curl handle lifecycle, curl_setopt + curl_setopt_array,
//   constants, curl_version, curl_strerror, error/errno on bad URLs.
//   no live network calls so the example is hermetic.

echo "=== handle lifecycle ===\n";
$ch = curl_init();
echo "is handle: " . ($ch instanceof CurlHandle ? "yes" : "no") . "\n";
$reset_ok = curl_reset($ch);
echo "reset: " . var_export($reset_ok, true) . "\n";
unset($ch);
echo "closed\n";

echo "\n=== init with URL arg ===\n";
$ch = curl_init('https://example.test/');
echo "instanceof: " . ($ch instanceof CurlHandle ? "yes" : "no") . "\n";
echo "errno before exec: " . curl_errno($ch) . "\n";
echo "error before exec: '" . curl_error($ch) . "'\n";
unset($ch);

echo "\n=== bulk setopt ===\n";
$ch = curl_init();
$options = [
    CURLOPT_URL => 'https://api.example.test/v1/things',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 10,
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS => 3,
    CURLOPT_USERAGENT => 'zphp/0.1',
    CURLOPT_HTTPHEADER => ['Accept: application/json', 'X-Trace: 1'],
    CURLOPT_CUSTOMREQUEST => 'POST',
    CURLOPT_POSTFIELDS => json_encode(['k' => 'v']),
];
$ok = curl_setopt_array($ch, $options);
echo "setopt_array: " . var_export($ok, true) . "\n";
unset($ch);

echo "\n=== unreachable port surfaces an error ===\n";
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'http://127.0.0.1:1');  // nothing listening
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT_MS, 200);
$res = curl_exec($ch);
$err = curl_errno($ch);
echo "result is false: " . ($res === false ? "yes" : "no") . "\n";
echo "errno > 0: " . ($err > 0 ? "yes" : "no") . "\n";
unset($ch);

echo "\n=== curl_strerror string coverage ===\n";
// CURLE_OK=0, CURLE_COULDNT_RESOLVE_HOST=6, CURLE_OPERATION_TIMEDOUT=28
foreach ([0, 6, 28] as $code) {
    $s = curl_strerror($code);
    echo sprintf("  code %d: %s\n", $code, is_string($s) && strlen($s) > 0 ? "string" : "missing");
}

echo "\n=== curl_version reports the library ===\n";
$v = curl_version();
echo "keys: " . implode(',', array_keys($v)) . "\n";
echo "version is string: " . (is_string($v['version'] ?? null) ? "yes" : "no") . "\n";

echo "\n=== option constants are stable integers ===\n";
$consts = [
    'CURLOPT_URL' => CURLOPT_URL,
    'CURLOPT_POST' => CURLOPT_POST,
    'CURLOPT_RETURNTRANSFER' => CURLOPT_RETURNTRANSFER,
    'CURLOPT_TIMEOUT' => CURLOPT_TIMEOUT,
    'CURLOPT_HTTPHEADER' => CURLOPT_HTTPHEADER,
    'CURLOPT_FOLLOWLOCATION' => CURLOPT_FOLLOWLOCATION,
    'CURLOPT_USERAGENT' => CURLOPT_USERAGENT,
    'CURLOPT_POSTFIELDS' => CURLOPT_POSTFIELDS,
];
foreach ($consts as $k => $v) {
    echo sprintf("  %-24s = %d\n", $k, $v);
}

echo "\n=== getinfo before exec returns defaults ===\n";
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://example.test/');
$info = curl_getinfo($ch);
echo "is array: " . (is_array($info) ? "yes" : "no") . "\n";
echo "http_code key present: " . (array_key_exists('http_code', $info) ? "yes" : "no") . "\n";
echo "url key present: " . (array_key_exists('url', $info) ? "yes" : "no") . "\n";
unset($ch);
