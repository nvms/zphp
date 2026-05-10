<?php
// openssl_digest
echo openssl_digest("hello", "sha256"), "\n";
echo openssl_digest("hello", "md5"), "\n";
echo openssl_digest("", "sha256"), "\n";

// openssl_digest binary output
echo bin2hex(openssl_digest("hello", "sha256", true)), "\n";

// openssl_random_pseudo_bytes
$b = openssl_random_pseudo_bytes(32);
echo strlen($b), "\n";

$b = openssl_random_pseudo_bytes(32, $strong);
echo strlen($b), " strong=", $strong ? "y" : "n", "\n";

// openssl_encrypt aes-256-cbc
$key = str_repeat("a", 32);
$iv = str_repeat("0", 16);
$plain = "secret message";
$cipher = openssl_encrypt($plain, "aes-256-cbc", $key, 0, $iv);
echo strlen($cipher) > 0 ? "enc-ok " : "enc-fail ";
$decrypted = openssl_decrypt($cipher, "aes-256-cbc", $key, 0, $iv);
echo $decrypted === $plain ? "round-trip-ok" : "round-trip-fail", "\n";

// raw cipher output
$cipher_raw = openssl_encrypt($plain, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo strlen($cipher_raw) > 0 ? "raw-ok " : "raw-fail ";
$decrypted = openssl_decrypt($cipher_raw, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
echo $decrypted === $plain ? "raw-trip-ok" : "raw-trip-fail", "\n";

// aes-128-cbc
$key128 = str_repeat("k", 16);
$iv128 = str_repeat("v", 16);
$cipher = openssl_encrypt("hello world", "aes-128-cbc", $key128, 0, $iv128);
echo openssl_decrypt($cipher, "aes-128-cbc", $key128, 0, $iv128), "\n";

// aes-256-gcm (with tag)
$key = str_repeat("g", 32);
$iv = openssl_random_pseudo_bytes(12);
$tag = "";
$cipher = openssl_encrypt("gcm test", "aes-256-gcm", $key, OPENSSL_RAW_DATA, $iv, $tag);
echo strlen($cipher) > 0 ? "gcm-enc-ok " : "gcm-enc-fail ";
echo strlen($tag) === 16 ? "tag-ok " : "tag-bad-len:" . strlen($tag) . " ";
$d = openssl_decrypt($cipher, "aes-256-gcm", $key, OPENSSL_RAW_DATA, $iv, $tag);
echo $d === "gcm test" ? "gcm-trip-ok\n" : "gcm-trip-fail:$d\n";

// chacha20-poly1305
$key = str_repeat("c", 32);
$iv = openssl_random_pseudo_bytes(12);
$tag = "";
$cipher = openssl_encrypt("chacha test", "chacha20-poly1305", $key, OPENSSL_RAW_DATA, $iv, $tag);
$d = openssl_decrypt($cipher, "chacha20-poly1305", $key, OPENSSL_RAW_DATA, $iv, $tag);
echo $d === "chacha test" ? "cp-ok\n" : "cp-fail:" . ($d === false ? "false" : $d) . "\n";

// openssl_cipher_iv_length
echo openssl_cipher_iv_length("aes-256-cbc"), "\n"; // 16
echo openssl_cipher_iv_length("aes-128-cbc"), "\n"; // 16
echo openssl_cipher_iv_length("aes-256-gcm"), "\n"; // 12

// openssl_get_cipher_methods returns array
$methods = openssl_get_cipher_methods();
echo gettype($methods), " ", in_array("aes-256-cbc", $methods, true) ? "has-aes" : "no-aes", "\n";

// openssl_get_md_methods
$mds = openssl_get_md_methods();
echo gettype($mds), " ", in_array("sha256", array_map("strtolower", $mds)) ? "has-sha256" : "no-sha256", "\n";

// hash_hkdf
$key = "input-key";
$salt = "salt";
$info = "context";
$out = hash_hkdf("sha256", $key, 32, $info, $salt);
echo strlen($out), "\n"; // 32 binary

// hash_hkdf no salt
$out = hash_hkdf("sha256", "key", 32);
echo strlen($out), "\n"; // 32

// hash_hmac
echo hash_hmac("sha256", "msg", "key"), "\n";
echo bin2hex(hash_hmac("sha256", "msg", "key", true)), "\n";

// pbkdf2
$d = hash_pbkdf2("sha256", "password", "salt", 1000, 32);
echo strlen($d), "\n"; // 32 hex

// password_hash + verify
$h = password_hash("secret", PASSWORD_BCRYPT);
var_dump(password_verify("secret", $h));
var_dump(password_verify("wrong", $h));

// random_bytes / random_int
echo strlen(random_bytes(16)), "\n";
$i = random_int(0, 100);
var_dump($i >= 0 && $i <= 100);

// crc32 / md5 / sha1 baselines
echo md5("test"), "\n";
echo sha1("test"), "\n";
echo crc32("test"), "\n";

// openssl_decrypt with bad data returns false
$bad = openssl_decrypt("not-base64-or-cipher", "aes-256-cbc", str_repeat("k", 32), 0, str_repeat("i", 16));
var_dump($bad === false);
