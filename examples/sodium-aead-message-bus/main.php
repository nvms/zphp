<?php
// covers: AEAD encrypt/decrypt round-trips with associated-data binding,
//   binary-safe storage via base64, replay detection via nonce bookkeeping,
//   tampered ciphertext detection. realistic "encrypted message bus" pattern.

class MessageBus {
    private string $key;
    /** @var array<string, true> */
    private array $seen_nonces = [];

    public function __construct() {
        $this->key = sodium_crypto_aead_xchacha20poly1305_ietf_keygen();
    }

    public function publish(string $payload, string $topic): string {
        $nonce = random_bytes(SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES);
        $cipher = sodium_crypto_aead_xchacha20poly1305_ietf_encrypt($payload, $topic, $nonce, $this->key);
        return sodium_bin2base64($nonce . $cipher, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
    }

    public function consume(string $envelope, string $topic): array {
        $raw = sodium_base642bin($envelope, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
        if ($raw === false || strlen($raw) < SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES) {
            return ['ok' => false, 'error' => 'malformed envelope'];
        }
        $nonce = substr($raw, 0, SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES);
        $cipher = substr($raw, SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES);
        $hex = bin2hex($nonce);
        if (isset($this->seen_nonces[$hex])) {
            return ['ok' => false, 'error' => 'replay'];
        }
        $plain = sodium_crypto_aead_xchacha20poly1305_ietf_decrypt($cipher, $topic, $nonce, $this->key);
        if ($plain === false) {
            return ['ok' => false, 'error' => 'tag mismatch'];
        }
        $this->seen_nonces[$hex] = true;
        return ['ok' => true, 'payload' => $plain];
    }
}

$bus = new MessageBus();

echo "=== normal publish + consume ===\n";
$envelope = $bus->publish("hello world", "topic-a");
echo "envelope is base64-ish: " . (preg_match('/^[A-Za-z0-9_-]+$/', $envelope) ? "yes" : "no") . "\n";
$result = $bus->consume($envelope, "topic-a");
echo "consume ok=" . ($result['ok'] ? "yes" : "no") . " payload=" . ($result['payload'] ?? "") . "\n";

echo "\n=== wrong topic (AD mismatch) ===\n";
$envelope = $bus->publish("for topic-a only", "topic-a");
$result = $bus->consume($envelope, "topic-b");
echo "result ok=" . var_export($result['ok'], true) . " error=" . ($result['error'] ?? "") . "\n";

echo "\n=== replay detection ===\n";
$envelope = $bus->publish("once-only", "events");
$r1 = $bus->consume($envelope, "events");
$r2 = $bus->consume($envelope, "events");
echo "first: ok=" . var_export($r1['ok'], true) . " payload=" . ($r1['payload'] ?? "") . "\n";
echo "second: ok=" . var_export($r2['ok'], true) . " error=" . ($r2['error'] ?? "") . "\n";

echo "\n=== ciphertext tamper ===\n";
$envelope = $bus->publish("transfer 100", "tx");
$raw = sodium_base642bin($envelope, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
// flip last byte (auth tag region)
$raw[strlen($raw) - 1] = chr(ord($raw[strlen($raw) - 1]) ^ 0x01);
$tampered = sodium_bin2base64($raw, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
$result = $bus->consume($tampered, "tx");
echo "tampered result: ok=" . var_export($result['ok'], true) . " error=" . ($result['error'] ?? "") . "\n";

echo "\n=== throughput sanity (100 messages) ===\n";
$bus2 = new MessageBus();
$count_ok = 0;
for ($i = 0; $i < 100; $i++) {
    $env = $bus2->publish("msg-$i", "bulk");
    $r = $bus2->consume($env, "bulk");
    if ($r['ok'] && $r['payload'] === "msg-$i") $count_ok++;
}
echo "round-tripped: $count_ok/100\n";
