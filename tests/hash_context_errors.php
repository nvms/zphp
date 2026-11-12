<?php
// HashContext's object behaviour and ext/hash's argument errors
function attempt(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$ctx = hash_init("sha256");
var_dump($ctx);
hash_update($ctx, "abc");
$copy = clone $ctx;
echo hash_final($ctx), "\n";
var_dump($ctx);
attempt(fn() => hash_update($ctx, "x"));
attempt(fn() => hash_final($ctx));
attempt(fn() => hash_copy($ctx));
attempt(fn() => clone $ctx);
attempt(fn() => serialize($ctx));
echo hash_final($copy), "\n";
attempt(fn() => new HashContext());
attempt(fn() => serialize(hash_init("md5", HASH_HMAC, "key")));
attempt(fn() => serialize(hash_init("xxh128")));
attempt(fn() => hash_init("nope"));
attempt(fn() => hash_init("crc32", HASH_HMAC, "key"));
attempt(fn() => hash_init("md5", HASH_HMAC));
attempt(fn() => hash("nope", "x"));
attempt(fn() => hash("MD5", "x"));
attempt(fn() => hash_hmac("crc32b", "x", "k"));
attempt(fn() => hash_hmac_file("md5", "a\0b", "k"));
attempt(fn() => hash_file("md5", "a\0b"));
attempt(fn() => hash_pbkdf2("adler32", "p", "s", 1));
attempt(fn() => hash_pbkdf2("md5", "p", "s", 0));
attempt(fn() => hash_pbkdf2("md5", "p", "s", 1, -1));
attempt(fn() => hash_hkdf("md5", ""));
attempt(fn() => hash_hkdf("md5", "k", -1));
attempt(fn() => hash_hkdf("md5", "k", 16 * 255 + 1));
attempt(fn() => hash_hkdf("fnv164", "k"));
attempt(fn() => hash_equals("a", 1));
attempt(fn() => hash_equals(null, "a"));
attempt(fn() => hash_equals("abc", "abc"));
attempt(fn() => hash_init("xxh3", 0, "", ["seed" => 1, "secret" => str_repeat("s", 200)]));
attempt(fn() => hash_init("xxh3", 0, "", ["secret" => "short"]));
attempt(fn() => hash("xxh64", "x", false, ["seed" => "1"]));
attempt(fn() => hash("murmur3a", "x", false, ["seed" => 1.5]));

$bad = [
    'O:11:"HashContext":5:{i:0;s:3:"md5";i:1;i:0;i:2;a:0:{}i:3;i:2;i:4;a:0:{}}',
    'O:11:"HashContext":5:{i:0;s:4:"nope";i:1;i:0;i:2;a:0:{}i:3;i:2;i:4;a:0:{}}',
    'O:11:"HashContext":5:{i:0;s:3:"md5";i:1;i:1;i:2;a:0:{}i:3;i:2;i:4;a:0:{}}',
    'O:11:"HashContext":4:{i:0;s:3:"md5";i:1;i:0;i:2;a:0:{}i:3;i:2;}',
    'O:11:"HashContext":5:{i:0;s:4:"sha1";i:1;i:0;i:2;a:0:{}i:3;i:7;i:4;a:0:{}}',
    'O:11:"HashContext":5:{i:0;s:3:"md2";i:1;i:0;i:2;a:4:{i:0;s:48:"' . str_repeat("a", 48) . '";i:1;s:16:"' . str_repeat("b", 16) . '";i:2;s:16:"' . str_repeat("c", 16) . '";i:3;i:99;}i:3;i:2;i:4;a:0:{}}',
];
foreach ($bad as $s) attempt(fn() => unserialize($s));

$c = hash_init("md5");
$c->extra = 1;
$s = serialize($c);
echo $s, "\n";
print_r(unserialize($s));
echo "\n";

$fp = fopen("php://memory", "w+");
fwrite($fp, str_repeat("stream data ", 300));
rewind($fp);
$c = hash_init("sha1");
var_dump(hash_update_stream($c, $fp, 1000));
var_dump(hash_update_stream($c, $fp));
echo hash_final($c), " ", sha1(str_repeat("stream data ", 300)), "\n";
attempt(fn() => hash_update_stream(hash_init("md5"), "nope"));

var_dump(mhash_count(), mhash_get_hash_name(MHASH_WHIRLPOOL), mhash_get_block_size(MHASH_TIGER), mhash_get_hash_name(4));
echo bin2hex(@mhash(MHASH_RIPEMD160, "data")), " ", bin2hex(@mhash(MHASH_SHA256, "data", "key")), "\n";
echo bin2hex(@mhash_keygen_s2k(MHASH_MD5, "password", "saltsaltsalt", 40)), "\n";
var_dump(hash_algos() === array_keys(array_flip(hash_algos())), count(hash_algos()), count(hash_hmac_algos()));
