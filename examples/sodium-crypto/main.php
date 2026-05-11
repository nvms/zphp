<?php
// covers: sodium_crypto_secretbox, sodium_crypto_box (anonymous + authenticated),
//   sodium_crypto_sign, sodium_crypto_generichash, sodium_crypto_pwhash_str,
//   sodium_crypto_aead_xchacha20poly1305_ietf_*, sodium_bin2hex, sodium_compare

echo "=== symmetric: secretbox round-trip ===\n";
$key = str_repeat("\x42", SODIUM_CRYPTO_SECRETBOX_KEYBYTES);
$nonce = str_repeat("\x01", SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
$message = "secrets travel best when authenticated";
$cipher = sodium_crypto_secretbox($message, $nonce, $key);
echo "cipher length: " . strlen($cipher) . " bytes\n";
echo "decrypts to: " . sodium_crypto_secretbox_open($cipher, $nonce, $key) . "\n";

// tampering detection
$tampered = $cipher;
$tampered[0] = chr(ord($tampered[0]) ^ 0x01);
$result = sodium_crypto_secretbox_open($tampered, $nonce, $key);
echo "tampered opens to: " . var_export($result, true) . "\n";

echo "\n=== asymmetric: anonymous sealed box ===\n";
$alice_kp = sodium_crypto_box_keypair();
$alice_pk = sodium_crypto_box_publickey($alice_kp);

$letter = "for alice's eyes only";
$sealed = sodium_crypto_box_seal($letter, $alice_pk);
echo "sealed length: " . strlen($sealed) . " bytes\n";
echo "alice opens: " . sodium_crypto_box_seal_open($sealed, $alice_kp) . "\n";

echo "\n=== authenticated box between two parties ===\n";
$bob_kp = sodium_crypto_box_keypair();
$bob_pk = sodium_crypto_box_publickey($bob_kp);
$bob_sk = sodium_crypto_box_secretkey($bob_kp);
$alice_sk = sodium_crypto_box_secretkey($alice_kp);

$nonce_box = str_repeat("\x99", SODIUM_CRYPTO_BOX_NONCEBYTES);
$kp_a_to_b = sodium_crypto_box_keypair_from_secretkey_and_publickey($alice_sk, $bob_pk);
$ct = sodium_crypto_box("hello bob, signed by alice", $nonce_box, $kp_a_to_b);
$kp_b_from_a = sodium_crypto_box_keypair_from_secretkey_and_publickey($bob_sk, $alice_pk);
echo "bob opens: " . sodium_crypto_box_open($ct, $nonce_box, $kp_b_from_a) . "\n";

echo "\n=== ed25519 detached signatures ===\n";
$signer_kp = sodium_crypto_sign_keypair();
$signer_pk = sodium_crypto_sign_publickey($signer_kp);
$signer_sk = sodium_crypto_sign_secretkey($signer_kp);

$messages = ["one", "two", "three"];
foreach ($messages as $m) {
    $sig = sodium_crypto_sign_detached($m, $signer_sk);
    $valid = sodium_crypto_sign_verify_detached($sig, $m, $signer_pk);
    echo sprintf("  %-6s sig=%d bytes valid=%s\n", $m, strlen($sig), $valid ? "yes" : "no");
}

echo "\n=== blake2b generic hash ===\n";
$data = "the quick brown fox";
echo "default (32B): " . sodium_bin2hex(sodium_crypto_generichash($data)) . "\n";
echo "short  (16B):  " . sodium_bin2hex(sodium_crypto_generichash($data, '', 16)) . "\n";

echo "\n=== argon2id password hashing ===\n";
$password = "correct horse battery staple";
$hash = sodium_crypto_pwhash_str(
    $password,
    SODIUM_CRYPTO_PWHASH_OPSLIMIT_INTERACTIVE,
    SODIUM_CRYPTO_PWHASH_MEMLIMIT_INTERACTIVE,
);
echo "hash prefix: " . substr($hash, 0, 10) . "\n";
echo "verify correct: " . (sodium_crypto_pwhash_str_verify($hash, $password) ? "yes" : "no") . "\n";
echo "verify wrong:   " . (sodium_crypto_pwhash_str_verify($hash, "guess") ? "yes" : "no") . "\n";

echo "\n=== AEAD: XChaCha20-Poly1305 with associated data ===\n";
$aead_key = sodium_crypto_aead_xchacha20poly1305_ietf_keygen();
$aead_nonce = str_repeat("\x77", SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES);
$payload = "transfer $1000 to acct 42";
$ad = "tx-id=abc123";

$aead_ct = sodium_crypto_aead_xchacha20poly1305_ietf_encrypt($payload, $ad, $aead_nonce, $aead_key);
echo "aead cipher: " . strlen($aead_ct) . " bytes\n";

$opened = sodium_crypto_aead_xchacha20poly1305_ietf_decrypt($aead_ct, $ad, $aead_nonce, $aead_key);
echo "opens with correct AD: " . $opened . "\n";

$bad = sodium_crypto_aead_xchacha20poly1305_ietf_decrypt($aead_ct, "different-ad", $aead_nonce, $aead_key);
echo "wrong AD result: " . var_export($bad, true) . "\n";

echo "\n=== constant-time compare ===\n";
echo "abc vs abc: " . sodium_compare("abc", "abc") . "\n";
echo "abc vs abd: " . sodium_compare("abc", "abd") . "\n";
echo "abd vs abc: " . sodium_compare("abd", "abc") . "\n";
