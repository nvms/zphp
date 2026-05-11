<?php
echo hash("md5", "hello"), "\n";
echo hash("sha1", "hello"), "\n";
echo hash("sha256", "hello"), "\n";
echo hash("sha512", "hello"), "\n";
echo hash("crc32", "hello"), "\n";
echo hash("crc32b", "hello"), "\n";
echo hash("sha3-256", "hello"), "\n";
echo hash("sha3-512", "hello"), "\n";
echo hash("sha224", "hello"), "\n";
echo hash("sha384", "hello"), "\n";
echo bin2hex(hash("sha256", "hello", true)), "\n";

echo hash_hmac("sha256", "msg", "key"), "\n";
echo hash_hmac("sha1", "msg", "key"), "\n";
echo hash_hmac("md5", "msg", "key"), "\n";
echo bin2hex(hash_hmac("sha256", "msg", "key", true)), "\n";

echo bin2hex(hash_pbkdf2("sha256", "pass", "salt", 1000, 32, true)), "\n";
echo hash_pbkdf2("sha256", "pass", "salt", 1000, 64), "\n";
echo strlen(hash_pbkdf2("sha256", "pass", "salt", 1, 32)), "\n";

echo md5("hello"), "\n";
echo md5("hello") === hash("md5", "hello") ? "y" : "n", "\n";
echo sha1("hello"), "\n";
echo sha1("hello") === hash("sha1", "hello") ? "y" : "n", "\n";

echo crc32("hello"), "\n";
echo dechex(crc32("hello")), "\n";

$algos = hash_algos();
echo is_array($algos) ? "y" : "n", "\n";
echo in_array("md5", $algos) ? "y" : "n", "\n";
echo in_array("sha256", $algos) ? "y" : "n", "\n";
echo in_array("sha512", $algos) ? "y" : "n", "\n";
echo in_array("sha3-256", $algos) ? "y" : "n", "\n";
echo in_array("sha224", $algos) ? "y" : "n", "\n";
echo in_array("nonsense", $algos) ? "y" : "n", "\n";

$pwd = "secret";
$hash = password_hash($pwd, PASSWORD_DEFAULT);
echo password_verify($pwd, $hash) ? "y" : "n", "\n";
echo password_verify("wrong", $hash) ? "y" : "n", "\n";

$hash2 = password_hash($pwd, PASSWORD_BCRYPT);
echo password_verify($pwd, $hash2) ? "y" : "n", "\n";

$hash3 = password_hash($pwd, PASSWORD_BCRYPT, ["cost" => 4]);
echo password_verify($pwd, $hash3) ? "y" : "n", "\n";
echo password_needs_rehash($hash3, PASSWORD_BCRYPT) ? "y" : "n", "\n";
echo password_needs_rehash($hash3, PASSWORD_BCRYPT, ["cost" => 12]) ? "y" : "n", "\n";

$info = password_get_info($hash);
echo $info["algoName"] ?? "x", "\n";

echo hash_equals("abc", "abc") ? "y" : "n", "\n";
echo hash_equals("abc", "abd") ? "y" : "n", "\n";
echo hash_equals("abc", "abcd") ? "y" : "n", "\n";

$ctx = hash_init("sha256");
hash_update($ctx, "hello");
hash_update($ctx, " ");
hash_update($ctx, "world");
echo hash_final($ctx), "\n";

$ctx2 = hash_init("sha256");
hash_update($ctx2, "hello world");
echo hash_final($ctx2), "\n";

$ctx3 = hash_init("sha256", HASH_HMAC, "key");
hash_update($ctx3, "msg");
echo hash_final($ctx3), "\n";

$file = tempnam(sys_get_temp_dir(), "h");
file_put_contents($file, "content for hashing");
echo hash_file("sha256", $file), "\n";
unlink($file);

echo defined("PASSWORD_DEFAULT") ? "y" : "n", "\n";
echo defined("PASSWORD_BCRYPT") ? "y" : "n", "\n";

echo strlen(md5("test")), "\n";
echo strlen(sha1("test")), "\n";
echo strlen(hash("sha256", "test")), "\n";
echo strlen(hash("sha512", "test")), "\n";

echo bin2hex(md5("hello", true)), "\n";
echo bin2hex(sha1("hello", true)), "\n";
