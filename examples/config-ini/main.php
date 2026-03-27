<?php
// covers: array_merge_recursive, array_walk_recursive, array_replace_recursive, str_contains, str_starts_with, trim, explode, is_numeric, array_key_exists, strtolower, preg_match, array_map, array_filter, array_values, compact, extract

// --- INI parser (manual since parse_ini_string may not be available) ---

function parseIni(string $content): array {
    $result = [];
    $currentSection = '';
    $lines = explode("\n", $content);

    foreach ($lines as $line) {
        $line = trim($line);

        if ($line === '' || str_starts_with($line, ';') || str_starts_with($line, '#')) {
            continue;
        }

        if (preg_match('/^\[(.+)\]$/', $line, $matches)) {
            $currentSection = $matches[1];
            if (!array_key_exists($currentSection, $result)) {
                $result[$currentSection] = [];
            }
            continue;
        }

        if (str_contains($line, '=')) {
            $parts = explode('=', $line, 2);
            $key = trim($parts[0]);
            $value = trim($parts[1]);

            // strip quotes
            if (strlen($value) >= 2) {
                $first = $value[0];
                $last = $value[strlen($value) - 1];
                if (($first === '"' && $last === '"') || ($first === "'" && $last === "'")) {
                    $value = substr($value, 1, strlen($value) - 2);
                }
            }

            // type coercion
            if (strtolower($value) === 'true' || strtolower($value) === 'on' || strtolower($value) === 'yes') {
                $value = true;
            } elseif (strtolower($value) === 'false' || strtolower($value) === 'off' || strtolower($value) === 'no') {
                $value = false;
            } elseif (strtolower($value) === 'null' || strtolower($value) === 'none') {
                $value = null;
            } elseif (is_numeric($value)) {
                $value = str_contains($value, '.') ? (float)$value : (int)$value;
            }

            if ($currentSection !== '') {
                $result[$currentSection][$key] = $value;
            } else {
                $result[$key] = $value;
            }
        }
    }

    return $result;
}

$ini = <<<'INI'
; global settings
app_name = "My Application"
debug = true
version = 2.1

[database]
host = localhost
port = 5432
name = mydb
ssl = on
max_connections = 100

[cache]
driver = redis
ttl = 3600
enabled = yes

[logging]
level = info
file = /var/log/app.log
rotate = false
INI;

$config = parseIni($ini);

echo "App name: " . $config['app_name'] . "\n";
echo "Debug: " . ($config['debug'] ? 'true' : 'false') . "\n";
echo "Version: " . $config['version'] . "\n";

echo "\nDatabase:\n";
echo "  host: " . $config['database']['host'] . "\n";
echo "  port: " . $config['database']['port'] . "\n";
echo "  ssl: " . ($config['database']['ssl'] ? 'true' : 'false') . "\n";
echo "  max_connections: " . $config['database']['max_connections'] . "\n";

echo "\nCache:\n";
echo "  driver: " . $config['cache']['driver'] . "\n";
echo "  ttl: " . $config['cache']['ttl'] . "\n";
echo "  enabled: " . ($config['cache']['enabled'] ? 'true' : 'false') . "\n";

echo "\nLogging:\n";
echo "  level: " . $config['logging']['level'] . "\n";
echo "  rotate: " . ($config['logging']['rotate'] ? 'true' : 'false') . "\n";

// --- deep merge configs (simulating environment overrides) ---

function deepMerge(array $base, array $override): array {
    foreach ($override as $key => $value) {
        if (is_array($value) && array_key_exists($key, $base) && is_array($base[$key])) {
            $base[$key] = deepMerge($base[$key], $value);
        } else {
            $base[$key] = $value;
        }
    }
    return $base;
}

$envOverrides = [
    'debug' => false,
    'database' => [
        'host' => 'db.production.local',
        'port' => 5433,
        'ssl' => true,
    ],
    'cache' => [
        'ttl' => 7200,
    ],
];

$merged = deepMerge($config, $envOverrides);

echo "\nAfter env overrides:\n";
echo "  debug: " . ($merged['debug'] ? 'true' : 'false') . "\n";
echo "  db.host: " . $merged['database']['host'] . "\n";
echo "  db.port: " . $merged['database']['port'] . "\n";
echo "  db.name: " . $merged['database']['name'] . "\n";
echo "  cache.ttl: " . $merged['cache']['ttl'] . "\n";
echo "  cache.driver: " . $merged['cache']['driver'] . "\n";

// --- config path accessor ---

function configGet(array $config, string $path, $default = null) {
    $keys = explode('.', $path);
    $current = $config;
    foreach ($keys as $key) {
        if (!is_array($current) || !array_key_exists($key, $current)) {
            return $default;
        }
        $current = $current[$key];
    }
    return $current;
}

function configSet(array $config, string $path, $value): array {
    $keys = explode('.', $path);
    if (count($keys) === 1) {
        $config[$keys[0]] = $value;
        return $config;
    }
    $key = $keys[0];
    $rest = implode('.', array_slice($keys, 1));
    if (!array_key_exists($key, $config) || !is_array($config[$key])) {
        $config[$key] = [];
    }
    $config[$key] = configSet($config[$key], $rest, $value);
    return $config;
}

echo "\nDot-path access:\n";
echo "  database.host: " . configGet($merged, 'database.host') . "\n";
echo "  cache.driver: " . configGet($merged, 'cache.driver') . "\n";
echo "  missing.key: " . (configGet($merged, 'missing.key', 'default') ?? 'null') . "\n";

$merged = configSet($merged, 'database.pool_size', 25);
$merged = configSet($merged, 'new.nested.value', 'created');
echo "  database.pool_size: " . configGet($merged, 'database.pool_size') . "\n";
echo "  new.nested.value: " . configGet($merged, 'new.nested.value') . "\n";

// --- config validation ---

function validateConfig(array $config, array $schema): array {
    $errors = [];
    foreach ($schema as $path => $rules) {
        $value = configGet($config, $path);
        $parts = explode('|', $rules);
        foreach ($parts as $rule) {
            $rule = trim($rule);
            if ($rule === 'required' && $value === null) {
                $errors[] = "$path is required";
            } elseif (str_starts_with($rule, 'type:')) {
                $expectedType = substr($rule, 5);
                if ($value !== null) {
                    $actualType = gettype($value);
                    if ($actualType !== $expectedType) {
                        $errors[] = "$path must be $expectedType, got $actualType";
                    }
                }
            } elseif (str_starts_with($rule, 'min:')) {
                $min = (int)substr($rule, 4);
                if (is_int($value) && $value < $min) {
                    $errors[] = "$path must be >= $min";
                }
            } elseif (str_starts_with($rule, 'max:')) {
                $max = (int)substr($rule, 4);
                if (is_int($value) && $value > $max) {
                    $errors[] = "$path must be <= $max";
                }
            } elseif (str_starts_with($rule, 'in:')) {
                $allowed = explode(',', substr($rule, 3));
                if ($value !== null && !in_array((string)$value, $allowed)) {
                    $errors[] = "$path must be one of: " . implode(', ', $allowed);
                }
            }
        }
    }
    return $errors;
}

$schema = [
    'app_name' => 'required|type:string',
    'database.host' => 'required|type:string',
    'database.port' => 'required|type:integer|min:1|max:65535',
    'cache.driver' => 'required|in:redis,memcached,file',
    'cache.ttl' => 'required|type:integer|min:0',
    'logging.level' => 'required|in:debug,info,warning,error',
];

$errors = validateConfig($merged, $schema);
echo "\nValidation:\n";
if (empty($errors)) {
    echo "  All checks passed\n";
} else {
    foreach ($errors as $err) {
        echo "  ERROR: $err\n";
    }
}

// --- test with bad config ---
$badConfig = deepMerge($merged, [
    'database' => ['port' => 99999],
    'cache' => ['driver' => 'dynamodb'],
    'logging' => ['level' => 'trace'],
]);

$badErrors = validateConfig($badConfig, $schema);
echo "\nBad config errors:\n";
foreach ($badErrors as $err) {
    echo "  $err\n";
}

// --- compact/extract ---

$host = 'localhost';
$port = 5432;
$name = 'testdb';
$packed = compact('host', 'port', 'name');
echo "\nCompact: host=" . $packed['host'] . " port=" . $packed['port'] . " name=" . $packed['name'] . "\n";

extract($packed);
echo "Extract: $host:$port/$name\n";
