<?php
$dbfile = sys_get_temp_dir() . "/_zphp_pdo_probe.sqlite";
if (file_exists($dbfile)) unlink($dbfile);

$pdo = new PDO("sqlite:$dbfile");
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$pdo->exec("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER, salary REAL, active INTEGER)");
echo "created\n";

$pdo->exec("INSERT INTO users (name, age, salary, active) VALUES ('alice', 30, 1500.5, 1)");
$pdo->exec("INSERT INTO users (name, age, salary, active) VALUES ('bob', 25, 2000.0, 0)");
$pdo->exec("INSERT INTO users (name, age, salary, active) VALUES ('carol', 40, 3000.75, 1)");
echo "inserted\n";

echo $pdo->lastInsertId(), "\n";

$rows = $pdo->query("SELECT * FROM users ORDER BY id")->fetchAll(PDO::FETCH_ASSOC);
foreach ($rows as $r) {
    echo $r["id"], "|", $r["name"], "|", $r["age"], "|", $r["salary"], "|", $r["active"], "\n";
}

$row = $pdo->query("SELECT * FROM users WHERE id = 1")->fetch(PDO::FETCH_ASSOC);
print_r($row);

$row = $pdo->query("SELECT * FROM users WHERE id = 1")->fetch(PDO::FETCH_NUM);
print_r($row);

$row = $pdo->query("SELECT * FROM users WHERE id = 1")->fetch(PDO::FETCH_BOTH);
print_r($row);

$row = $pdo->query("SELECT * FROM users WHERE id = 1")->fetch(PDO::FETCH_OBJ);
echo $row->name, ":", $row->age, "\n";

$stmt = $pdo->prepare("SELECT * FROM users WHERE age >= ? ORDER BY age");
$stmt->execute([25]);
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) echo $r["name"], " ", $r["age"], "\n";

$stmt = $pdo->prepare("SELECT * FROM users WHERE name = :name");
$stmt->execute([":name" => "bob"]);
$r = $stmt->fetch(PDO::FETCH_ASSOC);
echo $r["age"], " ", $r["salary"], "\n";

$stmt = $pdo->prepare("SELECT * FROM users WHERE active = :a AND age > :age");
$stmt->bindValue(":a", 1, PDO::PARAM_INT);
$stmt->bindValue(":age", 30, PDO::PARAM_INT);
$stmt->execute();
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) echo $r["name"], "/", $r["age"], "\n";

$stmt = $pdo->prepare("SELECT * FROM users WHERE name LIKE ?");
$stmt->execute(["%o%"]);
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) echo $r["name"], " ";
echo "\n";

$stmt = $pdo->prepare("INSERT INTO users (name, age, salary, active) VALUES (?, ?, ?, ?)");
$stmt->execute(["dave", 35, 2500.0, 1]);
echo $pdo->lastInsertId(), "\n";

$stmt = $pdo->prepare("INSERT INTO users (name, age, salary, active) VALUES (?, ?, ?, ?)");
$stmt->bindValue(1, "eve", PDO::PARAM_STR);
$stmt->bindValue(2, 28, PDO::PARAM_INT);
$stmt->bindValue(3, 1800.25, PDO::PARAM_STR);
$stmt->bindValue(4, 1, PDO::PARAM_INT);
$stmt->execute();
echo $pdo->lastInsertId(), "\n";

$count = $pdo->query("SELECT COUNT(*) FROM users")->fetchColumn();
echo "total=", $count, "\n";

$names = $pdo->query("SELECT name FROM users WHERE active = 1 ORDER BY name")->fetchAll(PDO::FETCH_COLUMN);
print_r($names);

$pdo->beginTransaction();
$stmt = $pdo->prepare("INSERT INTO users (name, age, salary, active) VALUES (?, ?, ?, ?)");
$stmt->execute(["txn1", 50, 5000, 1]);
$stmt->execute(["txn2", 51, 5100, 1]);
$pdo->commit();
echo $pdo->query("SELECT COUNT(*) FROM users")->fetchColumn(), "\n";

$pdo->beginTransaction();
$pdo->exec("INSERT INTO users (name, age, salary, active) VALUES ('rollback', 99, 100, 0)");
$pdo->rollBack();
echo $pdo->query("SELECT COUNT(*) FROM users WHERE name='rollback'")->fetchColumn(), "\n";

$stmt = $pdo->prepare("UPDATE users SET salary = salary * 1.1 WHERE active = 1");
$stmt->execute();
echo "updated:", $stmt->rowCount(), "\n";

$stmt = $pdo->prepare("DELETE FROM users WHERE age < 30");
$stmt->execute();
echo "deleted:", $stmt->rowCount(), "\n";

$stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
$stmt->execute([1]);
echo $stmt->columnCount(), "\n";

$stmt = $pdo->prepare("SELECT name, age FROM users LIMIT 2");
$stmt->execute();
while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) echo $r["name"], "/", $r["age"], "\n";

$null_stmt = $pdo->prepare("INSERT INTO users (name, age, salary, active) VALUES (?, ?, ?, ?)");
$null_stmt->bindValue(1, "nullable", PDO::PARAM_STR);
$null_stmt->bindValue(2, null, PDO::PARAM_NULL);
$null_stmt->bindValue(3, null, PDO::PARAM_NULL);
$null_stmt->bindValue(4, 0, PDO::PARAM_INT);
$null_stmt->execute();
$r = $pdo->query("SELECT name, age, salary FROM users WHERE name='nullable'")->fetch(PDO::FETCH_ASSOC);
echo var_export($r["age"], true), " ", var_export($r["salary"], true), "\n";

$stmt = $pdo->prepare("SELECT name FROM users WHERE id = :id");
$stmt->execute(["id" => 1]);
echo $stmt->fetchColumn(), "\n";

$pdo->exec("CREATE TABLE settings (k TEXT PRIMARY KEY, v TEXT)");
$pdo->exec("INSERT INTO settings VALUES ('lang', 'php'), ('host', 'localhost')");
$pairs = [];
foreach ($pdo->query("SELECT k, v FROM settings ORDER BY k") as $r) {
    $pairs[$r["k"]] = $r["v"];
}
print_r($pairs);

$drivers = PDO::getAvailableDrivers();
echo in_array("sqlite", $drivers) ? "y" : "n", "\n";

$attr = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
echo $attr, "\n";

if (file_exists($dbfile)) unlink($dbfile);
echo "done\n";
