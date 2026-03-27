<?php
// covers: vsprintf, preg_quote, preg_replace, preg_match, preg_split,
//   date, gmdate, sprintf, str_pad, strtoupper, array_map, array_filter,
//   array_keys, array_values, implode, count, substr, strpos, json_encode,
//   number_format, microtime, round

// log level constants
$LEVELS = [
    'DEBUG' => 0,
    'INFO' => 1,
    'WARNING' => 2,
    'ERROR' => 3,
    'CRITICAL' => 4,
];

function formatLogLine(string $level, string $message, array $context = []): string
{
    $timestamp = '2024-01-15 10:30:45';
    $padded = str_pad(strtoupper($level), 8);

    if (count($context) > 0) {
        // interpolate {key} placeholders
        foreach ($context as $key => $value) {
            $placeholder = '{' . $key . '}';
            if (is_array($value)) {
                $value = json_encode($value);
            }
            $message = str_replace($placeholder, (string)$value, $message);
        }
    }

    return sprintf("[%s] %s %s", $timestamp, $padded, $message);
}

echo "=== basic log formatting ===\n";
echo formatLogLine('info', 'Application started') . "\n";
echo formatLogLine('warning', 'Disk usage at {percent}%', ['percent' => 85]) . "\n";
echo formatLogLine('error', 'Failed to connect to {host}:{port}', ['host' => 'db.example.com', 'port' => 5432]) . "\n";
echo formatLogLine('debug', 'Query result: {data}', ['data' => ['rows' => 42, 'cached' => true]]) . "\n";

// vsprintf for structured formatting
echo "\n=== vsprintf formatting ===\n";
$formats = [
    "%-20s %5d requests  %6.2f%% success",
    "%-20s %5d requests  %6.2f%% success",
    "%-20s %5d requests  %6.2f%% success",
];
$data = [
    ['/api/users', 15234, 99.82],
    ['/api/orders', 8921, 97.50],
    ['/health', 102400, 100.00],
];
for ($i = 0; $i < count($data); $i++) {
    echo "  " . vsprintf($formats[$i], $data[$i]) . "\n";
}

// preg_quote: safely building patterns from user input
echo "\n=== preg_quote ===\n";
$userInputs = ['file.txt', 'data[0]', 'price ($)', 'a+b=c', 'path/to/file'];
foreach ($userInputs as $input) {
    $quoted = preg_quote($input, '/');
    $pattern = '/^' . $quoted . '$/';
    $matches = preg_match($pattern, $input);
    echo sprintf("  %-15s -> pattern: %-25s match: %s\n", $input, $pattern, $matches ? 'yes' : 'no');
}

// log parsing with regex
echo "\n=== log parsing ===\n";
$logLines = [
    "[2024-01-15 10:30:45] ERROR    Database connection failed: timeout after 30s",
    "[2024-01-15 10:30:46] INFO     Retrying connection (attempt 2/3)",
    "[2024-01-15 10:30:47] WARNING  Connection pool exhausted, queuing requests",
    "[2024-01-15 10:30:48] ERROR    Max retries exceeded for db.prod:5432",
    "[2024-01-15 10:30:49] INFO     Failover to db.backup:5432 successful",
];

$parsed = [];
foreach ($logLines as $line) {
    if (preg_match('/^\[([^\]]+)\]\s+(\w+)\s+(.+)$/', $line, $matches)) {
        $parsed[] = [
            'time' => $matches[1],
            'level' => $matches[2],
            'message' => $matches[3],
        ];
    }
}

$errors = array_filter($parsed, function ($entry) {
    return $entry['level'] === 'ERROR';
});
echo "  total entries: " . count($parsed) . "\n";
echo "  errors: " . count($errors) . "\n";
foreach ($errors as $err) {
    echo "    " . $err['time'] . " - " . $err['message'] . "\n";
}

// number formatting for metrics
echo "\n=== number formatting ===\n";
$metrics = [
    ['name' => 'requests', 'value' => 1234567],
    ['name' => 'bytes_sent', 'value' => 9876543210],
    ['name' => 'avg_latency_ms', 'value' => 12.3456],
    ['name' => 'error_rate', 'value' => 0.0234],
];
foreach ($metrics as $metric) {
    $formatted = number_format($metric['value'], 2, '.', ',');
    echo sprintf("  %-20s %20s\n", $metric['name'], $formatted);
}

// splitting log messages
echo "\n=== preg_split ===\n";
$kvLog = "host=db.prod port=5432 user=admin db=myapp pool_size=10";
$parts = preg_split('/\s+/', $kvLog);
$config = [];
foreach ($parts as $part) {
    $kv = explode('=', $part, 2);
    if (count($kv) === 2) {
        $config[$kv[0]] = $kv[1];
    }
}
foreach ($config as $k => $v) {
    echo "  $k: $v\n";
}

// gmdate with fixed timestamp (avoids timezone differences)
echo "\n=== gmdate ===\n";
$ts = 1705312245; // 2024-01-15 09:50:45 UTC
echo "  utc:   " . gmdate('Y-m-d H:i:s', $ts) . "\n";
echo "  rfc:   " . gmdate('D, d M Y H:i:s', $ts) . " GMT\n";

// round with precision
echo "\n=== round precision ===\n";
$values = [3.14159, 2.71828, 1.41421, 0.57721];
foreach ($values as $v) {
    echo sprintf("  %.5f -> %s (2dp) -> %s (0dp)\n", $v, round($v, 2), round($v, 0));
}
