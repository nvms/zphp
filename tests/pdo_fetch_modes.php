<?php

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER)');
$pdo->exec("INSERT INTO t (name, qty) VALUES ('a', 10), ('b', 20), ('c', 30)");

// FETCH_CLASS hydrates rows into class instances
class Item {
    public string $name;
    public int $qty;
    public function describe(): string { return "$this->name x $this->qty"; }
}
$items = $pdo->query('SELECT name, qty FROM t ORDER BY id')->fetchAll(PDO::FETCH_CLASS, Item::class);
foreach ($items as $i) echo $i->describe() . "\n";
echo count($items) . "\n";

// FETCH_OBJ produces stdClass
$obj = $pdo->query('SELECT * FROM t WHERE id = 1')->fetch(PDO::FETCH_OBJ);
echo $obj::class . " " . $obj->name . "\n";

// FETCH_NUM and FETCH_BOTH ordering
$row = $pdo->query('SELECT id, name FROM t WHERE id = 1')->fetch(PDO::FETCH_NUM);
echo $row[0] . "/" . $row[1] . "\n";

$row = $pdo->query('SELECT id, name FROM t WHERE id = 1')->fetch(PDO::FETCH_BOTH);
echo $row[0] . "/" . $row['id'] . "/" . $row[1] . "/" . $row['name'] . "\n";

// ERRMODE_SILENT returns false instead of throwing
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_SILENT);
$result = $pdo->exec('BAD SQL');
echo var_export($result, true) . "\n";
echo $pdo->errorCode() . "\n";

// switch back to exception mode
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
try {
    $pdo->exec('STILL BAD');
} catch (PDOException $e) {
    echo "caught\n";
}
