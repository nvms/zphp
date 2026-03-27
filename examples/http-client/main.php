<?php
// covers: parse_url, http_build_query, urlencode, urldecode, json_encode, json_decode,
//         array_merge, array_key_exists, implode, explode, strtolower, strtoupper,
//         substr, strpos, str_contains, str_starts_with, str_ends_with, trim, rtrim,
//         sprintf, preg_match, array_map, array_filter, array_keys, array_values,
//         str_replace, header parsing, multiline string building

// --- URL builder ---

function buildUrl($base, $path, $params = []) {
    $url = rtrim($base, '/') . '/' . ltrim($path, '/');
    if (!empty($params)) {
        $url .= '?' . http_build_query($params);
    }
    return $url;
}

$url = buildUrl('https://api.example.com/', '/users', ['page' => 2, 'limit' => 10, 'q' => 'hello world']);
echo "URL: $url\n";

$parts = parse_url($url);
echo "scheme: {$parts['scheme']}\n";
echo "host: {$parts['host']}\n";
echo "path: {$parts['path']}\n";
echo "query: {$parts['query']}\n";

// --- query string round-trip ---

parse_str($parts['query'], $queryParams);
echo "page: {$queryParams['page']}\n";
echo "limit: {$queryParams['limit']}\n";
echo "q: {$queryParams['q']}\n";

$rebuilt = http_build_query($queryParams);
echo "rebuilt: $rebuilt\n";

// --- URL encoding ---

$special = "name=John Doe&city=New York&emoji=<>";
$encoded = urlencode($special);
echo "encoded: $encoded\n";
$decoded = urldecode($encoded);
echo "decoded: $decoded\n";
echo "roundtrip: " . ($decoded === $special ? "yes" : "no") . "\n";

// --- header parsing ---

function parseHeaders($raw) {
    $headers = [];
    $lines = explode("\n", trim($raw));
    foreach ($lines as $line) {
        $line = trim($line);
        if (empty($line)) continue;
        $pos = strpos($line, ':');
        if ($pos === false) continue;
        $key = strtolower(trim(substr($line, 0, $pos)));
        $value = trim(substr($line, $pos + 1));
        $headers[$key] = $value;
    }
    return $headers;
}

$rawHeaders = "Content-Type: application/json\nX-Request-ID: abc-123\nCache-Control: no-cache, no-store\nAuthorization: Bearer token123\nX-Rate-Limit: 100";

$headers = parseHeaders($rawHeaders);
echo "content-type: {$headers['content-type']}\n";
echo "x-request-id: {$headers['x-request-id']}\n";
echo "cache-control: {$headers['cache-control']}\n";

// check header existence
echo "has auth: " . (array_key_exists('authorization', $headers) ? "yes" : "no") . "\n";
echo "has accept: " . (array_key_exists('accept', $headers) ? "yes" : "no") . "\n";

// --- JSON request/response simulation ---

function buildRequest($method, $url, $headers = [], $body = null) {
    $request = [
        'method' => strtoupper($method),
        'url' => $url,
        'headers' => $headers,
    ];
    if ($body !== null) {
        if (is_array($body)) {
            $request['body'] = json_encode($body);
            $request['headers']['Content-Type'] = 'application/json';
        } else {
            $request['body'] = (string)$body;
        }
    }
    return $request;
}

$req = buildRequest('post', 'https://api.example.com/users', [
    'Authorization' => 'Bearer secret',
    'Accept' => 'application/json',
], ['name' => 'Alice', 'email' => 'alice@example.com', 'age' => 30]);

echo "method: {$req['method']}\n";
echo "body: {$req['body']}\n";
echo "content-type: {$req['headers']['Content-Type']}\n";

// --- JSON response parsing ---

$responseJson = '{"status":200,"data":{"users":[{"id":1,"name":"Alice","active":true},{"id":2,"name":"Bob","active":false},{"id":3,"name":"Charlie","active":true}]},"meta":{"total":3,"page":1}}';

$response = json_decode($responseJson, true);
echo "status: {$response['status']}\n";
echo "total users: {$response['meta']['total']}\n";

$users = $response['data']['users'];
$activeUsers = array_filter($users, function($u) { return $u['active']; });
$names = array_map(function($u) { return $u['name']; }, array_values($activeUsers));
echo "active: " . implode(', ', $names) . "\n";

// --- URL path manipulation ---

function joinPath(...$parts) {
    $result = '';
    foreach ($parts as $part) {
        $part = trim($part, '/');
        if ($part !== '') {
            $result .= '/' . $part;
        }
    }
    return $result;
}

echo "path: " . joinPath('/api/', '/v2/', 'users/', '/123/') . "\n";

// extract path segments
$path = '/api/v2/users/123/posts';
$segments = array_filter(explode('/', $path), function($s) { return $s !== ''; });
$segments = array_values($segments);
echo "segments: " . count($segments) . "\n";
echo "resource: {$segments[2]}\n";
echo "id: {$segments[3]}\n";

// --- content type parsing ---

function parseContentType($header) {
    $parts = explode(';', $header);
    $type = trim($parts[0]);
    $params = [];
    for ($i = 1; $i < count($parts); $i++) {
        $kv = explode('=', trim($parts[$i]), 2);
        if (count($kv) === 2) {
            $params[trim($kv[0])] = trim($kv[1]);
        }
    }
    return ['type' => $type, 'params' => $params];
}

$ct = parseContentType('text/html; charset=utf-8; boundary=something');
echo "type: {$ct['type']}\n";
echo "charset: {$ct['params']['charset']}\n";
echo "boundary: {$ct['params']['boundary']}\n";

// --- basic auth encoding ---

$credentials = base64_encode('user:password123');
echo "auth: Basic $credentials\n";
$decoded = base64_decode($credentials);
echo "credentials: $decoded\n";

// --- cookie parsing ---

function parseCookies($cookieString) {
    $cookies = [];
    $pairs = explode(';', $cookieString);
    foreach ($pairs as $pair) {
        $kv = explode('=', trim($pair), 2);
        if (count($kv) === 2) {
            $cookies[trim($kv[0])] = urldecode(trim($kv[1]));
        }
    }
    return $cookies;
}

$cookies = parseCookies('session=abc123; theme=dark; lang=en; name=John%20Doe');
echo "session: {$cookies['session']}\n";
echo "theme: {$cookies['theme']}\n";
echo "name: {$cookies['name']}\n";

// --- query string building with nested arrays ---

$params = [
    'filter' => 'active',
    'sort' => 'name',
    'fields' => 'id,name,email',
];
$qs = http_build_query($params);
echo "query: $qs\n";

// verify round-trip
parse_str($qs, $parsed);
echo "filter: {$parsed['filter']}\n";
echo "fields: {$parsed['fields']}\n";
