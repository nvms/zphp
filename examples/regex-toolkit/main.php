<?php
// covers: preg_grep, preg_last_error, preg_last_error_msg, preg_match,
//   preg_match_all, preg_replace, preg_replace_callback, preg_split,
//   preg_quote, array_keys, array_values, implode, count, sprintf,
//   strtolower, strtoupper, trim, in_array

// preg_grep: filter arrays by pattern
echo "=== preg_grep basics ===\n";
$fruits = ['apple', 'banana', 'apricot', 'cherry', 'avocado', 'blueberry'];
$a_fruits = preg_grep('/^a/', $fruits);
echo "fruits starting with 'a': " . implode(', ', $a_fruits) . "\n";

$numbers = ['12', 'abc', '45.6', 'def', '789', '0x1F'];
$numeric = preg_grep('/^\d+(\.\d+)?$/', $numbers);
echo "numeric values: " . implode(', ', $numeric) . "\n";

// preg_grep with PREG_GREP_INVERT
echo "\n=== preg_grep invert ===\n";
$files = ['readme.md', 'index.php', 'style.css', 'app.js', 'config.php', 'logo.png'];
$non_php = preg_grep('/\.php$/', $files, 1);
echo "non-PHP files: " . implode(', ', $non_php) . "\n";

// preserves keys
echo "preserved keys: " . implode(', ', array_keys($non_php)) . "\n";

// preg_grep with case-insensitive
$mixed = ['Hello', 'WORLD', 'hello', 'World', 'HELLO', 'world'];
$hello_matches = preg_grep('/^hello$/i', $mixed);
echo "case-insensitive 'hello': " . implode(', ', $hello_matches) . "\n";

// preg_last_error
echo "\n=== preg_last_error ===\n";
$result = preg_match('/valid/', 'test string');
echo "after valid match: error=" . preg_last_error() . " msg=" . preg_last_error_msg() . "\n";

// email validation pipeline
echo "\n=== email validation ===\n";
$emails = [
    'user@example.com',
    'invalid-email',
    'admin@server.org',
    'bad@',
    'test.user+tag@domain.co.uk',
    '@nodomain',
    'spaces in@email.com',
];

$valid = preg_grep('/^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/', $emails);
echo "valid emails:\n";
foreach ($valid as $email) {
    echo "  $email\n";
}

$invalid = preg_grep('/^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/', $emails, 1);
echo "invalid emails:\n";
foreach ($invalid as $email) {
    echo "  $email\n";
}

// log level filtering with preg_grep
echo "\n=== log filtering ===\n";
$logs = [
    '[ERROR] Database connection failed',
    '[INFO] Server started on port 8080',
    '[WARNING] Disk usage above 80%',
    '[ERROR] Authentication timeout',
    '[DEBUG] Query executed in 23ms',
    '[INFO] User login: admin',
    '[WARNING] Rate limit approaching',
];

$errors = preg_grep('/^\[ERROR\]/', $logs);
echo "errors (" . count($errors) . "):\n";
foreach ($errors as $log) {
    echo "  $log\n";
}

$warnings_and_errors = preg_grep('/^\[(ERROR|WARNING)\]/', $logs);
echo "warnings+errors (" . count($warnings_and_errors) . "):\n";
foreach ($warnings_and_errors as $log) {
    echo "  $log\n";
}

// combining preg_grep with preg_replace_callback for data extraction
echo "\n=== data extraction pipeline ===\n";
$raw_data = [
    'price: $45.99',
    'name: Widget Pro',
    'price: $12.50',
    'sku: WP-001',
    'price: $199.00',
    'weight: 2.5kg',
];

$price_lines = preg_grep('/price:\s*\$[\d.]+/', $raw_data);
$total = 0.0;
foreach ($price_lines as $line) {
    preg_match('/\$([\d.]+)/', $line, $m);
    $total += (float)$m[1];
}
echo "price lines found: " . count($price_lines) . "\n";
echo sprintf("total: $%.2f\n", $total);

// ip address filtering
echo "\n=== ip filtering ===\n";
$access_log = [
    '192.168.1.1 - GET /api/users',
    '10.0.0.5 - POST /api/login',
    '192.168.1.100 - GET /health',
    '172.16.0.1 - DELETE /api/users/5',
    '10.0.0.5 - GET /api/orders',
    '192.168.1.1 - POST /api/orders',
];

$from_192 = preg_grep('/^192\.168\./', $access_log);
echo "requests from 192.168.x.x: " . count($from_192) . "\n";

// extract unique IPs
$ips = [];
foreach ($access_log as $line) {
    preg_match('/^([\d.]+)/', $line, $m);
    if (!in_array($m[1], $ips)) {
        $ips[] = $m[1];
    }
}
echo "unique IPs: " . implode(', ', $ips) . "\n";

// pattern building with preg_quote
echo "\n=== safe pattern building ===\n";
$search_terms = ['C++', 'C#', '.NET', 'Node.js', 'ASP.NET (Core)'];
foreach ($search_terms as $term) {
    $pattern = '/\b' . preg_quote($term, '/') . '\b/i';
    $text = "I work with $term daily";
    $found = preg_match($pattern, $text);
    echo sprintf("  %-20s found=%s\n", $term, $found ? 'yes' : 'no');
}
