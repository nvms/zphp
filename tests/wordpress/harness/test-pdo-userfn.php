<?php
// exercise PDO\Sqlite::createFunction with user PHP callbacks invoked
// inside SELECT. WordPress's SQLite drop-in uses this for MySQL-style
// builtins (UNIX_TIMESTAMP, FROM_UNIXTIME, etc.) that SQLite doesn't ship.
define('SHORTINIT', true);
$abspath = realpath(__DIR__ . '/../app/') . '/';
define('ABSPATH', $abspath);

$db_dir = __DIR__ . '/../app/wp-content/database';
if (!is_dir($db_dir)) mkdir($db_dir, 0777, true);
$db_path = $db_dir . '/.ht.userfn.sqlite';
if (file_exists($db_path)) unlink($db_path);

require $abspath . 'wp-load.php';

$pdo = new PDO('sqlite:' . $db_path);

$pdo->sqliteCreateFunction('php_upper', function($s) { return strtoupper($s); }, 1);
$pdo->sqliteCreateFunction('php_concat', function($a, $b) { return $a . '-' . $b; }, 2);
$pdo->sqliteCreateFunction('php_sum', function() { return array_sum(func_get_args()); }, -1);

$pdo->exec("CREATE TABLE t (id INT, name TEXT)");
$pdo->exec("INSERT INTO t VALUES (1, 'alice'), (2, 'bob'), (3, 'carol')");

$rows = $pdo->query("SELECT id, php_upper(name) AS upper_name FROM t ORDER BY id")->fetchAll(PDO::FETCH_ASSOC);
foreach ($rows as $r) {
    echo "row: {$r['id']} {$r['upper_name']}\n";
}

$joined = $pdo->query("SELECT php_concat(name, name) AS dbl FROM t WHERE id = 2")->fetchColumn();
echo "concat: $joined\n";

$sum = $pdo->query("SELECT php_sum(id, id*10, id*100) AS s FROM t WHERE id = 3")->fetchColumn();
echo "sum: $sum\n";

unset($pdo);
if (file_exists($db_path)) unlink($db_path);
