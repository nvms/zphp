<?php
// covers: parse_url, http_build_query, urlencode/urldecode, rawurlencode/decode,
//   parse_str, query-string round-trips, URL component recomposition

echo "=== parse_url anatomy ===\n";
$urls = [
    'https://user:pass@example.com:8080/path/to/page?a=1&b=2#frag',
    'http://example.com/',
    'mailto:alice@example.com',
    'tel:+1-555-0123',
    'redis://:secret@127.0.0.1:6379/2',
    '/relative/path?x=1',
    '//cdn.example.com/asset.js',
    'wss://stream.example.com/ws',
];
foreach ($urls as $u) {
    $parts = parse_url($u);
    echo "url: $u\n";
    if (is_array($parts)) {
        foreach (['scheme','host','port','user','pass','path','query','fragment'] as $k) {
            if (isset($parts[$k])) echo "  $k: " . $parts[$k] . "\n";
        }
    } else {
        echo "  (failed)\n";
    }
}

echo "\n=== parse_url with component selector ===\n";
$u = 'https://example.com:8080/p?x=1';
echo "PHP_URL_HOST: " . parse_url($u, PHP_URL_HOST) . "\n";
echo "PHP_URL_PORT: " . parse_url($u, PHP_URL_PORT) . "\n";
echo "PHP_URL_QUERY: " . parse_url($u, PHP_URL_QUERY) . "\n";
echo "PHP_URL_PATH: " . parse_url($u, PHP_URL_PATH) . "\n";

echo "\n=== http_build_query ===\n";
$data = [
    'name' => 'Alice & Bob',
    'role' => 'admin',
    'tags' => ['a', 'b', 'c'],
    'meta' => ['ip' => '203.0.113.1', 'lang' => 'en-US'],
    'active' => true,
];
echo "default sep: " . http_build_query($data) . "\n";
echo "custom sep: " . http_build_query($data, '', '|') . "\n";
echo "PHP_QUERY_RFC3986: " . http_build_query($data, '', '&', PHP_QUERY_RFC3986) . "\n";
echo "PHP_QUERY_RFC1738: " . http_build_query($data, '', '&', PHP_QUERY_RFC1738) . "\n";

echo "\n=== urlencode vs rawurlencode ===\n";
$cases = ['hello world', 'a+b', 'a/b', 'café', 'a&b=c'];
foreach ($cases as $c) {
    echo sprintf("  '%s' -> url:'%s' raw:'%s'\n", $c, urlencode($c), rawurlencode($c));
}

echo "\n=== round-trip through urlencode ===\n";
foreach ($cases as $c) {
    $enc = urlencode($c);
    $dec = urldecode($enc);
    echo sprintf("  match '%s' === '%s': %s\n", $c, $dec, $c === $dec ? "yes" : "no");
}

echo "\n=== parse_str ===\n";
$qs = 'name=Alice&role=admin&tags[]=a&tags[]=b&meta[ip]=1.2.3.4';
parse_str($qs, $out);
echo "name: " . $out['name'] . "\n";
echo "tags count: " . count($out['tags']) . "\n";
echo "tags[0]: " . $out['tags'][0] . "\n";
echo "meta.ip: " . $out['meta']['ip'] . "\n";

echo "\n=== query string round-trip ===\n";
$original = [
    'q' => 'php + zig',
    'page' => 2,
    'filters' => ['lang' => 'en', 'sort' => 'date desc'],
];
$qs = http_build_query($original);
parse_str($qs, $parsed);
echo "round-trip ok: " . ($parsed['q'] === $original['q'] ? "yes" : "no") . "\n";
echo "nested ok: " . ($parsed['filters']['sort'] === $original['filters']['sort'] ? "yes" : "no") . "\n";

echo "\n=== recompose URL ===\n";
function recompose(string $url): string {
    $p = parse_url($url);
    $scheme = $p['scheme'] ?? 'http';
    $host = $p['host'] ?? '';
    $userinfo = '';
    if (isset($p['user'])) {
        $userinfo = $p['user'];
        if (isset($p['pass'])) $userinfo .= ':' . $p['pass'];
        $userinfo .= '@';
    }
    $port = isset($p['port']) ? ':' . $p['port'] : '';
    $path = $p['path'] ?? '/';
    $query = isset($p['query']) ? '?' . $p['query'] : '';
    $frag = isset($p['fragment']) ? '#' . $p['fragment'] : '';
    return "$scheme://$userinfo$host$port$path$query$frag";
}
$cases = [
    'https://example.com/foo?x=1',
    'http://user@example.com:8080/path#section',
    'https://example.com',
];
foreach ($cases as $u) {
    echo "  '$u' -> '" . recompose($u) . "'\n";
}

echo "\n=== idn-like host normalize ===\n";
echo "lower host: " . strtolower(parse_url('https://EXAMPLE.com/path', PHP_URL_HOST) ?: '') . "\n";
echo "trim trailing slash: " . rtrim(parse_url('https://example.com/path/', PHP_URL_PATH), '/') . "\n";
