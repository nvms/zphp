<?php
// every hash_algos() algorithm: one-shot, streamed in uneven chunks, hmac,
// and a context serialized mid-stream (the serialized state is php's own
// context layout, so the strings must match byte for byte)
$data = str_repeat("The quick brown fox jumps over the lazy dog. ", 7) . "\x00\xff\x80tail";
$chunks = [1, 3, 7, 64, 65, 127, 129, 5];

foreach (hash_algos() as $algo) {
    $one = hash($algo, $data);
    $ctx = hash_init($algo);
    $pos = 0;
    $i = 0;
    while ($pos < strlen($data)) {
        $n = $chunks[$i++ % count($chunks)];
        hash_update($ctx, substr($data, $pos, $n));
        $pos += $n;
    }
    $streamed = hash_final($ctx);
    echo $algo, " ", $one, " ", $one === $streamed ? "same" : "streamed differs: $streamed", "\n";
    echo "  empty ", hash($algo, ""), " raw ", strlen(hash($algo, "abc", true)), "\n";
    if (in_array($algo, hash_hmac_algos(), true)) {
        echo "  hmac ", hash_hmac($algo, $data, "key"), "\n";
        echo "  hmac long key ", hash_hmac($algo, "abc", str_repeat("k", 200)), "\n";
        $h = hash_init($algo, HASH_HMAC, "secret");
        hash_update($h, substr($data, 0, 10));
        hash_update($h, substr($data, 10));
        echo "  hmac ctx ", hash_final($h) === hash_hmac($algo, $data, "secret") ? "same" : "differs", "\n";
    }
    $ctx = hash_init($algo);
    hash_update($ctx, substr($data, 0, 77));
    try {
        $s = serialize($ctx);
        echo "  serialized ", md5($s), "\n";
        $back = unserialize($s);
        hash_update($back, substr($data, 77));
        echo "  resumed ", hash_final($back) === $one ? "same" : "differs", "\n";
    } catch (Exception $e) {
        echo "  ", $e->getMessage(), "\n";
    }
    $copy = hash_copy($ctx);
    hash_update($ctx, "x");
    hash_update($copy, "x");
    echo "  copy ", hash_final($ctx) === hash_final($copy) ? "same" : "differs", "\n";
}

// seeds and secrets
foreach (["murmur3a", "murmur3c", "murmur3f", "xxh32", "xxh64", "xxh3", "xxh128"] as $algo) {
    echo $algo, " seed ", hash($algo, $data, false, ["seed" => 42]), "\n";
}
$secret = str_repeat("0123456789abcdef", 10);
foreach (["xxh3", "xxh128"] as $algo) {
    echo $algo, " secret ", hash($algo, $data, false, ["secret" => $secret]), "\n";
    $c = hash_init($algo, 0, "", ["secret" => $secret]);
    hash_update($c, $data);
    $d = clone $c;
    echo "  ", hash_final($c), " ", hash_final($d), "\n";
}
echo hash_pbkdf2("sha256", "password", "salt", 1000, 20), "\n";
echo bin2hex(hash_pbkdf2("ripemd160", "password", "salt", 3, 0, true)), "\n";
echo bin2hex(hash_hkdf("whirlpool", "input key", 70, "info", "salt")), "\n";
echo hash_file("tiger192,4", __FILE__) === hash("tiger192,4", file_get_contents(__FILE__)) ? "file same\n" : "file differs\n";
