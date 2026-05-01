<?php

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER)');
$pdo->exec("INSERT INTO items (name, qty) VALUES ('a', 1), ('b', 2), ('c', 3), ('d', 4)");

// foreach over PDOStatement (Iterator)
$stmt = $pdo->prepare('SELECT name, qty FROM items WHERE qty >= ? ORDER BY id');
$stmt->execute([2]);
foreach ($stmt as $r) echo $r['name'] . ":" . $r['qty'] . " ";
echo "\n";

// fetchObject with class name
class Item { public string $name; public int $qty; }
$stmt = $pdo->prepare('SELECT name, qty FROM items WHERE name = ?');
$stmt->execute(['b']);
$obj = $stmt->fetchObject(Item::class);
echo $obj::class . " " . $obj->name . "/" . $obj->qty . "\n";

// fetchObject with stdClass default
$stmt->execute(['c']);
$obj = $stmt->fetchObject();
echo $obj::class . " " . $obj->name . "\n";

// FETCH_KEY_PAIR
$pairs = $pdo->query('SELECT name, qty FROM items')->fetchAll(PDO::FETCH_KEY_PAIR);
foreach ($pairs as $k => $v) echo "$k=$v ";
echo "\n";

// FETCH_COLUMN
$names = $pdo->query('SELECT name FROM items ORDER BY id')->fetchAll(PDO::FETCH_COLUMN);
echo implode(",", $names) . "\n";
