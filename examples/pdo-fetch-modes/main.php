<?php
// covers: PDO FETCH_KEY_PAIR, FETCH_GROUP, FETCH_UNIQUE, FETCH_COLUMN, FETCH_FUNC,
//   FETCH_OBJ + iteration, prepared statement reuse with rebind

$db = new PDO('sqlite::memory:');
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$db->exec("CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    name TEXT NOT NULL,
    weight INTEGER NOT NULL
)");

$stmt = $db->prepare("INSERT INTO events (category, name, weight) VALUES (?, ?, ?)");
foreach ([
    ['error',   'disk-full',     5],
    ['error',   'timeout',       3],
    ['warn',    'slow',          1],
    ['warn',    'retry',         2],
    ['info',    'startup',       0],
    ['info',    'shutdown',      0],
    ['debug',   'connect',       0],
] as $row) {
    $stmt->execute($row);
}

echo "=== FETCH_KEY_PAIR (2 cols: key => value) ===\n";
$weights = $db->query("SELECT name, weight FROM events ORDER BY id")
              ->fetchAll(PDO::FETCH_KEY_PAIR);
foreach ($weights as $k => $v) echo "  $k => $v\n";

echo "\n=== FETCH_COLUMN ===\n";
$names = $db->query("SELECT name FROM events WHERE category = 'error' ORDER BY id")
            ->fetchAll(PDO::FETCH_COLUMN);
echo "names: " . implode(',', $names) . "\n";

echo "\n=== FETCH_GROUP (1st col as group key) ===\n";
$by_cat = $db->query("SELECT category, name FROM events ORDER BY name")
             ->fetchAll(PDO::FETCH_COLUMN | PDO::FETCH_GROUP);
foreach ($by_cat as $cat => $names) echo "  $cat: " . implode(',', $names) . "\n";

echo "\n=== FETCH_UNIQUE (1st col deduplicated key) ===\n";
$by_name = $db->query("SELECT name, category, weight FROM events ORDER BY id")
              ->fetchAll(PDO::FETCH_ASSOC | PDO::FETCH_UNIQUE);
ksort($by_name);
foreach ($by_name as $k => $v) echo "  $k: cat=$v[category] w=$v[weight]\n";

echo "\n=== FETCH_OBJ ===\n";
$q = $db->query("SELECT name, weight FROM events WHERE category = 'warn'");
foreach ($q->fetchAll(PDO::FETCH_OBJ) as $row) {
    echo "  obj name=$row->name weight=$row->weight\n";
}

echo "\n=== FETCH_NUM iteration ===\n";
$q = $db->query("SELECT name, weight FROM events LIMIT 2");
foreach ($q->fetchAll(PDO::FETCH_NUM) as $row) {
    echo "  [0]=$row[0] [1]=$row[1]\n";
}

echo "\n=== reusing a prepared statement with different params ===\n";
$pick = $db->prepare("SELECT GROUP_CONCAT(name, ',') AS list FROM events WHERE category = ?");
foreach (['error', 'warn', 'info'] as $cat) {
    $pick->execute([$cat]);
    $list = $pick->fetchColumn();
    echo "  $cat: $list\n";
}

echo "\n=== FETCH_BOTH (numeric + string keys) ===\n";
$q = $db->query("SELECT name, weight FROM events LIMIT 1");
$row = $q->fetch(PDO::FETCH_BOTH);
echo "by name: $row[name], by index: $row[0]\n";
echo "by weight: $row[weight], by index: $row[1]\n";

echo "\n=== count rows via aggregate, COUNT(*) ===\n";
$count = $db->query("SELECT COUNT(*) FROM events WHERE weight > 0")->fetchColumn();
echo "weighted: $count\n";

echo "\n=== query() returning iterable directly ===\n";
$lines = [];
foreach ($db->query("SELECT name FROM events WHERE category = 'info' ORDER BY name") as $r) {
    $lines[] = $r['name'] ?? $r[0];
}
echo implode(',', $lines) . "\n";

echo "\n=== fetch single row then move on ===\n";
$q = $db->query("SELECT name FROM events ORDER BY id");
echo "first: " . $q->fetch()['name'] . "\n";
echo "second: " . $q->fetch()['name'] . "\n";

echo "\ndone\n";
