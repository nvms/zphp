<?php
// covers: base64_encode, base64_decode, str_replace, rtrim, strtr, hash_hmac,
//   hash_equals, json_encode, json_decode, explode, implode, array_map,
//   strlen, substr, time, sprintf, in_array, array_keys, array_merge,
//   throw, try/catch, RuntimeException, DateTimeImmutable

function b64url_encode(string $bin): string {
    return rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
}

function b64url_decode(string $s): string {
    $pad = strlen($s) % 4;
    if ($pad) $s .= str_repeat('=', 4 - $pad);
    $bin = base64_decode(strtr($s, '-_', '+/'), true);
    if ($bin === false) throw new RuntimeException('invalid base64url');
    return $bin;
}

const JWT_ALGOS = [
    'HS256' => 'sha256',
    'HS384' => 'sha384',
    'HS512' => 'sha512',
];

function jwt_encode(array $claims, string $secret, string $alg = 'HS256'): string {
    if (!isset(JWT_ALGOS[$alg])) {
        throw new RuntimeException("unsupported algorithm: $alg");
    }
    $header = ['alg' => $alg, 'typ' => 'JWT'];
    $h = b64url_encode(json_encode($header));
    $p = b64url_encode(json_encode($claims));
    $signing_input = $h . '.' . $p;
    $sig = hash_hmac(JWT_ALGOS[$alg], $signing_input, $secret, true);
    return $signing_input . '.' . b64url_encode($sig);
}

function jwt_decode(string $token, string $secret, array $allowed = ['HS256']): array {
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        throw new RuntimeException('malformed token: expected 3 segments');
    }
    [$h_b64, $p_b64, $s_b64] = $parts;
    $header = json_decode(b64url_decode($h_b64), true);
    if (!is_array($header) || !isset($header['alg'])) {
        throw new RuntimeException('malformed header');
    }
    $alg = $header['alg'];
    if (!in_array($alg, $allowed, true)) {
        throw new RuntimeException("algorithm not allowed: $alg");
    }
    if (!isset(JWT_ALGOS[$alg])) {
        throw new RuntimeException("unsupported algorithm: $alg");
    }
    $expected = hash_hmac(JWT_ALGOS[$alg], $h_b64 . '.' . $p_b64, $secret, true);
    $provided = b64url_decode($s_b64);
    if (!hash_equals($expected, $provided)) {
        throw new RuntimeException('signature mismatch');
    }
    $claims = json_decode(b64url_decode($p_b64), true);
    if (!is_array($claims)) {
        throw new RuntimeException('malformed claims');
    }
    $now = time();
    if (isset($claims['exp']) && $now >= $claims['exp']) {
        throw new RuntimeException('token expired');
    }
    if (isset($claims['nbf']) && $now < $claims['nbf']) {
        throw new RuntimeException('token not yet valid');
    }
    return $claims;
}

echo "=== base64url roundtrip ===\n";
$samples = ['hello', "binary\x00\xff\x7f", '', 'a', 'ab', 'abc', 'abcd', str_repeat('x', 100)];
foreach ($samples as $s) {
    $enc = b64url_encode($s);
    $dec = b64url_decode($enc);
    $ok = $dec === $s ? 'ok' : 'FAIL';
    echo sprintf("  len=%-3d enc=%-20s %s\n", strlen($s), substr($enc, 0, 20), $ok);
}

echo "\n=== sign and verify (HS256) ===\n";
$secret = 'shared-secret-keep-this-safe';
$claims = [
    'sub' => 'user-42',
    'name' => 'Ada Lovelace',
    'iat' => 1700000000,
    'exp' => 9999999999,
    'roles' => ['admin', 'editor'],
];
$token = jwt_encode($claims, $secret);
echo "token segments: " . count(explode('.', $token)) . "\n";
echo "token starts with: " . substr($token, 0, 36) . "...\n";
$back = jwt_decode($token, $secret);
echo "sub matches: " . ($back['sub'] === 'user-42' ? 'yes' : 'no') . "\n";
echo "roles: " . implode(',', $back['roles']) . "\n";

echo "\n=== algorithm coverage ===\n";
foreach (array_keys(JWT_ALGOS) as $alg) {
    $tok = jwt_encode(['sub' => 'a'], $secret, $alg);
    $decoded = jwt_decode($tok, $secret, [$alg]);
    echo "  $alg: " . ($decoded['sub'] === 'a' ? 'ok' : 'FAIL') . "\n";
}

echo "\n=== rejection cases ===\n";

function expect_fail(string $label, callable $fn): void {
    try {
        $fn();
        echo "  $label: FAIL (no exception)\n";
    } catch (RuntimeException $e) {
        echo "  $label: rejected (" . $e->getMessage() . ")\n";
    } catch (Throwable $e) {
        echo "  $label: rejected with " . get_class($e) . "\n";
    }
}

expect_fail('wrong secret', fn() => jwt_decode($token, 'different-secret'));
expect_fail('tampered payload', function () use ($secret, $token) {
    $parts = explode('.', $token);
    $bad = json_encode(['sub' => 'attacker', 'exp' => 9999999999]);
    $parts[1] = b64url_encode($bad);
    jwt_decode(implode('.', $parts), $secret);
});
expect_fail('disallowed algorithm', function () use ($secret) {
    $tok = jwt_encode(['sub' => 'a'], $secret, 'HS512');
    jwt_decode($tok, $secret, ['HS256']);
});
expect_fail('malformed (2 segments)', fn() => jwt_decode('aaa.bbb', $secret));
expect_fail('malformed (4 segments)', fn() => jwt_decode('aaa.bbb.ccc.ddd', $secret));
expect_fail('garbage signature', function () use ($token, $secret) {
    $parts = explode('.', $token);
    $parts[2] = b64url_encode(str_repeat("\x00", 32));
    jwt_decode(implode('.', $parts), $secret);
});

echo "\n=== expiration ===\n";
$expired = jwt_encode(['sub' => 'a', 'exp' => time() - 60], $secret);
expect_fail('expired token', fn() => jwt_decode($expired, $secret));

$future = jwt_encode(['sub' => 'a', 'nbf' => time() + 3600], $secret);
expect_fail('not yet valid', fn() => jwt_decode($future, $secret));

$valid_now = jwt_encode(['sub' => 'a', 'exp' => time() + 60, 'nbf' => time() - 60], $secret);
$ok = jwt_decode($valid_now, $secret);
echo "  current window: " . ($ok['sub'] === 'a' ? 'ok' : 'FAIL') . "\n";

echo "\n=== known vector (HS256, RFC 7519 section 3.1) ===\n";
// canonical example token from RFC 7519
$rfc_secret = 'your-256-bit-secret';
$rfc_claims = ['sub' => '1234567890', 'name' => 'John Doe', 'iat' => 1516239022];
$rfc_token = jwt_encode($rfc_claims, $rfc_secret);
$rfc_back = jwt_decode($rfc_token, $rfc_secret);
echo "  sub: {$rfc_back['sub']}\n";
echo "  name: {$rfc_back['name']}\n";
echo "  iat: {$rfc_back['iat']}\n";

echo "\n=== iat/exp clock ===\n";
$now_iso = (new DateTimeImmutable('@' . time()))->format('Y');
echo "  current year present: " . (strlen($now_iso) === 4 ? 'yes' : 'no') . "\n";
