<?php
$key = str_repeat("k", 32);
$iv = str_repeat("v", 16);

$plain = "hello world";
$enc = openssl_encrypt($plain, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo strlen($enc) > 0 ? "y" : "n", "\n";
echo strlen($enc) % 16 === 0 ? "y" : "n", "\n";

$dec = openssl_decrypt($enc, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $dec === $plain ? "y" : "n", "\n";

$enc = openssl_encrypt($plain, "aes-256-cbc", $key, 0, $iv);
$dec = openssl_decrypt($enc, "aes-256-cbc", $key, 0, $iv);
echo $dec === $plain ? "y" : "n", "\n";

$enc1 = openssl_encrypt("same", "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
$enc2 = openssl_encrypt("same", "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $enc1 === $enc2 ? "deterministic" : "random", "\n";

$iv2 = str_repeat("x", 16);
$enc3 = openssl_encrypt("same", "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv2);
echo $enc1 !== $enc3 ? "y" : "n", "\n";

$wrong_key = str_repeat("X", 32);
$bad = openssl_decrypt($enc1, "aes-256-cbc", $wrong_key, OPENSSL_RAW_DATA, $iv);
echo $bad === false ? "y" : "n", "\n";

$big = str_repeat("data", 100);
$enc = openssl_encrypt($big, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
$dec = openssl_decrypt($enc, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $dec === $big ? "y" : "n", "\n";
echo strlen($enc), "\n";

$tiny = "x";
$enc = openssl_encrypt($tiny, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
$dec = openssl_decrypt($enc, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $dec, "\n";

$empty = "";
$enc = openssl_encrypt($empty, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
$dec = openssl_decrypt($enc, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $dec === "" ? "y" : "n", "\n";

$key128 = str_repeat("k", 16);
$enc = openssl_encrypt($plain, "aes-128-cbc", $key128, OPENSSL_RAW_DATA, $iv);
$dec = openssl_decrypt($enc, "aes-128-cbc", $key128, OPENSSL_RAW_DATA, $iv);
echo $dec === $plain ? "y" : "n", "\n";

echo strlen(openssl_random_pseudo_bytes(16)), "\n";
echo strlen(openssl_random_pseudo_bytes(32)), "\n";
try { openssl_random_pseudo_bytes(0); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
echo strlen(openssl_random_pseudo_bytes(100)), "\n";

$a = openssl_random_pseudo_bytes(16);
$b = openssl_random_pseudo_bytes(16);
echo $a === $b ? "same" : "diff", "\n";

echo openssl_digest("hello", "sha256"), "\n";
echo openssl_digest("hello", "md5"), "\n";
echo openssl_digest("hello", "sha1"), "\n";
echo openssl_digest("", "sha256"), "\n";
echo openssl_digest("hello", "sha512"), "\n";

echo strlen(openssl_digest("x", "sha256", true)), "\n";
echo bin2hex(openssl_digest("x", "sha256", true)), "\n";

echo strlen(random_bytes(16)), "\n";
echo strlen(random_bytes(32)), "\n";
echo strlen(random_bytes(1)), "\n";

$r1 = random_bytes(16);
$r2 = random_bytes(16);
echo $r1 === $r2 ? "same" : "diff", "\n";

try { random_bytes(0); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { random_bytes(-1); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

$n = random_int(1, 100);
echo $n >= 1 && $n <= 100 ? "y" : "n", "\n";

$n = random_int(0, 0);
echo $n === 0 ? "y" : "n", "\n";

$n = random_int(-100, -50);
echo $n >= -100 && $n <= -50 ? "y" : "n", "\n";

$counts = [];
for ($i = 0; $i < 100; $i++) {
    $v = random_int(1, 5);
    $counts[$v] = ($counts[$v] ?? 0) + 1;
}
echo array_sum($counts) === 100 ? "y" : "n", "\n";
echo count($counts) > 1 ? "y" : "n", "\n";

try { random_int(10, 1); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

echo openssl_digest("abc", "sha256"), "\n";
echo strlen(openssl_digest("any", "md5")), "\n";
echo strlen(openssl_digest("any", "sha256")), "\n";
echo strlen(openssl_digest("any", "sha512")), "\n";

$plain = "Lorem ipsum dolor sit amet";
$enc = openssl_encrypt($plain, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
$dec = openssl_decrypt($enc, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $dec, "\n";
