<?php
// covers: parse_url, parse_str, http_build_query, urlencode, urldecode,
//   rawurlencode, rawurldecode, quoted_printable_encode, quoted_printable_decode,
//   base64_encode, base64_decode, array auto-vivification, string interpolation

// --- parse_url ---
echo "=== parse_url ===\n";
$url = "https://user:pass@example.com:8443/api/v2/users?sort=name&limit=10#results";
$parts = parse_url($url);
echo "scheme: {$parts['scheme']}\n";
echo "host: {$parts['host']}\n";
echo "port: {$parts['port']}\n";
echo "user: {$parts['user']}\n";
echo "pass: {$parts['pass']}\n";
echo "path: {$parts['path']}\n";
echo "query: {$parts['query']}\n";
echo "fragment: {$parts['fragment']}\n";

$simple = parse_url("http://localhost/index.php");
echo "simple host: {$simple['host']}\n";
echo "simple path: {$simple['path']}\n";
echo "has port: " . (isset($simple['port']) ? 'yes' : 'no') . "\n";

// --- parse_str ---
echo "\n=== parse_str ===\n";
parse_str("name=John+Doe&age=30&tags[]=php&tags[]=zig", $params);
echo "name: {$params['name']}\n";
echo "age: {$params['age']}\n";

parse_str("color=red&size=large&color=blue", $p2);
echo "color: {$p2['color']}\n";

parse_str("key=" . urlencode("hello world&goodbye"), $p3);
echo "encoded value: {$p3['key']}\n";

// empty string
parse_str("", $empty);
echo "empty count: " . count($empty) . "\n";

// --- http_build_query ---
echo "\n=== http_build_query ===\n";
$data = ['name' => 'Jane', 'city' => 'New York', 'active' => 1];
$qs = http_build_query($data);
echo "basic: $qs\n";

parse_str($qs, $roundtrip);
echo "roundtrip name: {$roundtrip['name']}\n";
echo "roundtrip city: {$roundtrip['city']}\n";

$nested = ['filter' => ['status' => 'open', 'priority' => 'high']];
$nested_qs = http_build_query($nested);
echo "nested: $nested_qs\n";

// --- URL encoding ---
echo "\n=== url encoding ===\n";
$raw = "hello world & goodbye/friend";
echo "urlencode: " . urlencode($raw) . "\n";
echo "urldecode: " . urldecode(urlencode($raw)) . "\n";
echo "rawurlencode: " . rawurlencode($raw) . "\n";
echo "rawurldecode: " . rawurldecode(rawurlencode($raw)) . "\n";

echo "space urlencode: " . urlencode("a b") . "\n";
echo "space rawurlencode: " . rawurlencode("a b") . "\n";

$special = "key=val&other=1+2";
echo "double encode: " . urlencode($special) . "\n";
echo "double decode: " . urldecode(urlencode($special)) . "\n";

// --- quoted printable ---
echo "\n=== quoted printable ===\n";
$text = "Subject: Hello World\r\nThis line is fairly short.";
$encoded = quoted_printable_encode($text);
echo "qp contains =0D=0A: " . (str_contains($encoded, "=0D=0A") ? 'yes' : 'no') . "\n";
$decoded = quoted_printable_decode($encoded);
echo "qp roundtrip: " . ($decoded === $text ? 'yes' : 'no') . "\n";

$long = str_repeat("A", 100);
$qp_long = quoted_printable_encode($long);
echo "long line wrapped: " . (str_contains($qp_long, "=\r\n") ? 'yes' : 'no') . "\n";

// --- URL builder pattern ---
echo "\n=== url builder ===\n";
function buildUrl($base, $path, $params = []) {
    $parts = parse_url($base);
    $scheme = $parts['scheme'] ?? 'https';
    $host = $parts['host'] ?? 'localhost';
    $port = isset($parts['port']) ? ":{$parts['port']}" : '';
    $basePath = rtrim($parts['path'] ?? '', '/');

    $url = "{$scheme}://{$host}{$port}{$basePath}/{$path}";
    if (!empty($params)) {
        $url .= '?' . http_build_query($params);
    }
    return $url;
}

echo buildUrl("https://api.example.com", "users", ['page' => 1, 'limit' => 20]) . "\n";
echo buildUrl("http://localhost:3000/api", "search", ['q' => 'hello world']) . "\n";
echo buildUrl("https://host.com", "simple") . "\n";

// --- base64 with URL-safe variant ---
echo "\n=== base64 url-safe ===\n";
function base64UrlEncode($data) {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function base64UrlDecode($data) {
    $padded = $data . str_repeat('=', (4 - strlen($data) % 4) % 4);
    return base64_decode(strtr($padded, '-_', '+/'));
}

$payload = '{"sub":"1234567890","name":"John","iat":1516239022}';
$encoded = base64UrlEncode($payload);
echo "url-safe b64: $encoded\n";
echo "no plus: " . (str_contains($encoded, '+') ? 'no' : 'yes') . "\n";
echo "no slash: " . (str_contains($encoded, '/') ? 'no' : 'yes') . "\n";
echo "roundtrip: " . (base64UrlDecode($encoded) === $payload ? 'yes' : 'no') . "\n";

echo "\ndone\n";
