<?php

// basic connection and exec
$pdo = new PDO('sqlite::memory:');
$pdo->exec("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER)");
$pdo->exec("INSERT INTO users (name, age) VALUES ('alice', 30)");
$pdo->exec("INSERT INTO users (name, age) VALUES ('bob', 25)");
echo "inserted\n";

// query and fetch
$stmt = $pdo->query("SELECT * FROM users ORDER BY id");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo $row['name'] . " " . $row['age'] . "\n";  // alice 30
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo $row['name'] . " " . $row['age'] . "\n";  // bob 25
$row = $stmt->fetch();
echo ($row === false ? "no more" : "error") . "\n";  // no more

// prepared statement with positional params
$stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
$stmt->execute([1]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "by id: " . $row['name'] . "\n";  // by id: alice

// prepared statement with named params
$stmt = $pdo->prepare("SELECT * FROM users WHERE name = :name");
$stmt->execute(['name' => 'bob']);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "by name: " . $row['name'] . " " . $row['age'] . "\n";  // by name: bob 25

// fetchAll
$stmt = $pdo->query("SELECT name FROM users ORDER BY id");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo "count: " . count($rows) . "\n";  // count: 2
echo $rows[0]['name'] . " " . $rows[1]['name'] . "\n";  // alice bob

// fetchColumn
$stmt = $pdo->query("SELECT name FROM users ORDER BY id");
echo "first: " . $stmt->fetchColumn() . "\n";  // first: alice

// lastInsertId
$pdo->exec("INSERT INTO users (name, age) VALUES ('charlie', 35)");
echo "last id: " . $pdo->lastInsertId() . "\n";  // last id: 3

// columnCount
$stmt = $pdo->query("SELECT * FROM users");
echo "columns: " . $stmt->columnCount() . "\n";  // columns: 3

// transactions - rollback
$pdo->beginTransaction();
$pdo->exec("DELETE FROM users");
$pdo->rollBack();
$stmt = $pdo->query("SELECT COUNT(*) as cnt FROM users");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "after rollback: " . $row['cnt'] . "\n";  // after rollback: 3

// transactions - commit
$pdo->beginTransaction();
$pdo->exec("INSERT INTO users (name, age) VALUES ('dave', 40)");
$pdo->commit();
$stmt = $pdo->query("SELECT COUNT(*) as cnt FROM users");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "after commit: " . $row['cnt'] . "\n";  // after commit: 4

// reuse prepared statement
$stmt = $pdo->prepare("INSERT INTO users (name, age) VALUES (?, ?)");
$stmt->execute(['eve', 28]);
$stmt->execute(['frank', 33]);
$stmt = $pdo->query("SELECT COUNT(*) as cnt FROM users");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "total: " . $row['cnt'] . "\n";  // total: 6

// FETCH_NUM mode
$stmt = $pdo->query("SELECT name, age FROM users WHERE id = 1");
$row = $stmt->fetch(PDO::FETCH_NUM);
echo "num: " . $row[0] . " " . $row[1] . "\n";  // num: alice 30

echo "done\n";
