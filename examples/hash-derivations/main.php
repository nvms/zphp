<?php
// covers: hash() across algorithms, hash_hmac, hash_pbkdf2, hash_hkdf,
//   hash_equals constant-time, streaming hash_init/update/final/copy,
//   hash_file, crc32

echo "=== hash() across algorithms ===\n";
$msg = "the quick brown fox";
foreach (['md5', 'sha1', 'sha256', 'sha384', 'sha512', 'sha3-256'] as $algo) {
    $h = hash($algo, $msg);
    echo sprintf("  %-9s (%2d bytes) %s\n", $algo, strlen(hex2bin($h)), substr($h, 0, 16) . "...");
}

echo "\n=== raw output flag ===\n";
$bin = hash('sha256', "abc", true);
echo "raw is " . strlen($bin) . " bytes\n";
echo "matches hex hash: " . (bin2hex($bin) === hash('sha256', "abc") ? "yes" : "no") . "\n";

echo "\n=== hash_hmac ===\n";
$key = "secret-key";
$tag = hash_hmac('sha256', $msg, $key);
echo "tag: " . substr($tag, 0, 20) . "...\n";
echo "verify same: " . (hash_hmac('sha256', $msg, $key) === $tag ? "yes" : "no") . "\n";
echo "different msg differs: " . (hash_hmac('sha256', 'other', $key) !== $tag ? "yes" : "no") . "\n";

echo "\n=== hash_pbkdf2 ===\n";
$pw = "correct horse battery staple";
$salt = "saltsaltsaltsalt";
$d = hash_pbkdf2('sha256', $pw, $salt, 1000, 32);
echo "derived hex chars: " . strlen($d) . "\n";
$d2 = hash_pbkdf2('sha256', $pw, $salt, 1000, 32, true);
echo "raw bytes: " . strlen($d2) . "\n";
echo "consistency: " . ($d === bin2hex($d2) ? "yes" : "no") . "\n";

echo "\n=== hash_hkdf ===\n";
$ikm = "input keying material";
$hkdf = hash_hkdf('sha256', $ikm, 32, 'context-info', $salt);
echo "hkdf bytes: " . strlen($hkdf) . "\n";
$hkdf_b = hash_hkdf('sha256', $ikm, 32, 'context-info', $salt);
echo "deterministic: " . ($hkdf === $hkdf_b ? "yes" : "no") . "\n";

echo "\n=== hash_equals timing-safe compare ===\n";
$a = hash('sha256', "secret");
echo "match: " . (hash_equals($a, hash('sha256', "secret")) ? "yes" : "no") . "\n";
echo "mismatch: " . (hash_equals($a, hash('sha256', "other")) ? "yes" : "no") . "\n";
echo "length mismatch: " . (hash_equals($a, "short") ? "yes" : "no") . "\n";

echo "\n=== streaming hash_init/update/final ===\n";
$ctx = hash_init('sha256');
foreach (['the ', 'quick ', 'brown ', 'fox'] as $chunk) hash_update($ctx, $chunk);
$streamed = hash_final($ctx);
echo "streamed: " . substr($streamed, 0, 16) . "...\n";
echo "matches one-shot: " . ($streamed === hash('sha256', 'the quick brown fox') ? "yes" : "no") . "\n";

echo "\n=== hash_copy preserves state ===\n";
$base = hash_init('sha256');
hash_update($base, 'prefix-');
$copy_a = hash_copy($base);
$copy_b = hash_copy($base);
hash_update($copy_a, 'A');
hash_update($copy_b, 'B');
$ha = hash_final($copy_a);
$hb = hash_final($copy_b);
echo "branches differ: " . ($ha !== $hb ? "yes" : "no") . "\n";
echo "matches prefix+A: " . ($ha === hash('sha256', 'prefix-A') ? "yes" : "no") . "\n";

echo "\n=== hash_file ===\n";
$tmp = tempnam(sys_get_temp_dir(), 'hf');
file_put_contents($tmp, "file-contents-to-hash\n");
echo "sha256(file): " . substr(hash_file('sha256', $tmp), 0, 16) . "...\n";
echo "matches contents: " . (hash_file('sha256', $tmp) === hash('sha256', file_get_contents($tmp)) ? "yes" : "no") . "\n";
unlink($tmp);

echo "\n=== crc32 ===\n";
echo "crc32('hello'): " . sprintf('%08x', crc32('hello')) . "\n";
echo "hash crc32b: " . hash('crc32b', 'hello') . "\n";

echo "\n=== md5/sha1 shortcuts ===\n";
echo "md5(abc): " . md5('abc') . "\n";
echo "sha1(abc): " . sha1('abc') . "\n";

echo "\n=== algo list ===\n";
$algos = hash_algos();
$required = ['md5', 'sha1', 'sha256', 'sha384', 'sha512'];
foreach ($required as $r) echo "  $r: " . (in_array($r, $algos) ? "yes" : "no") . "\n";

echo "\ndone\n";
