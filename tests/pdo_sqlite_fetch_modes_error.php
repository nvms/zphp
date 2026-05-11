<?php
$db = new PDO("sqlite::memory:");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$db->exec("CREATE TABLE u (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, age INTEGER)");

$stmt = $db->prepare("INSERT INTO u (name, age) VALUES (:n, :a)");
foreach ([["alice", 30], ["bob", 25], ["carol", 35]] as [$n, $a]) {
    $stmt->execute([":n" => $n, ":a" => $a]);
}
echo $db->lastInsertId(), "\n";

$stmt = $db->query("SELECT name, age FROM u ORDER BY id");
print_r($stmt->fetchAll(PDO::FETCH_KEY_PAIR));

$stmt = $db->query("SELECT name FROM u ORDER BY id");
print_r($stmt->fetchAll(PDO::FETCH_COLUMN));

class Person {
    public string $name;
    public int $age;
    public function info(): string { return "$this->name ($this->age)"; }
}
$stmt = $db->query("SELECT name, age FROM u ORDER BY id");
foreach ($stmt->fetchAll(PDO::FETCH_CLASS, "Person") as $p) {
    echo $p->info(), "\n";
}

$db->beginTransaction();
$db->exec("UPDATE u SET age = 999 WHERE id = 1");
$db->rollback();
echo $db->query("SELECT age FROM u WHERE id = 1")->fetchColumn(), "\n";

$db->beginTransaction();
$db->exec("UPDATE u SET age = 888 WHERE id = 1");
$db->commit();
echo $db->query("SELECT age FROM u WHERE id = 1")->fetchColumn(), "\n";

$stmt = $db->prepare("UPDATE u SET age = age + 100");
$stmt->execute();
echo $stmt->rowCount(), "\n";

$stmt = $db->prepare("DELETE FROM u WHERE age > ?");
$stmt->execute([100]);
echo $stmt->rowCount(), "\n";

$stmt = $db->prepare("SELECT * FROM u");
$stmt->execute();
print_r($stmt->errorInfo());

try {
    $stmt = $db->prepare("SELECT * FROM nonexistent");
    $stmt->execute();
    echo "no exception\n";
} catch (PDOException $e) {
    echo "caught\n";
}
