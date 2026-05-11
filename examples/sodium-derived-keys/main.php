<?php
// covers: sodium_crypto_kdf_*, sodium_crypto_auth, sodium_pad/unpad,
//   sodium_crypto_scalarmult, sodium_increment, sodium_bin2base64

echo "=== KDF: derive subkeys from a master ===\n";
$master = str_repeat("\xA5", SODIUM_CRYPTO_KDF_KEYBYTES);
$context = "appauthx"; // exactly SODIUM_CRYPTO_KDF_CONTEXTBYTES (8) bytes
for ($id = 1; $id <= 4; $id++) {
    $subkey = sodium_crypto_kdf_derive_from_key(32, $id, $context, $master);
    echo sprintf("subkey #%d (%d bytes): %s\n", $id, strlen($subkey), sodium_bin2hex($subkey));
}

echo "\n=== Constant-context yields stable subkeys ===\n";
$a = sodium_crypto_kdf_derive_from_key(16, 7, $context, $master);
$b = sodium_crypto_kdf_derive_from_key(16, 7, $context, $master);
echo "deterministic: " . ($a === $b ? "yes" : "no") . "\n";
$c = sodium_crypto_kdf_derive_from_key(16, 8, $context, $master);
echo "different ids differ: " . ($a !== $c ? "yes" : "no") . "\n";

echo "\n=== HMAC-style auth tag ===\n";
$auth_key = sodium_crypto_auth_keygen();
$message = "transfer:bob:100";
$mac = sodium_crypto_auth($message, $auth_key);
echo "tag length: " . strlen($mac) . "\n";
echo "verify valid: " . (sodium_crypto_auth_verify($mac, $message, $auth_key) ? "yes" : "no") . "\n";
echo "verify tampered msg: " . (sodium_crypto_auth_verify($mac, "transfer:bob:101", $auth_key) ? "yes" : "no") . "\n";
$other_key = sodium_crypto_auth_keygen();
echo "verify wrong key: " . (sodium_crypto_auth_verify($mac, $message, $other_key) ? "yes" : "no") . "\n";

echo "\n=== pad/unpad ===\n";
$payloads = ["", "a", "ab", "abc", "abcdef"];
foreach ($payloads as $p) {
    $padded = sodium_pad($p, 8);
    $unpadded = sodium_unpad($padded, 8);
    echo sprintf("  len %2d -> padded %2d -> unpad ok=%s match=%s\n", strlen($p), strlen($padded), $unpadded !== false ? "yes" : "no", $unpadded === $p ? "yes" : "no");
}

echo "\n=== curve25519 scalarmult: shared secret ===\n";
$alice_sk = str_repeat("\x01", SODIUM_CRYPTO_SCALARMULT_SCALARBYTES);
$bob_sk = str_repeat("\x02", SODIUM_CRYPTO_SCALARMULT_SCALARBYTES);
$alice_pk = sodium_crypto_scalarmult_base($alice_sk);
$bob_pk = sodium_crypto_scalarmult_base($bob_sk);

$shared_a = sodium_crypto_scalarmult($alice_sk, $bob_pk);
$shared_b = sodium_crypto_scalarmult($bob_sk, $alice_pk);
echo "shared secrets match: " . ($shared_a === $shared_b ? "yes" : "no") . "\n";
echo "shared length: " . strlen($shared_a) . "\n";

echo "\n=== counter increment ===\n";
$counter = "\x00\x00\x00\x00";
for ($i = 0; $i < 4; $i++) {
    sodium_increment($counter);
    echo sprintf("after inc %d: %s\n", $i + 1, bin2hex($counter));
}
