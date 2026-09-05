<?php
error_reporting(E_ALL & ~E_DEPRECATED);
$db = new PDO('sqlite::memory:');
$db->sqliteCreateAggregate('agg', function($c,$n,$v) { throw new RuntimeException('step'); }, fn($c,$n) => $c, 1);
$db->setAttribute(PDO::ATTR_ERRMODE, 0);
try {
    $db->query('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:step:query:", $e->getMessage(), "\n";
}
try {
    $db->exec('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:step:exec:", $e->getMessage(), "\n";
}
try {
    $db->prepare('SELECT agg(1)')->execute();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:step:execute:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetch();
    $stmt->fetch();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:step:fetch:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchColumn();
    $stmt->fetchColumn();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:step:fetchColumn:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchAll();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:step:fetchAll:", $e->getMessage(), "\n";
}
$db->setAttribute(PDO::ATTR_ERRMODE, 2);
try {
    $db->query('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:step:query:", $e->getMessage(), "\n";
}
try {
    $db->exec('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:step:exec:", $e->getMessage(), "\n";
}
try {
    $db->prepare('SELECT agg(1)')->execute();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:step:execute:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetch();
    $stmt->fetch();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:step:fetch:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchColumn();
    $stmt->fetchColumn();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:step:fetchColumn:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchAll();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:step:fetchAll:", $e->getMessage(), "\n";
}
echo $db->query("SELECT 42")->fetchColumn(), "\n";
$db->sqliteCreateAggregate('agg', fn($c,$n,$v) => $v, function($c,$n) { throw new RuntimeException('final'); }, 1);
$db->setAttribute(PDO::ATTR_ERRMODE, 0);
try {
    $db->query('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:final:query:", $e->getMessage(), "\n";
}
try {
    $db->exec('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:final:exec:", $e->getMessage(), "\n";
}
try {
    $db->prepare('SELECT agg(1)')->execute();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:final:execute:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetch();
    $stmt->fetch();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:final:fetch:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchColumn();
    $stmt->fetchColumn();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:final:fetchColumn:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchAll();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "0:final:fetchAll:", $e->getMessage(), "\n";
}
$db->setAttribute(PDO::ATTR_ERRMODE, 2);
try {
    $db->query('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:final:query:", $e->getMessage(), "\n";
}
try {
    $db->exec('SELECT agg(1)');
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:final:exec:", $e->getMessage(), "\n";
}
try {
    $db->prepare('SELECT agg(1)')->execute();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:final:execute:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetch();
    $stmt->fetch();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:final:fetch:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchColumn();
    $stmt->fetchColumn();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:final:fetchColumn:", $e->getMessage(), "\n";
}
try {
    $stmt = $db->query('SELECT 0 UNION ALL SELECT agg(1)');
    $stmt->fetchAll();
    echo "lost exception\n";
} catch (RuntimeException $e) {
    echo "2:final:fetchAll:", $e->getMessage(), "\n";
}
echo $db->query("SELECT 42")->fetchColumn(), "\n";
