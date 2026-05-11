<?php
// covers: signed/authenticated session cookies using ed25519 + base64url,
//   constant-time signature verification, expiry handling, JSON serialization.
//   "stateless server" pattern - all session data lives in the cookie.

function b64u_encode(string $bin): string {
    return rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
}

function b64u_decode(string $enc): string|false {
    $pad = strlen($enc) % 4;
    if ($pad) $enc .= str_repeat('=', 4 - $pad);
    return base64_decode(strtr($enc, '-_', '+/'), true);
}

class CookieSigner {
    private string $sk;
    private string $pk;

    public function __construct() {
        $kp = sodium_crypto_sign_keypair();
        $this->sk = sodium_crypto_sign_secretkey($kp);
        $this->pk = sodium_crypto_sign_publickey($kp);
    }

    public function publicKey(): string { return $this->pk; }

    public function issue(array $claims, int $ttl_seconds): string {
        $claims['exp'] = time() + $ttl_seconds;
        $payload = json_encode($claims, JSON_UNESCAPED_SLASHES);
        $sig = sodium_crypto_sign_detached($payload, $this->sk);
        return b64u_encode($payload) . '.' . b64u_encode($sig);
    }
}

class CookieVerifier {
    public function __construct(private string $pk) {}

    public function verify(string $cookie, int $now = -1): array|false {
        $now = $now < 0 ? time() : $now;
        $parts = explode('.', $cookie);
        if (count($parts) !== 2) return false;
        $payload = b64u_decode($parts[0]);
        $sig = b64u_decode($parts[1]);
        if ($payload === false || $sig === false) return false;
        if (strlen($sig) !== SODIUM_CRYPTO_SIGN_BYTES) return false;
        if (!sodium_crypto_sign_verify_detached($sig, $payload, $this->pk)) return false;
        $claims = json_decode($payload, true);
        if (!is_array($claims)) return false;
        if (isset($claims['exp']) && $claims['exp'] < $now) return false;
        return $claims;
    }
}

$signer = new CookieSigner();
$verifier = new CookieVerifier($signer->publicKey());

echo "=== happy path ===\n";
$cookie = $signer->issue(['uid' => 42, 'role' => 'admin'], 3600);
echo "cookie shape: " . (preg_match('/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/', $cookie) ? "valid" : "invalid") . "\n";
$claims = $verifier->verify($cookie);
echo "verified uid=" . $claims['uid'] . " role=" . $claims['role'] . "\n";

echo "\n=== expired cookie ===\n";
$expired = $signer->issue(['uid' => 1], -60);
$result = $verifier->verify($expired);
echo "rejected expired: " . ($result === false ? "yes" : "no") . "\n";

echo "\n=== tampered payload ===\n";
$cookie = $signer->issue(['uid' => 7, 'admin' => false], 3600);
[$body, $sig] = explode('.', $cookie);
$decoded = b64u_decode($body);
$tampered_body = str_replace('"admin":false', '"admin":true', $decoded);
$tampered_cookie = b64u_encode($tampered_body) . '.' . $sig;
$result = $verifier->verify($tampered_cookie);
echo "rejected tampered: " . ($result === false ? "yes" : "no") . "\n";

echo "\n=== wrong signing key ===\n";
$other_signer = new CookieSigner();
$cookie = $other_signer->issue(['uid' => 99], 3600);
$result = $verifier->verify($cookie);
echo "rejected foreign signature: " . ($result === false ? "yes" : "no") . "\n";

echo "\n=== malformed cookies ===\n";
$cases = ['', 'not.a.real.cookie', 'onlyonepart', 'a.b.c', 'invalid_base64?!.xx'];
foreach ($cases as $c) {
    $r = $verifier->verify($c);
    echo sprintf("  %-25s -> %s\n", $c === '' ? '(empty)' : $c, $r === false ? "rejected" : "accepted");
}

echo "\n=== claim round-trips ===\n";
$rich_claims = [
    'uid' => 1234567890,
    'email' => 'alice@example.com',
    'scopes' => ['read', 'write', 'admin'],
    'meta' => ['ip' => '203.0.113.5', 'ua' => 'Mozilla/5.0'],
    'flags' => 0b1011,
];
$cookie = $signer->issue($rich_claims, 60);
$verified = $verifier->verify($cookie);
echo "uid matches: " . ($verified['uid'] === $rich_claims['uid'] ? "yes" : "no") . "\n";
echo "scopes count: " . count($verified['scopes']) . "\n";
echo "nested meta.ip: " . $verified['meta']['ip'] . "\n";
echo "binary flags: " . $verified['flags'] . "\n";
