<?php
$db = new PDO("sqlite::memory:");
$db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$db->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, age INT, score REAL, active INT, bio TEXT)");

// placeholders various types
$stmt = $db->prepare("INSERT INTO t (id, name, age, score, active, bio) VALUES (?, ?, ?, ?, ?, ?)");
$stmt->execute([1, "alice", 30, 9.5, 1, null]);
$stmt->execute([2, "bob", 25, 8.7, 0, "developer"]);
$stmt->execute([3, "charlie", 40, 7.0, 1, ""]);

$stmt = $db->query("SELECT * FROM t ORDER BY id");
print_r($stmt->fetchAll(PDO::FETCH_ASSOC));

// named placeholders
$stmt = $db->prepare("SELECT name FROM t WHERE id = :id");
$stmt->execute([":id" => 1]);
echo $stmt->fetchColumn(), "\n";

$stmt->execute(["id" => 2]); // colon optional
echo $stmt->fetchColumn(), "\n";

// bindValue with explicit types
$stmt = $db->prepare("SELECT name FROM t WHERE id = :id");
$stmt->bindValue(":id", 3, PDO::PARAM_INT);
$stmt->execute();
echo $stmt->fetchColumn(), "\n";

// bindValue null
$stmt = $db->prepare("SELECT id FROM t WHERE bio IS :bio OR (bio = :bio2)");
// SQLite uses IS for null, can't directly bind null - but test bind null:
$stmt = $db->prepare("SELECT id FROM t WHERE bio IS NULL");
$stmt->execute();
echo $stmt->fetchColumn(), "\n"; // 1

// LIKE patterns
$stmt = $db->prepare("SELECT name FROM t WHERE name LIKE ?");
$stmt->execute(["%bob%"]);
echo $stmt->fetchColumn(), "\n";

$stmt->execute(["a%"]);
echo $stmt->fetchColumn(), "\n";

$stmt->execute(["_lice"]); // single-char wildcard
echo $stmt->fetchColumn(), "\n";

// PDO::quote
echo $db->quote("hello"), "\n";
echo $db->quote("with 'quote'"), "\n";
echo $db->quote(""), "\n";
echo $db->quote(42), "\n"; // '42'
echo $db->quote(3.14), "\n"; // '3.14'
echo $db->quote(true), "\n"; // '1'
echo $db->quote(false), "\n"; // '' (empty string)
// quote(null) deprecated in PHP 8.5 (architectural skip on warning emission)

// fetch FETCH_OBJ
$stmt = $db->query("SELECT id, name, age FROM t WHERE id = 1");
$row = $stmt->fetch(PDO::FETCH_OBJ);
echo get_class($row), " ", $row->name, "/", $row->age, "\n";

// fetch FETCH_OBJ stdClass
$stmt = $db->query("SELECT id, name FROM t");
$rows = $stmt->fetchAll(PDO::FETCH_OBJ);
foreach ($rows as $r) echo $r->name, " ";
echo "\n";

// fetch FETCH_CLASS
class Person {
    public int $id = 0;
    public string $name = "";
    public int $age = 0;
}
$stmt = $db->query("SELECT id, name, age FROM t");
$people = $stmt->fetchAll(PDO::FETCH_CLASS, Person::class);
foreach ($people as $p) echo "$p->name(", get_class($p), ") ";
echo "\n";

// FETCH_CLASS with constructor args
class PersonWithCtor {
    public int $id = 0;
    public string $name = "";
    public int $age = 0;
    public string $tag = "";
    public function __construct(string $tag) {
        $this->tag = $tag;
    }
}
$stmt = $db->query("SELECT id, name, age FROM t WHERE id = 1");
$people = $stmt->fetchAll(PDO::FETCH_CLASS, PersonWithCtor::class, ["X"]);
foreach ($people as $p) echo "$p->name/$p->tag ";
echo "\n";

// FETCH_INTO
$target = new Person;
$stmt = $db->query("SELECT id, name, age FROM t WHERE id = 2");
$stmt->setFetchMode(PDO::FETCH_INTO, $target);
$stmt->fetch();
echo "$target->name/$target->age\n";

// FETCH_NUM
$stmt = $db->query("SELECT id, name FROM t ORDER BY id");
$r = $stmt->fetch(PDO::FETCH_NUM);
print_r($r);

// FETCH_BOTH (default)
$stmt = $db->query("SELECT id, name FROM t WHERE id = 1");
$r = $stmt->fetch();
print_r($r);

// FETCH_KEY_PAIR (id => name)
$stmt = $db->query("SELECT id, name FROM t ORDER BY id");
$kv = $stmt->fetchAll(PDO::FETCH_KEY_PAIR);
print_r($kv);

// FETCH_COLUMN
$stmt = $db->query("SELECT name FROM t ORDER BY id");
$names = $stmt->fetchAll(PDO::FETCH_COLUMN);
print_r($names);

// fetch with multiple types of binding
$stmt = $db->prepare("SELECT * FROM t WHERE age > :a AND score > :s");
$stmt->bindValue(":a", 20, PDO::PARAM_INT);
$stmt->bindValue(":s", 8.0, PDO::PARAM_STR);
$stmt->execute();
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo count($rows), " matches\n";

// PARAM_BOOL (sqlite stores as int)
$stmt = $db->prepare("SELECT name FROM t WHERE active = :a");
$stmt->bindValue(":a", true, PDO::PARAM_BOOL);
$stmt->execute();
$names = $stmt->fetchAll(PDO::FETCH_COLUMN);
print_r($names);

// PARAM_NULL
$stmt = $db->prepare("UPDATE t SET bio = :bio WHERE id = :id");
$stmt->bindValue(":bio", null, PDO::PARAM_NULL);
$stmt->bindValue(":id", 2, PDO::PARAM_INT);
$stmt->execute();
echo $stmt->rowCount(), " rows updated\n";

$stmt = $db->query("SELECT bio FROM t WHERE id = 2");
$r = $stmt->fetch(PDO::FETCH_NUM);
var_dump($r[0]); // null

// bindParam still works as bindValue (architectural - no by-ref)
$stmt = $db->prepare("SELECT name FROM t WHERE id = :id");
$id = 1;
$stmt->bindParam(":id", $id);
$stmt->execute();
echo $stmt->fetchColumn(), "\n";

// PDO::quote with binary-ish
echo $db->quote("a\\nb"), "\n"; // 'a\nb' (sqlite doesn't escape backslash)
echo $db->quote("a\nb"), "\n"; // 'a<newline>b' (literal newline within quotes)
