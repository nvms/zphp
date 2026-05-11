<?php
$dbfile = sys_get_temp_dir() . "/_zphp_pdo2_probe.sqlite";
if (file_exists($dbfile)) unlink($dbfile);

$pdo = new PDO("sqlite:$dbfile");
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$pdo->exec("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL, stock INTEGER, category TEXT)");

$stmt = $pdo->prepare("INSERT INTO products (name, price, stock, category) VALUES (?, ?, ?, ?)");

$data = [
    ["apple", 1.5, 100, "fruit"],
    ["banana", 0.5, 200, "fruit"],
    ["carrot", 0.75, 50, "vegetable"],
    ["donut", 2.0, 30, "snack"],
];
foreach ($data as $row) {
    $stmt->execute($row);
}
echo $pdo->query("SELECT COUNT(*) FROM products")->fetchColumn(), "\n";

$stmt = $pdo->prepare("SELECT * FROM products WHERE price BETWEEN ? AND ?");
$stmt->execute([0.5, 1.5]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
foreach ($rows as $r) echo $r["name"], " ";
echo "\n";

$stmt = $pdo->prepare("SELECT * FROM products WHERE category = :cat AND stock > :min_stock ORDER BY name");
$stmt->execute([":cat" => "fruit", ":min_stock" => 50]);
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) echo $r["name"], "/", $r["price"], " ";
echo "\n";

$stmt = $pdo->prepare("SELECT name, price FROM products WHERE id = :id");
$stmt->bindValue(":id", 1, PDO::PARAM_INT);
$stmt->execute();
$r = $stmt->fetch(PDO::FETCH_ASSOC);
echo $r["name"], " ", $r["price"], "\n";

$stmt = $pdo->prepare("SELECT * FROM products WHERE id = ?");
$stmt->execute([2]);
$r = $stmt->fetch(PDO::FETCH_ASSOC);
echo $r["name"], "\n";

$stmt->execute([3]);
$r = $stmt->fetch(PDO::FETCH_ASSOC);
echo $r["name"], "\n";

$rows = $pdo->query("SELECT name, price FROM products ORDER BY id LIMIT 2")->fetchAll(PDO::FETCH_ASSOC);
print_r($rows);

$rows = $pdo->query("SELECT name, price FROM products ORDER BY id LIMIT 2")->fetchAll(PDO::FETCH_NUM);
print_r($rows);

$rows = $pdo->query("SELECT name, price FROM products ORDER BY id LIMIT 2")->fetchAll(PDO::FETCH_BOTH);
print_r($rows);

$rows = $pdo->query("SELECT name, price FROM products ORDER BY id LIMIT 2")->fetchAll(PDO::FETCH_OBJ);
foreach ($rows as $r) echo $r->name, "/", $r->price, " ";
echo "\n";

$names = $pdo->query("SELECT name FROM products")->fetchAll(PDO::FETCH_COLUMN);
print_r($names);

$pdo->beginTransaction();
$pdo->exec("INSERT INTO products (name, price, stock, category) VALUES ('rollback_test', 99.99, 1, 'test')");
echo $pdo->query("SELECT COUNT(*) FROM products WHERE name='rollback_test'")->fetchColumn(), "\n";
$pdo->rollBack();
echo $pdo->query("SELECT COUNT(*) FROM products WHERE name='rollback_test'")->fetchColumn(), "\n";

$pdo->beginTransaction();
$pdo->exec("INSERT INTO products (name, price, stock, category) VALUES ('commit_test', 50, 5, 'test')");
$pdo->commit();
echo $pdo->query("SELECT COUNT(*) FROM products WHERE name='commit_test'")->fetchColumn(), "\n";

$stmt = $pdo->prepare("UPDATE products SET price = price * 1.1 WHERE category = ?");
$stmt->execute(["fruit"]);
echo "updated:", $stmt->rowCount(), "\n";

$stmt = $pdo->prepare("DELETE FROM products WHERE name = ?");
$stmt->execute(["nonexistent"]);
echo "deleted:", $stmt->rowCount(), "\n";

$stmt = $pdo->prepare("DELETE FROM products WHERE name = ?");
$stmt->execute(["commit_test"]);
echo "deleted:", $stmt->rowCount(), "\n";

$stmt = $pdo->prepare("SELECT name FROM products WHERE id = ?");
$stmt->execute([1]);
echo $stmt->columnCount(), "\n";

try {
    $pdo->exec("INVALID SQL");
} catch (\PDOException $e) {
    echo "caught\n";
    $info = $pdo->errorInfo();
    echo is_array($info) ? "y" : "n", "\n";
    echo count($info) >= 3 ? "y" : "n", "\n";
    echo strlen($pdo->errorCode()) > 0 ? "y" : "n", "\n";
}

$stmt = $pdo->prepare("SELECT * FROM products WHERE id > ?");
$stmt->execute([0]);
$count = 0;
while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) $count++;
echo "scrolled:", $count, "\n";

$stmt = $pdo->prepare("SELECT id, name FROM products WHERE category = ? ORDER BY id");
$stmt->execute(["fruit"]);
$assoc = [];
while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) $assoc[$r["id"]] = $r["name"];
print_r($assoc);

$stmt = $pdo->prepare("INSERT INTO products (name, price, stock, category) VALUES (?, ?, ?, ?)");
$stmt->execute(["multi1", 1, 1, "a"]);
$id1 = $pdo->lastInsertId();
$stmt->execute(["multi2", 2, 2, "b"]);
$id2 = $pdo->lastInsertId();
echo $id2 > $id1 ? "y" : "n", "\n";

$pdo = new PDO("sqlite::memory:");
$pdo->exec("CREATE TABLE t (n INTEGER)");
echo $pdo->getAttribute(PDO::ATTR_DRIVER_NAME), "\n";

for ($i = 1; $i <= 3; $i++) $pdo->exec("INSERT INTO t (n) VALUES ($i)");
echo $pdo->query("SELECT SUM(n) FROM t")->fetchColumn(), "\n";

$nested = $pdo->prepare("SELECT * FROM t WHERE n IN (?, ?, ?)");
$nested->execute([1, 2, 3]);
echo $nested->rowCount() === 3 || count($nested->fetchAll()) === 3 ? "y" : "n", "\n";

if (file_exists($dbfile)) unlink($dbfile);
echo "done\n";
