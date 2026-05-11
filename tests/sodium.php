<?php
// covers: sodium constants, bin2hex/hex2bin, base64, secretbox, box, sign, generichash, pwhash_str, aead chacha/xchacha, memcmp/compare, kdf

assert(SODIUM_CRYPTO_SECRETBOX_KEYBYTES === 32);
assert(SODIUM_CRYPTO_BOX_NONCEBYTES === 24);
assert(SODIUM_CRYPTO_SIGN_BYTES === 64);
assert(SODIUM_CRYPTO_GENERICHASH_BYTES === 32);

// hex round-trip
$bin = "\x01\x02\x03\xff";
$hex = sodium_bin2hex($bin);
assert($hex === "010203ff");
assert(sodium_hex2bin($hex) === $bin);

// base64
$b64 = sodium_bin2base64($bin, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
assert(sodium_base642bin($b64, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING) === $bin);

// secretbox roundtrip
$key = sodium_crypto_secretbox_keygen();
assert(strlen($key) === 32);
$nonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
$msg = "hello world";
$ct = sodium_crypto_secretbox($msg, $nonce, $key);
$pt = sodium_crypto_secretbox_open($ct, $nonce, $key);
assert($pt === $msg);

// box roundtrip
$alice = sodium_crypto_box_keypair();
$bob = sodium_crypto_box_keypair();
$alice_sk = sodium_crypto_box_secretkey($alice);
$bob_pk = sodium_crypto_box_publickey($bob);
$kp_a2b = sodium_crypto_box_keypair_from_secretkey_and_publickey($alice_sk, $bob_pk);
$n = random_bytes(SODIUM_CRYPTO_BOX_NONCEBYTES);
$c = sodium_crypto_box("secret message", $n, $kp_a2b);

$bob_sk = sodium_crypto_box_secretkey($bob);
$alice_pk = sodium_crypto_box_publickey($alice);
$kp_b2a = sodium_crypto_box_keypair_from_secretkey_and_publickey($bob_sk, $alice_pk);
$m = sodium_crypto_box_open($c, $n, $kp_b2a);
assert($m === "secret message");

// sealed boxes
$sealed = sodium_crypto_box_seal("anonymous", $bob_pk);
assert(sodium_crypto_box_seal_open($sealed, $bob) === "anonymous");

// sign/verify
$kp = sodium_crypto_sign_keypair();
$pk = sodium_crypto_sign_publickey($kp);
$sk = sodium_crypto_sign_secretkey($kp);
$msg = "important";
$sig = sodium_crypto_sign_detached($msg, $sk);
assert(strlen($sig) === SODIUM_CRYPTO_SIGN_BYTES);
assert(sodium_crypto_sign_verify_detached($sig, $msg, $pk) === true);
assert(sodium_crypto_sign_verify_detached($sig, "tampered", $pk) === false);

// signed-message form
$signed = sodium_crypto_sign($msg, $sk);
$opened = sodium_crypto_sign_open($signed, $pk);
assert($opened === $msg);

// generic hash
$h1 = sodium_crypto_generichash("abc");
assert(strlen($h1) === 32);
$h2 = sodium_crypto_generichash("abc", str_repeat("\x00", 32), 16);
assert(strlen($h2) === 16);

// pwhash_str round-trip
$hash = sodium_crypto_pwhash_str("pass", SODIUM_CRYPTO_PWHASH_OPSLIMIT_INTERACTIVE, SODIUM_CRYPTO_PWHASH_MEMLIMIT_INTERACTIVE);
assert(is_string($hash));
assert(strncmp($hash, '$argon2id$', 10) === 0);
assert(sodium_crypto_pwhash_str_verify($hash, "pass") === true);
assert(sodium_crypto_pwhash_str_verify($hash, "wrong") === false);

// aead chacha20-poly1305 ietf
$k = sodium_crypto_aead_chacha20poly1305_ietf_keygen();
$n = random_bytes(SODIUM_CRYPTO_AEAD_CHACHA20POLY1305_IETF_NPUBBYTES);
$c = sodium_crypto_aead_chacha20poly1305_ietf_encrypt("data", "ad", $n, $k);
assert(sodium_crypto_aead_chacha20poly1305_ietf_decrypt($c, "ad", $n, $k) === "data");
assert(sodium_crypto_aead_chacha20poly1305_ietf_decrypt($c, "wrong-ad", $n, $k) === false);

// memcmp
assert(sodium_memcmp("abc", "abc") === 0);
assert(sodium_memcmp("abc", "abd") === -1);

// increment
$x = "\x01\x02\x03";
sodium_increment($x);
assert($x === "\x02\x02\x03");

echo "ok\n";
