<?php
echo md5("hello"), "\n";
echo md5(""), "\n";
echo md5("The quick brown fox jumps over the lazy dog"), "\n";
echo bin2hex(md5("hello", true)), "\n";
echo strlen(md5("x", true)), "\n";

echo sha1("hello"), "\n";
echo sha1(""), "\n";
echo bin2hex(sha1("hello", true)), "\n";
echo strlen(sha1("x", true)), "\n";

echo hash("sha256", "hello"), "\n";
echo hash("sha256", ""), "\n";
echo hash("sha512", "hello"), "\n";
echo hash("md5", "hello"), "\n";
echo hash("sha1", "hello"), "\n";
echo bin2hex(hash("sha256", "hello", true)), "\n";

echo crc32("hello"), "\n";
echo crc32(""), "\n";
echo crc32("123456789"), "\n";
echo sprintf("%08x", crc32("hello")), "\n";

echo hash("crc32b", "hello"), "\n";
echo hash("crc32", "hello"), "\n";

echo hash("sha384", "hello"), "\n";
echo strlen(hash("sha256", "x")), "\n";
echo strlen(hash("sha512", "x")), "\n";
echo strlen(hash("md5", "x")), "\n";

echo hash("sha256", "abc"), "\n";

echo hash_hmac("sha256", "data", "key"), "\n";
echo hash_hmac("sha1", "data", "key"), "\n";
echo hash_hmac("md5", "data", "key"), "\n";
echo hash_hmac("sha256", "", ""), "\n";
echo hash_hmac("sha256", "long key " . str_repeat("x", 100), "k"), "\n";
echo hash_hmac("sha256", "msg", str_repeat("k", 100)), "\n";

echo bin2hex(hash_hmac("sha256", "data", "key", true)), "\n";

echo in_array("md5", hash_algos()) ? "y" : "n", "\n";
echo in_array("sha256", hash_algos()) ? "y" : "n", "\n";
echo in_array("sha512", hash_algos()) ? "y" : "n", "\n";

echo strlen(password_hash("password", PASSWORD_BCRYPT)) > 0 ? "y" : "n", "\n";
echo password_verify("password", password_hash("password", PASSWORD_BCRYPT)) ? "y" : "n", "\n";
echo password_verify("wrong", password_hash("password", PASSWORD_BCRYPT)) ? "y" : "n", "\n";

$hash = password_hash("test", PASSWORD_BCRYPT, ["cost" => 10]);
echo password_verify("test", $hash) ? "y" : "n", "\n";
echo strlen($hash) === 60 ? "y" : "n", "\n";
echo str_starts_with($hash, "\$2y\$10\$") ? "y" : "n", "\n";

echo password_needs_rehash($hash, PASSWORD_BCRYPT, ["cost" => 10]) ? "y" : "n", "\n";
echo password_needs_rehash($hash, PASSWORD_BCRYPT, ["cost" => 12]) ? "y" : "n", "\n";

$info = password_get_info($hash);
echo $info["algoName"] ?? "?", "\n";
echo isset($info["options"]["cost"]) ? $info["options"]["cost"] : "?", "\n";

echo password_verify("", password_hash("", PASSWORD_BCRYPT)) ? "y" : "n", "\n";

$h1 = password_hash("samepw", PASSWORD_BCRYPT);
$h2 = password_hash("samepw", PASSWORD_BCRYPT);
echo $h1 === $h2 ? "same" : "diff", "\n";
echo password_verify("samepw", $h1) ? "y" : "n", "\n";
echo password_verify("samepw", $h2) ? "y" : "n", "\n";

echo password_verify("a", '$2y$10$invalidhashheresoverylongabcdefghijklmnopqrstuvwxyz123') ? "y" : "n", "\n";

echo strtolower(hash("sha256", "")) === "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ? "y" : "n", "\n";

echo hash_equals("a", "a") ? "y" : "n", "\n";
echo hash_equals("a", "b") ? "y" : "n", "\n";
echo hash_equals("hello", "hello") ? "y" : "n", "\n";
echo hash_equals("hello", "Hello") ? "y" : "n", "\n";
echo hash_equals("ab", "abc") ? "y" : "n", "\n";

echo hash_pbkdf2("sha256", "password", "salt", 1000, 32), "\n";
echo strlen(hash_pbkdf2("sha256", "password", "salt", 1000, 32)), "\n";
echo strlen(hash_pbkdf2("sha256", "password", "salt", 1000, 32, true)), "\n";

