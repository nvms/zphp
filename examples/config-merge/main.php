<?php
// covers: array_replace_recursive, array_intersect_key, array_diff_key,
//   array_merge_recursive, array_key_exists, is_array, array_walk_recursive,
//   json_encode, array_map, array_keys, array_values, compact, extract,
//   ksort, count, implode, sprintf

$defaults = [
    'database' => [
        'host' => 'localhost',
        'port' => 3306,
        'name' => 'myapp',
        'options' => [
            'charset' => 'utf8mb4',
            'timeout' => 30,
            'retries' => 3,
        ],
    ],
    'cache' => [
        'driver' => 'file',
        'ttl' => 3600,
        'prefix' => 'app_',
    ],
    'logging' => [
        'level' => 'warning',
        'file' => '/var/log/app.log',
        'max_size' => 10485760,
    ],
];

$environment = [
    'database' => [
        'host' => 'db.prod.example.com',
        'port' => 5432,
        'options' => [
            'timeout' => 5,
            'ssl' => true,
        ],
    ],
    'cache' => [
        'driver' => 'redis',
        'ttl' => 7200,
    ],
    'logging' => [
        'level' => 'error',
    ],
];

$overrides = [
    'database' => [
        'options' => [
            'retries' => 5,
        ],
    ],
    'debug' => true,
];

// array_replace_recursive: deep merge configs
$config = array_replace_recursive($defaults, $environment, $overrides);

echo "=== merged config ===\n";

function printConfig(array $config, string $prefix = ''): void
{
    ksort($config);
    foreach ($config as $key => $value) {
        $path = $prefix ? "$prefix.$key" : $key;
        if (is_array($value)) {
            printConfig($value, $path);
        } else {
            $display = is_bool($value) ? ($value ? 'true' : 'false') : (string)$value;
            echo sprintf("  %-40s %s\n", $path, $display);
        }
    }
}

printConfig($config);

// array_intersect_key: extract only database config
$dbKeys = array_flip(['database']);
$dbOnly = array_intersect_key($config, $dbKeys);
echo "\n=== database config only ===\n";
printConfig($dbOnly);

// array_diff_key: everything except database
$rest = array_diff_key($config, $dbKeys);
echo "\n=== non-database config ===\n";
printConfig($rest);

// compact/extract
$host = $config['database']['host'];
$port = $config['database']['port'];
$driver = $config['cache']['driver'];
$level = $config['logging']['level'];

$summary = compact('host', 'port', 'driver', 'level');
echo "\n=== compact ===\n";
foreach ($summary as $k => $v) {
    echo "  $k = $v\n";
}

// extract into scope
$data = ['app_name' => 'MyApp', 'version' => '2.1.0', 'env' => 'production'];
extract($data);
echo "\n=== extract ===\n";
echo "  $app_name v$version ($env)\n";

// array_walk_recursive: collect all leaf values
$leaves = [];
array_walk_recursive($config, function ($value) use (&$leaves) {
    $leaves[] = $value;
});
echo "\n=== leaf count: " . count($leaves) . " ===\n";

// array_merge_recursive: merge arrays (different semantics than replace)
$a = ['tags' => ['php', 'web'], 'meta' => ['author' => 'alice']];
$b = ['tags' => ['api', 'rest'], 'meta' => ['author' => 'bob', 'year' => 2024]];
$merged = array_merge_recursive($a, $b);
echo "\n=== merge_recursive ===\n";
echo "  tags: " . implode(', ', $merged['tags']) . "\n";
echo "  author: " . implode(', ', $merged['meta']['author']) . "\n";
echo "  year: " . $merged['meta']['year'] . "\n";

// verify key preservation through operations
$original_keys = array_keys($defaults);
$merged_keys = array_keys($config);
sort($original_keys);
sort($merged_keys);
echo "\n=== key preservation ===\n";
echo "  defaults: " . implode(', ', $original_keys) . "\n";
echo "  merged: " . implode(', ', $merged_keys) . "\n";
echo "  new keys: " . implode(', ', array_diff($merged_keys, $original_keys)) . "\n";
