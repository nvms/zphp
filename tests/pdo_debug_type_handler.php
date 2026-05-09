<?php
// PDO sqlite in-memory
$pdo = new PDO("sqlite::memory:");
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)");
$pdo->exec("INSERT INTO t (name, age) VALUES ('alice', 30), ('bob', 25), ('carol', 40)");
$stmt = $pdo->prepare("SELECT * FROM t WHERE age > ? ORDER BY id");
$stmt->execute([26]);
foreach ($stmt as $row) echo $row['id'], ":", $row['name'], "(", $row['age'], ")|";
echo "\n";

$stmt = $pdo->prepare("SELECT name FROM t WHERE id = :id");
$stmt->bindValue(":id", 2);
$stmt->execute();
echo $stmt->fetchColumn(), "\n";

$stmt = $pdo->prepare("INSERT INTO t (name, age) VALUES (?, ?)");
$stmt->execute(["dave", 50]);
echo $pdo->lastInsertId(), "\n";

// transactions
$pdo->beginTransaction();
$pdo->exec("INSERT INTO t (name, age) VALUES ('eve', 60)");
$pdo->rollBack();
echo $pdo->query("SELECT COUNT(*) FROM t")->fetchColumn(), "\n";

// date_parse
$d = date_parse("2024-06-15 14:30:00");
echo $d['year'], "-", $d['month'], "-", $d['day'], " ", $d['hour'], ":", $d['minute'], ":", $d['second'], "\n";
echo $d['warning_count'], ",", $d['error_count'], "\n";

// gettype
echo gettype(null), "\n";
echo gettype(true), "\n";
echo gettype(1), "\n";
echo gettype(1.5), "\n";
echo gettype("s"), "\n";
echo gettype([1]), "\n";
echo gettype(new stdClass), "\n";
echo gettype(fn() => 1), "\n";

// get_debug_type
echo get_debug_type(null), "\n";
echo get_debug_type(true), "\n";
echo get_debug_type(1), "\n";
echo get_debug_type(1.5), "\n";
echo get_debug_type("s"), "\n";
echo get_debug_type([1]), "\n";
echo get_debug_type(new stdClass), "\n";
echo get_debug_type(fn() => 1), "\n";
class FooBar {}
echo get_debug_type(new FooBar), "\n";

// closures and generators
$cl = function () {};
echo $cl instanceof Closure ? "is-closure\n" : "no\n";

function gg() { yield 1; }
$g = gg();
echo $g instanceof Generator ? "is-gen\n" : "no\n";
echo gettype($g), "\n";

// assert behavior depends on zend.assertions (PHP_INI_SYSTEM, varies in CI), only check the no-op path
assert(1 + 1 === 2);
echo "after assert\n";

// trigger_error / set_error_handler
set_error_handler(function ($severity, $message, $file, $line) {
    echo "handled[$severity]:$message\n";
    return true;
});
trigger_error("user notice", E_USER_NOTICE);
trigger_error("user warning", E_USER_WARNING);
trigger_error("user error", E_USER_ERROR);
restore_error_handler();
echo "after trigger\n";

// set_error_handler that throws
set_error_handler(function ($s, $m) { throw new RuntimeException("from handler:$m"); });
try { trigger_error("oops", E_USER_WARNING); echo "no err\n"; } catch (\RuntimeException $e) { echo "caught:", $e->getMessage(), "\n"; }
restore_error_handler();

// array_walk modifying via ref
$arr = [1, 2, 3, 4];
array_walk($arr, function (&$v, $k) { $v = $v * 10 + $k; });
print_r($arr);

// array_walk with extra data
$arr2 = ["a", "b", "c"];
array_walk($arr2, function (&$v, $k, $prefix) { $v = "$prefix:$v"; }, "X");
print_r($arr2);

// ArrayObject with custom iterator
class MyIter implements Iterator {
    private int $i = 0;
    public function __construct(private array $data) {}
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < count($this->data); }
    public function current(): mixed { return $this->data[$this->i] * 2; }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
}
$m = new MyIter([1, 2, 3, 4]);
foreach ($m as $k => $v) echo "$k=$v ";
echo "\n";

// IteratorAggregate
class Container implements IteratorAggregate {
    public function __construct(private array $data) {}
    public function getIterator(): Iterator { return new ArrayIterator($this->data); }
}
$c = new Container(["a"=>1, "b"=>2, "c"=>3]);
foreach ($c as $k => $v) echo "$k=$v ";
echo "\n";

// error_reporting initial level varies by CI ini; just verify set/get roundtrips
$prev = error_reporting(E_ALL);
echo error_reporting() === E_ALL ? "all\n" : "fail\n";
error_reporting($prev);
echo error_reporting() === $prev ? "restored\n" : "fail\n";
