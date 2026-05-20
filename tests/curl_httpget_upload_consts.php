<?php
// regression: CURLOPT_HTTPGET and CURLOPT_UPLOAD must be defined and
// accepted by curl_setopt. previously they were undefined constants, and
// curl_setopt would throw a ValueError ("not a valid cURL option").
var_dump(defined('CURLOPT_HTTPGET'));
var_dump(defined('CURLOPT_UPLOAD'));

$ch = curl_init();
var_dump(curl_setopt($ch, CURLOPT_HTTPGET, true));
var_dump(curl_setopt($ch, CURLOPT_UPLOAD, false));
var_dump(curl_setopt($ch, CURLOPT_UPLOAD, 1));

// also valid inside curl_setopt_array
$ok = curl_setopt_array($ch, [
    CURLOPT_HTTPGET => true,
    CURLOPT_UPLOAD => false,
]);
var_dump($ok);
curl_close($ch);
echo "done\n";
