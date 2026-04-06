<?php

// test constants exist with correct values
echo "CURLOPT_URL: " . CURLOPT_URL . "\n";
echo "CURLOPT_RETURNTRANSFER: " . CURLOPT_RETURNTRANSFER . "\n";
echo "CURLOPT_POST: " . CURLOPT_POST . "\n";
echo "CURLOPT_FOLLOWLOCATION: " . CURLOPT_FOLLOWLOCATION . "\n";
echo "CURLOPT_TIMEOUT: " . CURLOPT_TIMEOUT . "\n";
echo "CURLOPT_HTTPHEADER: " . CURLOPT_HTTPHEADER . "\n";
echo "CURLOPT_SSL_VERIFYPEER: " . CURLOPT_SSL_VERIFYPEER . "\n";
echo "CURLOPT_CUSTOMREQUEST: " . CURLOPT_CUSTOMREQUEST . "\n";
echo "CURLOPT_USERAGENT: " . CURLOPT_USERAGENT . "\n";
echo "CURLOPT_POSTFIELDS: " . CURLOPT_POSTFIELDS . "\n";
echo "CURLE_OK: " . CURLE_OK . "\n";

// test curl_init
$ch = curl_init();
echo "init: " . ($ch instanceof CurlHandle ? "CurlHandle" : gettype($ch)) . "\n";

// test curl_error/curl_errno on fresh handle
echo "error: '" . curl_error($ch) . "'\n";
echo "errno: " . curl_errno($ch) . "\n";

// test curl_setopt
echo "setopt url: " . (curl_setopt($ch, CURLOPT_URL, "http://example.com") ? "true" : "false") . "\n";
echo "setopt rt: " . (curl_setopt($ch, CURLOPT_RETURNTRANSFER, true) ? "true" : "false") . "\n";
echo "setopt timeout: " . (curl_setopt($ch, CURLOPT_TIMEOUT, 5) ? "true" : "false") . "\n";
echo "setopt ua: " . (curl_setopt($ch, CURLOPT_USERAGENT, "TestAgent/1.0") ? "true" : "false") . "\n";
echo "setopt follow: " . (curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true) ? "true" : "false") . "\n";
echo "setopt maxredir: " . (curl_setopt($ch, CURLOPT_MAXREDIRS, 3) ? "true" : "false") . "\n";
echo "setopt post: " . (curl_setopt($ch, CURLOPT_POST, true) ? "true" : "false") . "\n";
echo "setopt postfields: " . (curl_setopt($ch, CURLOPT_POSTFIELDS, "key=value") ? "true" : "false") . "\n";
echo "setopt custom: " . (curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "DELETE") ? "true" : "false") . "\n";
echo "setopt header array: " . (curl_setopt($ch, CURLOPT_HTTPHEADER, ["Content-Type: application/json", "X-Custom: test"]) ? "true" : "false") . "\n";

// test curl_getinfo with specific option
$info = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
echo "effective url: " . $info . "\n";

// test curl_getinfo all
$all = curl_getinfo($ch);
echo "all info type: " . gettype($all) . "\n";
echo "all has url: " . (isset($all['url']) ? "true" : "false") . "\n";
echo "all has http_code: " . (isset($all['http_code']) ? "true" : "false") . "\n";
echo "all has total_time: " . (isset($all['total_time']) ? "true" : "false") . "\n";

// test curl_setopt_array
$ch2 = curl_init();
$result = curl_setopt_array($ch2, [
    CURLOPT_URL => "http://example.com/test",
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 10,
]);
echo "setopt_array: " . ($result ? "true" : "false") . "\n";
$url = curl_getinfo($ch2, CURLINFO_EFFECTIVE_URL);
echo "setopt_array url: " . $url . "\n";

// test curl_init with url
$ch3 = curl_init("http://example.com/init-url");
$url = curl_getinfo($ch3, CURLINFO_EFFECTIVE_URL);
echo "init url: " . $url . "\n";

// test curl_reset
curl_reset($ch3);
echo "after reset errno: " . curl_errno($ch3) . "\n";
echo "after reset error: '" . curl_error($ch3) . "'\n";

// test curl_version
$ver = curl_version();
echo "version type: " . gettype($ver) . "\n";
echo "version has version: " . (isset($ver['version']) ? "true" : "false") . "\n";
echo "version has ssl: " . (isset($ver['ssl_version']) ? "true" : "false") . "\n";

echo "done\n";
