<?php
echo md5("hello"), "\n";
echo md5(""), "\n";
echo md5("a"), "\n";

echo sha1("hello"), "\n";
echo sha1(""), "\n";

echo hash("sha256", "hello"), "\n";
echo hash("sha256", ""), "\n";

echo hash("sha512", "hello"), "\n";

echo hash("crc32", "hello"), "\n";
echo hash("crc32b", "hello"), "\n";
echo crc32("hello"), "\n";

echo hash("md5", "hello"), "\n";
echo hash("sha1", "hello"), "\n";

// raw output
echo bin2hex(md5("hello", true)), "\n";
echo bin2hex(hash("sha256", "hello", true)), "\n";

// hash_hmac
echo hash_hmac("sha256", "message", "secret"), "\n";
echo hash_hmac("sha1", "message", "secret"), "\n";
echo hash_hmac("md5", "message", "secret"), "\n";
echo hash_hmac("sha512", "message", "secret"), "\n";

// hash_hmac empty
echo hash_hmac("sha256", "", ""), "\n";

// hash_hmac binary key
echo hash_hmac("sha256", "data", "\x00\x01\x02\x03"), "\n";

// hash_hmac raw
echo bin2hex(hash_hmac("sha256", "msg", "key", true)), "\n";

// hash_pbkdf2
echo hash_pbkdf2("sha256", "password", "salt", 1000, 32), "\n";
echo hash_pbkdf2("sha256", "password", "salt", 1, 20), "\n";
echo hash_pbkdf2("sha1", "password", "salt", 1, 20), "\n";

// hash_pbkdf2 raw output
echo bin2hex(hash_pbkdf2("sha256", "p", "s", 1, 32, true)), "\n";

// hash_pbkdf2 with length 0 (default for full digest)
echo strlen(hash_pbkdf2("sha256", "p", "s", 1, 0)), "\n"; // default full digest as hex

// hash_equals constant time
var_dump(hash_equals("hello", "hello"));
var_dump(hash_equals("hello", "world"));
var_dump(hash_equals("hello", "helloo"));
var_dump(hash_equals("", ""));
var_dump(hash_equals("a", ""));
var_dump(hash_equals("a", "b"));

// hash_equals returns false on different lengths
var_dump(hash_equals("abc", "abcd"));

// hash_equals with binary
var_dump(hash_equals(hex2bin("deadbeef"), hex2bin("deadbeef")));
var_dump(hash_equals(hex2bin("deadbeef"), hex2bin("deadbeee")));

// hash_algos contains common algorithms
$algos = hash_algos();
foreach (["md5", "sha1", "sha256", "sha512", "crc32", "crc32b"] as $a) {
    echo "$a:", in_array($a, $algos) ? "y" : "n", " ";
}
echo "\n";

// streaming hash
$ctx = hash_init("sha256");
hash_update($ctx, "hello");
hash_update($ctx, " ");
hash_update($ctx, "world");
echo hash_final($ctx), "\n";

// vs single-shot
echo hash("sha256", "hello world"), "\n";

// hash_init with key (hmac mode)
$ctx = hash_init("sha256", HASH_HMAC, "secret");
hash_update($ctx, "message");
echo hash_final($ctx), "\n";
echo hash_hmac("sha256", "message", "secret"), "\n";

// hash_copy
$a = hash_init("sha256");
hash_update($a, "abc");
$b = hash_copy($a);
hash_update($a, "1");
hash_update($b, "2");
echo hash_final($a), "\n";
echo hash_final($b), "\n";

// hash_final raw
$c = hash_init("md5");
hash_update($c, "test");
echo bin2hex(hash_final($c, true)), "\n";

// hash on int (php casts to string)
echo md5(123), "\n";

// password_hash / password_verify
$h = password_hash("secret", PASSWORD_BCRYPT);
var_dump(password_verify("secret", $h));
var_dump(password_verify("wrong", $h));

$h2 = password_hash("hello", PASSWORD_DEFAULT);
var_dump(password_verify("hello", $h2));

// password_hash with cost
$h = password_hash("data", PASSWORD_BCRYPT, ["cost" => 5]);
echo strpos($h, '$2y$05') === 0 ? "cost-ok" : "cost-no", "\n";
