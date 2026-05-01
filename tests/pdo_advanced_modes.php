<?php

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE orders (id INTEGER PRIMARY KEY, user TEXT, total INTEGER)');
$pdo->exec("INSERT INTO orders (user, total) VALUES ('alice', 100), ('bob', 50), ('alice', 75), ('bob', 25)");

// FETCH_GROUP groups rows by the first column
$grouped = $pdo->query('SELECT user, total FROM orders ORDER BY id')->fetchAll(PDO::FETCH_GROUP | PDO::FETCH_ASSOC);
foreach ($grouped as $user => $rows) {
    echo "$user has " . count($rows) . " orders, total=";
    $sum = 0;
    foreach ($rows as $r) $sum += $r['total'];
    echo "$sum\n";
}

// FETCH_UNIQUE: first column is key, only one row kept per key (last wins)
$pdo->exec('CREATE TABLE settings (key TEXT, value TEXT)');
$pdo->exec("INSERT INTO settings VALUES ('a', '1'), ('b', '2'), ('c', '3')");
$by_key = $pdo->query('SELECT key, value FROM settings')->fetchAll(PDO::FETCH_UNIQUE | PDO::FETCH_ASSOC);
foreach ($by_key as $k => $v) echo "$k:" . $v['value'] . " ";
echo "\n";

// PDO constructor options array honored
$pdo2 = new PDO('sqlite::memory:', null, null, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
$pdo2->exec('CREATE TABLE x (n INTEGER)');
$pdo2->exec('INSERT INTO x VALUES (1), (2)');
$rows = $pdo2->query('SELECT n FROM x')->fetchAll();
echo array_keys($rows[0])[0] . "\n"; // should be 'n', not 0

// getAttribute
echo $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) . "\n";
echo $pdo->getAttribute(PDO::ATTR_ERRMODE) . "\n";
echo $pdo->getAttribute(PDO::ATTR_DEFAULT_FETCH_MODE) . "\n";

// columnCount
$stmt = $pdo->prepare('SELECT id, user, total FROM orders WHERE id = ?');
$stmt->execute([1]);
echo $stmt->columnCount() . "\n";

// scalar query
echo $pdo->query("SELECT 'literal'")->fetchColumn() . "\n";
echo $pdo->query('SELECT COUNT(*) FROM orders')->fetchColumn() . "\n";
