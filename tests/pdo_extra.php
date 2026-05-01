<?php

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER)');
$pdo->exec("INSERT INTO t (name, qty) VALUES ('a', 1), ('b', 2), ('c', 3)");

// quote with various types
echo $pdo->quote("O'Reilly") . "\n";
echo $pdo->quote("plain string") . "\n";
echo $pdo->quote(42) . "\n";
echo $pdo->quote("") . "\n";

// inTransaction transitions
echo ($pdo->inTransaction() ? "in" : "no") . "\n";
$pdo->beginTransaction();
echo ($pdo->inTransaction() ? "in" : "no") . "\n";
$pdo->commit();
echo ($pdo->inTransaction() ? "in" : "no") . "\n";

$pdo->beginTransaction();
$pdo->rollBack();
echo ($pdo->inTransaction() ? "in" : "no") . "\n";

// errorCode on a fresh handle
echo $pdo->errorCode() . "\n";

// fetch with explicit while
$stmt = $pdo->prepare('SELECT id, name FROM t ORDER BY id');
$stmt->execute();
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    echo $row['id'] . "=" . $row['name'] . " ";
}
echo "\n";

// IN clause with manual placeholder expansion
$ids = [1, 3];
$placeholders = implode(',', array_fill(0, count($ids), '?'));
$stmt = $pdo->prepare("SELECT name FROM t WHERE id IN ($placeholders)");
$stmt->execute($ids);
echo implode(",", $stmt->fetchAll(PDO::FETCH_COLUMN)) . "\n";

// LIKE with bound param
$stmt = $pdo->prepare('SELECT name FROM t WHERE name LIKE ?');
$stmt->execute(['%']);
echo implode(",", $stmt->fetchAll(PDO::FETCH_COLUMN)) . "\n";

// closeCursor + reuse
$stmt = $pdo->prepare('SELECT name FROM t WHERE id = ?');
$stmt->execute([1]);
echo $stmt->fetchColumn() . "\n";
$stmt->closeCursor();
$stmt->execute([2]);
echo $stmt->fetchColumn() . "\n";

// rowCount on INSERT
$ins = $pdo->prepare("INSERT INTO t (name, qty) VALUES (?, ?)");
$ins->execute(['d', 4]);
echo "inserted=" . $ins->rowCount() . "\n";
echo "lastId=" . $pdo->lastInsertId() . "\n";

// available drivers includes sqlite
echo in_array('sqlite', PDO::getAvailableDrivers()) ? "y" : "n";
echo "\n";
