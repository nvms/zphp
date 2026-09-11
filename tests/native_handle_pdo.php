<?php
// covers: PDO sqlite connection and statement handles surviving forged __db_ptr/__stmt_ptr/__driver properties, uncloneable PDO/Pdo\Sqlite/PDOStatement

$pdo = new PDO("sqlite::memory:");
$pdo->__db_ptr = 0x41414141;
$pdo->__driver = "mysql";
$pdo->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)");
$pdo->exec("INSERT INTO t (name) VALUES ('alpha'), ('beta')");
echo "driver: ", $pdo->getAttribute(PDO::ATTR_DRIVER_NAME), "\n";
echo "last id: ", $pdo->lastInsertId(), "\n";
var_dump(isset($pdo->__db_ptr));
var_dump(isset($pdo->__driver));

$stmt = $pdo->prepare("SELECT name FROM t WHERE id = ?");
$stmt->__stmt_ptr = 0x42424242;
$stmt->__db_ptr = 0x43434343;
$stmt->__driver = "pgsql";
$stmt->execute([2]);
echo "row: ", $stmt->fetchColumn(), "\n";
var_dump(isset($stmt->__stmt_ptr));
var_dump(isset($stmt->__db_ptr));

$q = $pdo->query("SELECT COUNT(*) AS n FROM t");
$q->__stmt_ptr = 0;
$q->__db_ptr = 0;
echo "count: ", $q->fetch(PDO::FETCH_ASSOC)["n"], "\n";
var_dump(isset($q->__stmt_ptr));

$bad = $pdo->prepare("SELECT json_extract('{', '$')");
$bad->__db_ptr = 0x44444444;
try {
    $bad->execute();
} catch (PDOException $e) {
    echo "error: ", $e->getMessage(), "\n";
}

$sub = new Pdo\Sqlite("sqlite::memory:");
echo "sub: ", $sub->query("SELECT 7")->fetchColumn(), "\n";
echo "sub class: ", get_class($sub), "\n";

foreach ([$pdo, $sub, $stmt] as $obj) {
    try {
        $copy = clone $obj;
        echo "cloned ", get_class($copy), "\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}

$stmt->closeCursor();
$stmt = null;
$q = null;
$bad = null;
echo "after: ", $pdo->query("SELECT name FROM t ORDER BY id")->fetchColumn(), "\n";
