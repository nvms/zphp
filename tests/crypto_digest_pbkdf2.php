<?php
// openssl_encrypt/decrypt round-trip
$key128 = str_repeat("k", 16);
$key256 = str_repeat("K", 32);
$iv = str_repeat("i", 16);

$pt = "secret message";
$ct = openssl_encrypt($pt, "aes-128-cbc", $key128, OPENSSL_RAW_DATA, $iv);
echo strlen($ct) > 0 ? "ct128-ok\n" : "no\n";
$rt = openssl_decrypt($ct, "aes-128-cbc", $key128, OPENSSL_RAW_DATA, $iv);
echo $rt === $pt ? "rt128-ok\n" : "rt-fail\n";

$ct = openssl_encrypt($pt, "aes-256-cbc", $key256, OPENSSL_RAW_DATA, $iv);
echo strlen($ct) > 0 ? "ct256-ok\n" : "no\n";
$rt = openssl_decrypt($ct, "aes-256-cbc", $key256, OPENSSL_RAW_DATA, $iv);
echo $rt === $pt ? "rt256-ok\n" : "rt-fail\n";

// AES GCM (needs tag)
$tag = "";
$ct = openssl_encrypt($pt, "aes-256-gcm", $key256, OPENSSL_RAW_DATA, $iv, $tag);
echo strlen($ct) > 0 && strlen($tag) === 16 ? "gcm-ok\n" : "no\n";
$rt = openssl_decrypt($ct, "aes-256-gcm", $key256, OPENSSL_RAW_DATA, $iv, $tag);
echo $rt === $pt ? "gcm-rt\n" : "gcm-fail\n";

// wrong tag should fail
$rt = openssl_decrypt($ct, "aes-256-gcm", $key256, OPENSSL_RAW_DATA, $iv, str_repeat("X", 16));
var_dump($rt); // false

// bad cipher: PHP emits warning + returns false (architectural gap on warning)

// openssl_digest
echo openssl_digest("hello", "sha256"), "\n";
echo openssl_digest("hello", "md5"), "\n";
echo openssl_digest("hello", "sha1"), "\n";
echo openssl_digest("hello", "sha384"), "\n";
echo openssl_digest("", "sha256"), "\n";

// raw output
echo bin2hex(openssl_digest("hello", "sha256", true)), "\n";

// invalid digest: PHP emits warning + returns false (architectural gap on warning)

// hash_pbkdf2
$r = hash_pbkdf2("sha256", "pass", "salt", 1000, 0);
echo strlen($r), "|", ctype_xdigit($r) ? "hex" : "no", "\n"; // PHP default hex output

// raw
$r = hash_pbkdf2("sha256", "pass", "salt", 1000, 0, true);
echo strlen($r), ":", bin2hex($r), "\n";

$r = hash_pbkdf2("sha256", "pass", "salt", 1000, 32);
echo strlen($r), "\n"; // 32 hex chars

$r = hash_pbkdf2("sha256", "pass", "salt", 1000, 32, true);
echo strlen($r), "\n"; // 32 raw bytes

// password info
$h = password_hash("test", PASSWORD_BCRYPT, ["cost" => 4]);
$info = password_get_info($h);
echo $info["algo"] ?? "null", ":", $info["algoName"] ?? "null", "\n"; // 2y / bcrypt
print_r($info["options"]);

// invalid hash
$info = password_get_info("plain text");
echo $info["algo"] ?? "null", ":", $info["algoName"] ?? "null", "\n"; // 0/null:unknown
echo count($info["options"] ?? []), "\n";

// password_needs_rehash
$h = password_hash("test", PASSWORD_BCRYPT, ["cost" => 4]);
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ["cost" => 4]));
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ["cost" => 12]));

// PASSWORD_DEFAULT vs BCRYPT (both should be bcrypt currently)
echo PASSWORD_DEFAULT === PASSWORD_BCRYPT ? "default-bcrypt" : "default-other", "\n";

// base32 (not standard PHP but if available)
if (function_exists('base32_encode')) {
    echo base32_encode("Hello"), "\n";
} else {
    echo "no-base32\n";
}

// hash_hmac variants
echo hash_hmac("sha256", "msg", "key"), "\n";
echo hash_hmac("sha256", "msg", "key", true) === hex2bin(hash_hmac("sha256", "msg", "key")) ? "raw-eq\n" : "no\n";
echo hash_hmac("sha512", "", ""), "\n";

// hash list
$algos = hash_algos();
echo in_array("sha256", $algos) ? "sha256-yes\n" : "no\n";
echo in_array("md5", $algos) ? "md5-yes\n" : "no\n";
echo in_array("crc32b", $algos) ? "crc32b-yes\n" : "no\n";
echo gettype($algos), ":", count($algos) > 5 ? "many" : "few", "\n";

// CSPRNG: random_int
$samples = [];
for ($i = 0; $i < 10; $i++) $samples[] = random_int(0, 1000000);
echo count(array_unique($samples)) === count($samples) ? "all-unique\n" : "dupes\n";
