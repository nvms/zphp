<?php

$pdo = new PDO('sqlite::memory:');

// invalid SQL should throw
try {
    $pdo->exec("NOT VALID SQL AT ALL");
    echo "no error\n";
} catch (PDOException $e) {
    echo "caught pdo error\n";
} catch (Exception $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// query on nonexistent table
try {
    $pdo->query("SELECT * FROM nonexistent_table");
    echo "no error\n";
} catch (PDOException $e) {
    echo "caught table error\n";
} catch (Exception $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// FETCH_BOTH mode
$pdo->exec("CREATE TABLE t (name TEXT, age INTEGER)");
$pdo->exec("INSERT INTO t VALUES ('alice', 30)");
$stmt = $pdo->query("SELECT name, age FROM t");
$row = $stmt->fetch(PDO::FETCH_BOTH);
echo $row[0] . "\n";
echo $row['name'] . "\n";
echo $row[1] . "\n";
echo $row['age'] . "\n";

// rowCount on insert/update
$pdo->exec("INSERT INTO t VALUES ('bob', 25)");
$stmt = $pdo->prepare("UPDATE t SET age = ? WHERE name = ?");
$stmt->execute([31, 'alice']);
echo "rows: " . $stmt->rowCount() . "\n";

// closeCursor
$stmt = $pdo->query("SELECT * FROM t");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
echo $row['name'] . "\n";
$stmt->closeCursor();

echo "done\n";
