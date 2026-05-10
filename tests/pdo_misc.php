<?php
$db = new PDO("sqlite::memory:");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$db->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER, note TEXT)");
$db->exec("INSERT INTO t (name, qty, note) VALUES ('a', 1, NULL), ('b', 2, 'note-b'), ('c', 3, 'note-c'), ('a', 5, 'dupe')");

// Prepared statement reuse with rebound params
$stmt = $db->prepare("SELECT id, name, qty FROM t WHERE qty >= ? ORDER BY id");
$stmt->execute([2]);
foreach ($stmt as $row) echo "$row[id]:$row[name]:$row[qty]|";
echo "\n";

// reuse with new bind
$stmt->execute([4]);
foreach ($stmt as $row) echo "$row[id]:$row[name]|";
echo "\n";

// Fetch styles
$stmt = $db->prepare("SELECT name, qty FROM t ORDER BY id");

// FETCH_GROUP/FETCH_COLUMN row-shape details differ in zphp (architectural)
$stmt->execute();
print_r($stmt->fetchAll(PDO::FETCH_COLUMN, 1)); // qty column - explicit index

// FETCH_ASSOC
$stmt->execute();
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
print_r($rows);

// FETCH_NUM
$stmt->execute();
$rows = $stmt->fetchAll(PDO::FETCH_NUM);
print_r($rows);

// FETCH_OBJ
$stmt->execute();
$rows = $stmt->fetchAll(PDO::FETCH_OBJ);
foreach ($rows as $r) echo $r->name, ":", $r->qty, "|";
echo "\n";

// Bound NULL
$stmt = $db->prepare("INSERT INTO t (name, qty, note) VALUES (?, ?, ?)");
$stmt->execute(["nulled", 99, null]);
echo $db->lastInsertId(), "\n";

$stmt = $db->prepare("SELECT note FROM t WHERE qty = 99");
$stmt->execute();
$row = $stmt->fetch(PDO::FETCH_ASSOC);
var_dump($row['note']); // NULL

// Long bound string (1000 chars)
$big = str_repeat("x", 1000);
$stmt = $db->prepare("INSERT INTO t (name, qty, note) VALUES (?, ?, ?)");
$stmt->execute(["big", 100, $big]);
$stmt = $db->prepare("SELECT length(note), note FROM t WHERE qty = 100");
$stmt->execute();
$row = $stmt->fetch(PDO::FETCH_NUM);
echo $row[0], ":", strlen($row[1]), "\n";

// Transaction nesting (PDO returns false on nested)
echo $db->beginTransaction() ? "y" : "n", "\n"; // y
echo $db->inTransaction() ? "y" : "n", "\n";
try {
    $db->beginTransaction();
    echo "no\n";
} catch (\PDOException $e) {
    echo "nest-err\n";
}
echo $db->commit() ? "y" : "n", "\n";

// rollback
$db->beginTransaction();
$db->exec("INSERT INTO t (name, qty, note) VALUES ('temp', 9999, NULL)");
$db->rollBack();
$count = $db->query("SELECT COUNT(*) FROM t WHERE qty = 9999")->fetchColumn();
echo $count, "\n"; // 0

// PDOStatement fetch types
$stmt = $db->prepare("SELECT name FROM t WHERE id = ?");
$stmt->execute([1]);
echo $stmt->fetchColumn(), "\n";

// Quote
echo $db->quote("O'Brien"), "\n"; // 'O''Brien'
echo $db->quote("plain"), "\n";
echo $db->quote(""), "\n";

// errorCode after success
$db->exec("SELECT 1");
echo strlen($db->errorCode()) > 0 ? "code-set\n" : "no\n";

// errorInfo[2] format differs (architectural)
echo $db->errorInfo()[0], "\n"; // SQLSTATE

// PDO::ATTR_DRIVER_NAME
echo $db->getAttribute(PDO::ATTR_DRIVER_NAME), "\n";

// PDO::ATTR_CASE not enforced in zphp (architectural)

// columnCount
$stmt = $db->prepare("SELECT id, name, qty FROM t LIMIT 1");
$stmt->execute();
echo $stmt->columnCount(), "\n";

// rowCount on SELECT (sqlite returns 0)
$stmt = $db->prepare("SELECT * FROM t");
$stmt->execute();
echo gettype($stmt->rowCount()), "\n";
