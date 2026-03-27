<?php
// covers: hash, hash_hmac, hash_equals, hash_algos, bin2hex, hex2bin,
//   substr, strlen, strtolower, sprintf, str_repeat, explode, implode,
//   array_map, in_array, str_pad, md5, sha1, crc32

// available algorithms
echo "=== supported algorithms ===\n";
$algos = hash_algos();
$required = ['md5', 'sha1', 'sha256', 'sha384', 'sha512'];
foreach ($required as $algo) {
    echo "$algo: " . (in_array($algo, $algos) ? 'available' : 'missing') . "\n";
}

// basic hashing across algorithms
echo "\n=== hash comparison ===\n";
$message = "hello world";
$interesting_algos = ['md5', 'sha1', 'sha256', 'sha512'];
foreach ($interesting_algos as $algo) {
    $digest = hash($algo, $message);
    echo sprintf("  %-8s (%2d bytes) %s\n", $algo, strlen(hex2bin($digest)), $digest);
}

// verify hex2bin/bin2hex roundtrip
echo "\n=== hex encoding roundtrip ===\n";
$original = "The quick brown fox";
$hex = bin2hex($original);
$decoded = hex2bin($hex);
echo "original length: " . strlen($original) . "\n";
echo "hex: $hex\n";
echo "roundtrip match: " . ($decoded === $original ? 'yes' : 'no') . "\n";

// binary round trip via raw hex
$raw_hex = "deadbeef0102030405";
$binary = hex2bin($raw_hex);
echo "raw hex '$raw_hex' -> " . strlen($binary) . " bytes -> " . bin2hex($binary) . "\n";

// hmac signing
echo "\n=== HMAC signing ===\n";
$secret = "my-secret-key-2024";
$payloads = [
    'user=admin&action=login',
    'user=admin&action=delete',
    'amount=100&currency=USD',
];

foreach ($payloads as $payload) {
    $sig = hash_hmac('sha256', $payload, $secret);
    echo sprintf("  payload: %-30s sig: %.16s...\n", $payload, $sig);
}

// verify that different keys produce different signatures
echo "\n=== key sensitivity ===\n";
$data = "important message";
$keys = ['key1', 'key2', 'key1'];
$sigs = [];
foreach ($keys as $key) {
    $sigs[] = hash_hmac('sha256', $data, $key);
}
echo "key1 vs key2: " . ($sigs[0] === $sigs[1] ? 'same' : 'different') . "\n";
echo "key1 vs key1: " . ($sigs[0] === $sigs[2] ? 'same' : 'different') . "\n";

// hash_equals: timing-safe comparison
echo "\n=== hash_equals (timing-safe) ===\n";
$known_hash = hash('sha256', 'correct-password');

$test_cases = [
    ['correct-password', true],
    ['wrong-password', false],
    ['correct-passwore', false],
    ['', false],
];

foreach ($test_cases as $case) {
    $candidate = hash('sha256', $case[0]);
    $result = hash_equals($known_hash, $candidate);
    $expected = $case[1];
    $status = ($result === $expected) ? 'ok' : 'FAIL';
    $label = strlen($case[0]) > 0 ? $case[0] : '(empty)';
    echo sprintf("  %-25s expected=%-5s got=%-5s %s\n",
        $label, $expected ? 'true' : 'false', $result ? 'true' : 'false', $status);
}

// different lengths always return false
echo "  length mismatch: " . (hash_equals("abc", "ab") ? 'true' : 'false') . "\n";

// webhook signature verification pattern
echo "\n=== webhook verification ===\n";
function verifyWebhook(string $payload, string $signature, string $secret): bool {
    $expected = hash_hmac('sha256', $payload, $secret);
    return hash_equals($expected, $signature);
}

$webhook_secret = "whsec_test123";
$payload = '{"event":"payment.completed","amount":9999}';
$valid_sig = hash_hmac('sha256', $payload, $webhook_secret);
$tampered_sig = hash_hmac('sha256', $payload . ' ', $webhook_secret);

echo "valid signature: " . (verifyWebhook($payload, $valid_sig, $webhook_secret) ? 'accepted' : 'rejected') . "\n";
echo "tampered sig:    " . (verifyWebhook($payload, $tampered_sig, $webhook_secret) ? 'accepted' : 'rejected') . "\n";
echo "wrong secret:    " . (verifyWebhook($payload, $valid_sig, "wrong-secret") ? 'accepted' : 'rejected') . "\n";

// api token generation pattern
echo "\n=== token generation ===\n";
function generateToken(string $user_id, string $secret): string {
    $timestamp = 1700000000;
    $data = "$user_id:$timestamp";
    $sig = hash_hmac('sha256', $data, $secret);
    return "$data:$sig";
}

function validateToken(string $token, string $secret): array {
    $parts = explode(':', $token);
    if (count($parts) !== 3) return ['valid' => false, 'user' => ''];
    $data = $parts[0] . ':' . $parts[1];
    $sig = $parts[2];
    $expected = hash_hmac('sha256', $data, $secret);
    return [
        'valid' => hash_equals($expected, $sig),
        'user' => $parts[0],
    ];
}

$secret = "app-secret-key";
$token = generateToken("user_42", $secret);
echo "token: " . substr($token, 0, 30) . "...\n";

$check = validateToken($token, $secret);
echo "valid: " . ($check['valid'] ? 'yes' : 'no') . "\n";
echo "user: " . $check['user'] . "\n";

// tamper with token
$tampered = str_replace("user_42", "user_99", $token);
$check2 = validateToken($tampered, $secret);
echo "tampered valid: " . ($check2['valid'] ? 'yes' : 'no') . "\n";

// checksum verification
echo "\n=== data integrity ===\n";
$files = [
    'config.json' => '{"db":"localhost","port":5432}',
    'schema.sql' => 'CREATE TABLE users (id INT, name TEXT);',
    'readme.txt' => 'This is the readme file for the project.',
];

echo sprintf("  %-15s %-32s %s\n", "file", "md5", "sha1 (first 16)");
foreach ($files as $name => $content) {
    echo sprintf("  %-15s %-32s %.16s\n", $name, md5($content), sha1($content));
}
