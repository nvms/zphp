<?php
// covers: parse_ini_string, parse_ini_file, array_multisort, array_column, implode, count, is_array, number_format, sprintf, str_pad, arsort, array_keys, array_values, in_array

// --- parse_ini_string: basic ---

$config = "
; database settings
[database]
host = localhost
port = 3306
name = myapp
user = root
password = \"secret123\"

[cache]
enabled = true
ttl = 3600
driver = redis

[app]
debug = false
name = \"My Application\"
version = 1.2
";

echo "=== Config parser ===\n";
$cfg = parse_ini_string($config, true);
echo "DB host: " . $cfg['database']['host'] . "\n";
echo "DB port: " . $cfg['database']['port'] . "\n";
echo "Cache enabled: " . $cfg['cache']['enabled'] . "\n";
echo "Cache TTL: " . $cfg['cache']['ttl'] . "\n";
echo "App name: " . $cfg['app']['name'] . "\n";
echo "Debug: '" . $cfg['app']['debug'] . "'\n";
echo "Sections: " . implode(", ", array_keys($cfg)) . "\n";

// --- parse_ini_string: RAW mode ---

echo "\n=== RAW mode ===\n";
$raw = parse_ini_string($config, true, INI_SCANNER_RAW);
echo "Cache enabled (raw): " . $raw['cache']['enabled'] . "\n";
echo "Debug (raw): " . $raw['app']['debug'] . "\n";

// --- parse_ini_string: TYPED mode ---

echo "\n=== TYPED mode ===\n";
$typed = parse_ini_string($config, true, INI_SCANNER_TYPED);
echo "Cache enabled type: " . gettype($typed['cache']['enabled']) . "\n";
echo "Cache TTL type: " . gettype($typed['cache']['ttl']) . "\n";
echo "Version type: " . gettype($typed['app']['version']) . "\n";

// --- parse_ini_string: array keys ---

echo "\n=== Array keys in INI ===\n";
$ini_arrays = "
extensions[] = pdo
extensions[] = mbstring
extensions[] = json

[routes]
api[users] = /api/users
api[posts] = /api/posts
api[comments] = /api/comments
";
$r = parse_ini_string($ini_arrays, true);
echo "Extensions: " . implode(", ", $r['extensions']) . "\n";
echo "Routes: " . implode(", ", array_values($r['routes']['api'])) . "\n";

// --- parse_ini_string: no sections ---

echo "\n=== Flat (no sections) ===\n";
$flat = parse_ini_string($config, false);
echo "Keys: " . count($flat) . "\n";
echo "host: " . $flat['host'] . "\n";
echo "driver: " . $flat['driver'] . "\n";

// --- parse_ini_file ---

echo "\n=== parse_ini_file ===\n";
$tmpfile = tempnam(sys_get_temp_dir(), 'ini');
file_put_contents($tmpfile, "[server]\nhost = 0.0.0.0\nport = 8080\nworkers = 4\n");
$srv = parse_ini_file($tmpfile, true);
echo "Server host: " . $srv['server']['host'] . "\n";
echo "Server port: " . $srv['server']['port'] . "\n";
echo "Workers: " . $srv['server']['workers'] . "\n";
unlink($tmpfile);

// --- array_multisort: basic ---

echo "\n=== Multisort basic ===\n";
$scores = [85, 92, 78, 95, 88];
$names = ["Eve", "Alice", "Charlie", "Bob", "Diana"];
array_multisort($scores, SORT_DESC, $names);
foreach ($names as $i => $name) {
    echo "  " . str_pad($name, 10) . $scores[$i] . "\n";
}

// --- array_multisort: multi-column ---

echo "\n=== Multisort multi-column ===\n";
$employees = [
    ['name' => 'Alice',   'dept' => 'Engineering', 'salary' => 95000],
    ['name' => 'Bob',     'dept' => 'Marketing',   'salary' => 72000],
    ['name' => 'Charlie', 'dept' => 'Engineering', 'salary' => 110000],
    ['name' => 'Diana',   'dept' => 'Marketing',   'salary' => 68000],
    ['name' => 'Eve',     'dept' => 'Engineering', 'salary' => 88000],
];

$depts = array_column($employees, 'dept');
$salaries = array_column($employees, 'salary');
array_multisort($depts, SORT_ASC, $salaries, SORT_DESC, $employees);

foreach ($employees as $e) {
    echo "  " . str_pad($e['dept'], 14) . str_pad($e['name'], 10) . "$" . number_format($e['salary']) . "\n";
}

// --- array_multisort: string sort ---

echo "\n=== Multisort SORT_STRING ===\n";
$items = ["banana", "Apple", "cherry", "apricot"];
array_multisort($items, SORT_STRING, SORT_ASC);
echo implode(", ", $items) . "\n";

// --- combine: config-driven sorting ---

echo "\n=== Config-driven sort ===\n";
$sort_config = "
[sort]
field = salary
direction = desc
";
$sc = parse_ini_string($sort_config, true);
$field = $sc['sort']['field'];
$dir = $sc['sort']['direction'];

$data = [
    ['name' => 'Alice', 'salary' => 95000],
    ['name' => 'Bob',   'salary' => 72000],
    ['name' => 'Eve',   'salary' => 88000],
];

$sort_col = array_column($data, $field);
$sort_flag = ($dir === 'desc') ? SORT_DESC : SORT_ASC;
array_multisort($sort_col, $sort_flag, $data);

foreach ($data as $row) {
    echo "  " . $row['name'] . ": $" . number_format($row['salary']) . "\n";
}
