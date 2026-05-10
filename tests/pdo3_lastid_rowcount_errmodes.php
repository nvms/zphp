<?php
$db = new PDO("sqlite::memory:");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$db->exec("CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INT)");

// lastInsertId after INSERT
$db->exec("INSERT INTO t (name, age) VALUES ('alice', 30)");
echo "id1=", $db->lastInsertId(), "\n"; // 1

$db->exec("INSERT INTO t (name, age) VALUES ('bob', 25)");
echo "id2=", $db->lastInsertId(), "\n"; // 2

// lastInsertId after prepared
$stmt = $db->prepare("INSERT INTO t (name, age) VALUES (?, ?)");
$stmt->execute(["carol", 40]);
echo "id3=", $db->lastInsertId(), "\n"; // 3

// rowCount after INSERT
echo "rc=", $stmt->rowCount(), "\n"; // 1

// rowCount after UPDATE
$stmt = $db->prepare("UPDATE t SET age = age + 1");
$stmt->execute();
echo "upd=", $stmt->rowCount(), "\n"; // 3

// rowCount after DELETE
$stmt = $db->prepare("DELETE FROM t WHERE age > ?");
$stmt->execute([30]);
echo "del=", $stmt->rowCount(), "\n"; // 2 (alice 31, bob 26, carol 41 -> deleted alice and carol)

// columnCount before execute (PHP returns 0)
$stmt = $db->prepare("SELECT id, name, age FROM t");
echo "cc-pre=", $stmt->columnCount(), "\n"; // 0
$stmt->execute();
echo "cc-post=", $stmt->columnCount(), "\n"; // 3

// rowCount on SELECT (driver-dependent; sqlite returns 0)
echo "sel-rc=", $stmt->rowCount(), "\n"; // 0 in sqlite

// fetchAll
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo count($rows), "\n";
foreach ($rows as $r) echo $r["name"], "=", $r["age"], " ";
echo "\n";

// ERRMODE_SILENT
$db2 = new PDO("sqlite::memory:");
$db2->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_SILENT);
$res = $db2->exec("SELECT * FROM nonexistent");
var_dump($res); // false
$ei = $db2->errorInfo();
echo $ei[0], ":", isset($ei[2]) ? "msg-set" : "no-msg", "\n";

// ERRMODE_WARNING
$db3 = new PDO("sqlite::memory:");
$db3->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_WARNING);
$prev = error_reporting(0);
$res = @$db3->exec("SELECT * FROM nonexistent");
error_reporting($prev);
var_dump($res); // false (warning suppressed)

// ERRMODE_EXCEPTION
try {
    $db->exec("SELECT * FROM nonexistent");
    echo "no-throw\n";
} catch (PDOException $e) {
    echo "caught:", strlen($e->getMessage()) > 0 ? "y" : "n", "\n";
}

// Bad prepare with EXCEPTION
try {
    $stmt = $db->prepare("BAD SQL HERE");
    $stmt->execute();
    echo "no-throw\n";
} catch (PDOException $e) {
    echo "prep-exc\n";
}

// quote
echo $db->quote("alice's"), "\n"; // 'alice''s'
echo $db->quote("hello"), "\n";   // 'hello'

// inTransaction
var_dump($db->inTransaction()); // false
$db->beginTransaction();
var_dump($db->inTransaction()); // true
$db->commit();
var_dump($db->inTransaction()); // false

// rollback
$db->beginTransaction();
$db->exec("INSERT INTO t (name, age) VALUES ('zed', 99)");
$db->rollback();
$stmt = $db->query("SELECT count(*) FROM t WHERE name = 'zed'");
echo $stmt->fetchColumn(), "\n"; // 0

// fetchColumn with various indexes
$stmt = $db->query("SELECT id, name, age FROM t ORDER BY id LIMIT 1");
$row = $stmt->fetch(PDO::FETCH_NUM);
print_r($row);

// PDO::FETCH_KEY_PAIR
$stmt = $db->query("SELECT name, age FROM t ORDER BY id");
$kv = $stmt->fetchAll(PDO::FETCH_KEY_PAIR);
print_r($kv);

// PDO::FETCH_OBJ
$stmt = $db->query("SELECT id, name, age FROM t ORDER BY id LIMIT 1");
$obj = $stmt->fetch(PDO::FETCH_OBJ);
echo $obj->name, "/", $obj->age, "\n";

// PDOStatement bindParam vs bindValue with reference
$stmt = $db->prepare("SELECT name FROM t WHERE age = :a");
$age = 26;
$stmt->bindParam(":a", $age, PDO::PARAM_INT);
$stmt->execute();
echo $stmt->fetchColumn(), "\n"; // bob (bound by ref but value is 26 at execute)

// bindParam by-reference re-fetch at execute (architectural - zphp captures at bind time)
