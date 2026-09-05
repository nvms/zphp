<?php
error_reporting(E_ALL & ~E_DEPRECATED);
function step_total($context, $row, $value) {
    return ($context ?? 0) + $value;
}
function final_total($context, $row) { return json_encode([$context, $row]); }
$db = new PDO('sqlite::memory:');
$db->exec('CREATE TABLE items (g TEXT, v INTEGER)');
$db->exec("INSERT INTO items VALUES ('a',2),('a',3),('b',7)");
var_dump($db->sqliteCreateAggregate('total_php', 'step_total', 'final_total', 1));
foreach ($db->query('SELECT g, total_php(v) AS total FROM items GROUP BY g ORDER BY g')->fetchAll(PDO::FETCH_ASSOC) as $row) echo json_encode($row), "\n";
echo $db->query('SELECT total_php(v) FROM items WHERE 0')->fetchColumn(), "\n";
$db->sqliteCreateAggregate('state_php', function ($c, $n, $v) { $c[] = [$n, $v]; gc_collect_cycles(); return $c; }, function ($c, $n) { return json_encode([$c, $n]); }, 1);
gc_collect_cycles();
echo $db->query('SELECT state_php(v) FROM items')->fetchColumn(), "\n";
$db->sqliteCreateAggregate('total_php', fn($c, $n, $v) => ($c ?? '') . $v, fn($c, $n) => $c, 1);
echo $db->query('SELECT total_php(v) FROM items')->fetchColumn(), "\n";
$db->sqliteCreateAggregate('types_php', fn($c, $n, $a, $b, $d) => [$a,$b,$d], fn($c,$n) => json_encode($c));
echo $db->query("SELECT types_php(NULL, 1.25, CAST(x'610062' AS BLOB))")->fetchColumn(), "\n";
$db->sqliteCreateAggregate('fail_php', function($c,$n,$v) { throw new RuntimeException('step failed'); }, fn($c,$n) => $c, 1);
try { $db->query('SELECT fail_php(v) FROM items'); } catch (RuntimeException $e) { echo $e->getMessage(), "\n"; }
$db->sqliteCreateAggregate('fail_php', fn($c,$n,$v) => $v, function($c,$n) { throw new RuntimeException('final failed'); }, 1);
try { $db->query('SELECT fail_php(v) FROM items'); } catch (RuntimeException $e) { echo $e->getMessage(), "\n"; }
echo $db->query('SELECT total_php(v) FROM items')->fetchColumn(), "\n";
var_dump($db->sqliteCreateAggregate('invalid_arity', 'step_total', 'final_total', -2));
if (class_exists('Pdo\\Sqlite')) {
    $alias = new Pdo\Sqlite('sqlite::memory:');
    var_dump($alias->createAggregate('alias_php', 'step_total', 'final_total', 1));
    echo $alias->query('SELECT alias_php(9)')->fetchColumn(), "\n";
}
class AggregateCallbacks {
    public function step($c, $n, $v) { return ($c ?? 0) + $v; }
    public function finish($c, $n) { return $c; }
}
$callbacks = new AggregateCallbacks();
$db->sqliteCreateAggregate('object_php', [$callbacks, 'step'], [$callbacks, 'finish'], 1);
unset($callbacks); gc_collect_cycles();
$stmt = $db->prepare('SELECT object_php(v) FROM items WHERE v > ?');
$stmt->execute([2]); var_dump($stmt->fetchColumn());
$stmt->execute([6]); var_dump($stmt->fetchColumn());
$db->sqliteCreateAggregate('bool_php', fn($c,$n,$v) => $v, fn($c,$n) => false, 1);
var_dump($db->query('SELECT bool_php(v) FROM items')->fetchColumn());
try { $db->sqliteCreateAggregate('bad_callback', 'no_such_callback', 'final_total', 1); } catch (TypeError $e) { echo "invalid callback caught\n"; }
$db->sqliteCreateFunction('scalar_php', fn($v) => $v * 3, 1);
var_dump($db->query('SELECT scalar_php(4)')->fetchColumn());
$db->sqliteCreateCollation('reverse_php', fn($a,$b) => strcmp($b,$a));
echo json_encode($db->query('SELECT g FROM items ORDER BY g COLLATE reverse_php')->fetchAll(PDO::FETCH_COLUMN)), "\n";
unset($db); gc_collect_cycles();
echo "done\n";
