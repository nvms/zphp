<?php

$pdo = new PDO("pgsql:host=127.0.0.1;port=5432;dbname=test", "postgres", "test");

// create table
$pdo->exec("DROP TABLE IF EXISTS users");
$pdo->exec("CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), age INT)");
echo "created\n";

// insert
$pdo->exec("INSERT INTO users (name, age) VALUES ('alice', 30)");
$pdo->exec("INSERT INTO users (name, age) VALUES ('bob', 25)");
echo "inserted\n";

// query
$stmt = $pdo->query("SELECT name, age FROM users ORDER BY name");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo $rows[0]["name"] . " " . $rows[0]["age"] . "\n";
echo $rows[1]["name"] . " " . $rows[1]["age"] . "\n";

// prepared statement with positional params
$stmt = $pdo->prepare("SELECT name, age FROM users WHERE age > ?");
$stmt->execute([20]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo "older than 20: " . count($rows) . "\n";

// prepared statement with named params
$stmt = $pdo->prepare("SELECT name FROM users WHERE name = :name");
$stmt->execute(["name" => "alice"]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "found: " . $row["name"] . "\n";

// lastInsertId
$pdo->exec("INSERT INTO users (name, age) VALUES ('charlie', 35)");
echo "last id: " . $pdo->lastInsertId() . "\n";

// transactions
$pdo->beginTransaction();
$pdo->exec("INSERT INTO users (name, age) VALUES ('dave', 40)");
$pdo->rollBack();
$stmt = $pdo->query("SELECT COUNT(*) as cnt FROM users");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "after rollback: " . $row["cnt"] . "\n";

$pdo->beginTransaction();
$pdo->exec("INSERT INTO users (name, age) VALUES ('eve', 28)");
$pdo->commit();
$stmt = $pdo->query("SELECT COUNT(*) as cnt FROM users");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo "after commit: " . $row["cnt"] . "\n";

// fetchColumn
$stmt = $pdo->query("SELECT name FROM users ORDER BY name LIMIT 1");
echo "first: " . $stmt->fetchColumn() . "\n";

// rowCount
$stmt = $pdo->prepare("UPDATE users SET age = age + 1 WHERE age > ?");
$stmt->execute([0]);
echo "updated: " . $stmt->rowCount() . "\n";

// cleanup
$pdo->exec("DROP TABLE users");
echo "done\n";
