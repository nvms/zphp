<?php
// regression: PDOException messages for SQL errors carry PHP's
// "SQLSTATE[HY000]: General error: <code> <driver message>" prefix. zphp
// threw the bare sqlite error text, so code that pattern-matches on
// "SQLSTATE[" (Laravel's QueryException, Doctrine, etc.) saw nothing.
$db = new PDO('sqlite::memory:');
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$db->exec('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)');

// query against a missing table
try {
    $db->query('SELECT * FROM no_such_table');
} catch (PDOException $e) {
    echo (str_starts_with($e->getMessage(), 'SQLSTATE[HY000]: General error:') ? 'query-prefixed' : 'query-bare'), "\n";
    echo (str_contains($e->getMessage(), 'no such table') ? 'has-detail' : 'no-detail'), "\n";
}

// prepare with a syntax error
try {
    $db->prepare('SELCT broken');
} catch (PDOException $e) {
    echo (str_starts_with($e->getMessage(), 'SQLSTATE[') ? 'prepare-prefixed' : 'prepare-bare'), "\n";
}

// exec against a missing table
try {
    $db->exec('INSERT INTO missing_table VALUES (1)');
} catch (PDOException $e) {
    echo (str_starts_with($e->getMessage(), 'SQLSTATE[HY000]') ? 'exec-prefixed' : 'exec-bare'), "\n";
}

// a successful query still works (no regression)
$db->exec("INSERT INTO t (name) VALUES ('ok')");
echo $db->query('SELECT name FROM t')->fetchColumn(), "\n";

// errorInfo() keeps the raw driver message in slot [2] (not SQLSTATE-wrapped)
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_SILENT);
$db->query('SELECT * FROM still_missing');
$info = $db->errorInfo();
echo $info[0], "\n";  // SQLSTATE code
echo (is_string($info[2]) && strlen($info[2]) > 0 ? 'errorinfo-ok' : 'errorinfo-bad'), "\n";
