<?php

// password_get_info on bcrypt hash
$hash = password_hash('secret', PASSWORD_BCRYPT, ['cost' => 8]);
$info = password_get_info($hash);
echo $info['algoName'] . "\n";
echo $info['options']['cost'] . "\n";

// password_get_info on invalid input
$info2 = password_get_info('not a hash');
echo $info2['algoName'] . "\n";

// password_algos returns at least bcrypt
$algos = password_algos();
echo (count($algos) >= 1 ? "ok" : "fail") . "\n";

// password_needs_rehash with target cost
$h = password_hash('test', PASSWORD_BCRYPT, ['cost' => 8]);
echo password_needs_rehash($h, PASSWORD_BCRYPT, ['cost' => 10]) ? "yes" : "no";
echo "\n";
echo password_needs_rehash($h, PASSWORD_BCRYPT, ['cost' => 8]) ? "yes" : "no";
echo "\n";

// openssl_random_pseudo_bytes
$b = openssl_random_pseudo_bytes(16);
echo strlen($b) . "\n";

// roundtrip encrypt/decrypt
$key = openssl_random_pseudo_bytes(32);
$iv = openssl_random_pseudo_bytes(16);
$plain = 'hello world';
$enc = openssl_encrypt($plain, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
$dec = openssl_decrypt($enc, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
echo ($dec === $plain ? "match" : "fail") . "\n";
