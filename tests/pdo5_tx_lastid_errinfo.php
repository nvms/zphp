<?php
$db = new PDO("sqlite::memory:");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$db->exec("CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INT)");

echo "id-before=", $db->lastInsertId(), "\n";

$db->exec("INSERT INTO t (name, age) VALUES ('alice', 30)");
echo "id1=", $db->lastInsertId(), "\n";

$db->exec("INSERT INTO t (name, age) VALUES ('bob', 25)");
echo "id2=", $db->lastInsertId(), "\n";

$db->exec("INSERT INTO t (name, age) VALUES ('carol', 40)");
echo "id3=", $db->lastInsertId(), "\n";

$stmt = $db->prepare("INSERT INTO t (name, age) VALUES (?, ?)");
$stmt->execute(["dave", 35]);
echo "id-prep=", $db->lastInsertId(), "\n";

var_dump($db->beginTransaction());
echo "in-tx=", $db->inTransaction() ? "y" : "n", "\n";

$db->exec("INSERT INTO t (name, age) VALUES ('temp', 99)");
echo "id-tx=", $db->lastInsertId(), "\n";

var_dump($db->rollBack());
echo "in-tx=", $db->inTransaction() ? "y" : "n", "\n";

$count = $db->query("SELECT COUNT(*) FROM t WHERE name = 'temp'")->fetchColumn();
echo "rolledback=", $count, "\n";

$db->beginTransaction();
$db->exec("INSERT INTO t (name, age) VALUES ('committed', 50)");
$db->commit();
$count = $db->query("SELECT COUNT(*) FROM t WHERE name = 'committed'")->fetchColumn();
echo "committed=", $count, "\n";

try { $db->beginTransaction(); $db->beginTransaction(); echo "no\n"; }
catch (\PDOException $e) { echo "nested-exc\n"; }
$db->rollBack();

$stmt = $db->prepare("SELECT name FROM t WHERE id = ?");
$stmt->execute([1]);
echo "exec1: ", $stmt->fetchColumn(), "\n";

$stmt->execute([2]);
echo "exec2: ", $stmt->fetchColumn(), "\n";

$stmt->execute([3]);
echo "exec3: ", $stmt->fetchColumn(), "\n";

$stmt = $db->prepare("SELECT name FROM t WHERE age > :a ORDER BY age");
$stmt->execute([":a" => 30]);
$names = $stmt->fetchAll(PDO::FETCH_COLUMN);
print_r($names);

$stmt->execute([":a" => 20]);
$names = $stmt->fetchAll(PDO::FETCH_COLUMN);
print_r($names);

$db_silent = new PDO("sqlite::memory:");
$db_silent->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_SILENT);
$res = $db_silent->exec("SELECT * FROM nonexistent_table");
var_dump($res);

$ei = $db_silent->errorInfo();
echo gettype($ei), " count=", count($ei), "\n";
echo "code=", $ei[0], "\n";
echo "msg-set=", isset($ei[2]) && strlen($ei[2]) > 0 ? "y" : "n", "\n";

echo "errcode=", $db_silent->errorCode(), "\n";

try {
    $db->exec("SELECT * FROM not_exist_xyz");
    echo "no\n";
} catch (\PDOException $e) {
    $ei = $e->errorInfo;
    echo "thrown msg-set=", strlen($e->getMessage()) > 0 ? "y" : "n", "\n";
    echo "code-set=", $e->getCode() !== "" ? "y" : "n", "\n";
}

$stmt = $db->prepare("SELECT 1");
$stmt->execute();
echo "stmt-rc=", $stmt->errorCode(), "\n";

try {
    $stmt = $db->prepare("BAD SQL HERE");
    echo "no\n";
} catch (\PDOException $e) {
    echo "bad-prep-exc\n";
}

$stmt = $db->prepare("INSERT INTO t (name, age) VALUES (?, ?)");
$names = ["x", "y", "z"];
$ages = [10, 20, 30];
foreach ($names as $i => $n) {
    $stmt->execute([$n, $ages[$i]]);
}
echo "row-count=", $db->query("SELECT COUNT(*) FROM t")->fetchColumn(), "\n";

$stmt = $db->prepare("SELECT name, age FROM t WHERE age > ? ORDER BY id LIMIT 2");
$stmt->execute([20]);
while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    echo $row["name"], "=", $row["age"], " ";
}
echo "\n";

$stmt = $db->prepare("SELECT name FROM t WHERE id > ?");
$stmt->execute([0]);
$count = 0;
while ($stmt->fetch(PDO::FETCH_ASSOC)) $count++;
echo "iter=$count\n";

try { (new PDO("sqlite:/nonexistent/path/db"))->exec("SELECT 1"); echo "no\n"; }
catch (\PDOException $e) { echo "open-fail\n"; }

$drivers = PDO::getAvailableDrivers();
echo gettype($drivers), " has-sqlite=", in_array("sqlite", $drivers) ? "y" : "n", "\n";
