<?php
error_reporting(E_ALL & ~E_DEPRECATED);
$db = new Pdo\Sqlite('sqlite::memory:');
$step = fn($c,$n,$v) => ($c ?? 0) + $v;
$final = fn($c,$n) => $c;
var_dump($db->createAggregate('agg', $step, $final, 1));
$stmt = $db->query('SELECT agg(2) UNION ALL SELECT agg(3)');
// Active statements reject replacement; SQLite destroys only the new registration.
var_dump($db->createAggregate('agg', $step, fn($c,$n) => 99, 1));
var_dump($stmt->fetchAll(PDO::FETCH_COLUMN));
var_dump($db->createAggregate('agg', $step, fn($c,$n) => 99, 1));
var_dump($db->createAggregate('invalid', $step, $final, -2));
$stmt = $db->query('SELECT agg(4) UNION ALL SELECT agg(5)');
unset($db); gc_collect_cycles();
var_dump($stmt->fetchAll(PDO::FETCH_COLUMN));
unset($stmt); gc_collect_cycles();
echo "done\n";
