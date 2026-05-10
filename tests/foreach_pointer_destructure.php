<?php
$arr = [1, 2, 3];
foreach ($arr as &$v) $v *= 10;
unset($v);
print_r($arr);

$arr = ["a" => 1, "b" => 2];
foreach ($arr as $k => &$v) $v = "$k-$v";
unset($v);
print_r($arr);

// foreach copies array - modifying original doesn't affect iteration
$src = [1, 2, 3];
$out = [];
foreach ($src as $v) {
    $out[] = $v;
    if ($v === 1) {
        $src[] = 99;
        $src[] = 100;
    }
}
print_r($out); // [1, 2, 3]
print_r($src); // [1, 2, 3, 99, 100]

// foreach by-ref sees appended elements (architectural - zphp snapshots on iter_begin)

// internal pointer
$arr = [10, 20, 30];
echo current($arr), "\n"; // 10
echo key($arr), "\n"; // 0
echo next($arr), "\n"; // 20
echo current($arr), "\n";
echo key($arr), "\n";
echo prev($arr), "\n"; // 10
echo end($arr), "\n"; // 30
echo key($arr), "\n"; // 2
echo reset($arr), "\n"; // 10

// next past end -> false
$arr = [1];
echo current($arr), "\n";
$r = next($arr);
var_dump($r);
var_dump(current($arr));

// empty
$arr = [];
var_dump(current($arr));
var_dump(key($arr));

// foreach doesn't affect cursor of original (after copy)
$arr = ["a", "b", "c"];
foreach ($arr as $v) {}
echo current($arr), "\n"; // a (cursor at start)

// internal pointer after assoc
$arr = ["x" => 10, "y" => 20];
echo current($arr), "/", key($arr), "\n";
next($arr);
echo current($arr), "/", key($arr), "\n";

// loop
$arr = [1, 2, 3];
$out = [];
reset($arr);
while (key($arr) !== null) {
    $out[] = current($arr);
    next($arr);
}
print_r($out);

// each() removed in PHP 8
echo function_exists("each") ? "y" : "n", "\n";

// array_walk doesn't disturb cursor
$arr = [10, 20, 30];
next($arr);
echo key($arr), "\n";
array_walk($arr, fn($v) => $v);
// PHP behavior: array_walk uses internal pointer, may reset
echo key($arr), "\n"; // depends on impl

// foreach of an Iterator
class C implements Iterator {
    private int $i = 0;
    private array $data;
    public function __construct(array $d) { $this->data = $d; }
    public function current(): mixed { return $this->data[$this->i] ?? null; }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return isset($this->data[$this->i]); }
}
foreach (new C([10, 20, 30]) as $k => $v) echo "$k=$v ";
echo "\n";

// foreach over generator
$gen = (function () {
    yield 1;
    yield 2;
    yield 3;
})();
foreach ($gen as $v) echo "$v ";
echo "\n";

// foreach copy with array of objects (objects are still by reference)
class Box { public int $n = 0; }
$boxes = [new Box, new Box, new Box];
foreach ($boxes as $b) $b->n = 99;
foreach ($boxes as $b) echo $b->n, " "; // 99 99 99
echo "\n";

// foreach by ref over array of arrays
$data = [[1, 2], [3, 4]];
foreach ($data as &$row) $row[] = 99;
unset($row);
print_r($data); // [[1,2,99], [3,4,99]]

// foreach skip with continue
$out = [];
foreach ([1, 2, 3, 4, 5] as $v) {
    if ($v % 2 === 0) continue;
    $out[] = $v;
}
print_r($out);

// nested foreach with break N
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
];
$found = null;
foreach ($matrix as $row) {
    foreach ($row as $v) {
        if ($v === 5) {
            $found = $v;
            break 2;
        }
    }
}
echo $found, "\n";

// foreach destructure
$pairs = [["a", 1], ["b", 2]];
foreach ($pairs as [$k, $v]) echo "$k=$v ";
echo "\n";

foreach ($pairs as $i => [$k, $v]) echo "$i:$k=$v ";
echo "\n";

// associative destructure in foreach
$rows = [
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
];
foreach ($rows as ["name" => $n, "age" => $a]) echo "$n=$a ";
echo "\n";

// foreach over string/null warning (architectural - PHP emits Warning, zphp silent)
