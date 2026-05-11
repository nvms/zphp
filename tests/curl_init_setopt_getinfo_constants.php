<?php
$ch = curl_init();
echo $ch !== false ? "ok" : "no", "\n";

curl_setopt($ch, CURLOPT_URL, "http://example.com");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
echo curl_getinfo($ch, CURLINFO_EFFECTIVE_URL), "\n";

curl_setopt_array($ch, [
    CURLOPT_URL => "http://test.com",
    CURLOPT_TIMEOUT => 30,
    CURLOPT_USERAGENT => "zphp-test",
]);
echo curl_getinfo($ch, CURLINFO_EFFECTIVE_URL), "\n";
echo curl_error($ch), "|\n";
echo curl_errno($ch), "\n";

$ch2 = curl_init("http://example.com");
echo curl_getinfo($ch2, CURLINFO_EFFECTIVE_URL), "\n";

$ch3 = curl_init();
curl_setopt($ch3, CURLOPT_CUSTOMREQUEST, "POST");
curl_setopt($ch3, CURLOPT_POSTFIELDS, "key=value");
curl_setopt($ch3, CURLOPT_HTTPHEADER, ["X-Header: 1", "Accept: application/json"]);
echo curl_getinfo($ch3, CURLINFO_HTTP_CODE), "\n";

echo function_exists("curl_init") ? "y" : "n", "\n";
echo function_exists("curl_setopt") ? "y" : "n", "\n";
echo function_exists("curl_setopt_array") ? "y" : "n", "\n";
echo function_exists("curl_exec") ? "y" : "n", "\n";
echo function_exists("curl_error") ? "y" : "n", "\n";
echo function_exists("curl_errno") ? "y" : "n", "\n";
echo function_exists("curl_getinfo") ? "y" : "n", "\n";
echo function_exists("curl_reset") ? "y" : "n", "\n";
echo function_exists("curl_version") ? "y" : "n", "\n";

echo defined("CURLOPT_URL") ? "y" : "n", "\n";
echo defined("CURLOPT_RETURNTRANSFER") ? "y" : "n", "\n";
echo defined("CURLOPT_POST") ? "y" : "n", "\n";
echo defined("CURLOPT_POSTFIELDS") ? "y" : "n", "\n";
echo defined("CURLOPT_HEADER") ? "y" : "n", "\n";
echo defined("CURLOPT_FOLLOWLOCATION") ? "y" : "n", "\n";
echo defined("CURLOPT_TIMEOUT") ? "y" : "n", "\n";
echo defined("CURLOPT_USERAGENT") ? "y" : "n", "\n";
echo defined("CURLOPT_HTTPHEADER") ? "y" : "n", "\n";
echo defined("CURLOPT_CUSTOMREQUEST") ? "y" : "n", "\n";
echo defined("CURLOPT_USERPWD") ? "y" : "n", "\n";
echo defined("CURLOPT_SSL_VERIFYPEER") ? "y" : "n", "\n";
echo defined("CURLOPT_SSL_VERIFYHOST") ? "y" : "n", "\n";
echo defined("CURLOPT_PROXY") ? "y" : "n", "\n";
echo defined("CURLOPT_NOBODY") ? "y" : "n", "\n";
echo defined("CURLOPT_COOKIE") ? "y" : "n", "\n";
echo defined("CURLINFO_HTTP_CODE") ? "y" : "n", "\n";
echo defined("CURLINFO_EFFECTIVE_URL") ? "y" : "n", "\n";
echo defined("CURLINFO_TOTAL_TIME") ? "y" : "n", "\n";
echo defined("CURLINFO_CONTENT_TYPE") ? "y" : "n", "\n";

$v = curl_version();
echo isset($v["version"]) ? "y" : "n", "\n";

$ch4 = curl_init();
curl_setopt($ch4, CURLOPT_URL, "http://test1");
curl_reset($ch4);
echo curl_getinfo($ch4, CURLINFO_EFFECTIVE_URL), "|\n";
