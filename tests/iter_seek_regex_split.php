<?php
// SplDoublyLinkedList prev/next traversal
$l = new SplDoublyLinkedList();
foreach ([1, 2, 3, 4, 5] as $v) $l->push($v);
$l->rewind();
while ($l->valid()) {
    echo $l->current(), " ";
    $l->next();
}
echo "|\n";

// SplDoublyLinkedList LIFO mode
$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
$l->rewind();
while ($l->valid()) { echo $l->current(), " "; $l->next(); }
echo "|\n";

// serialize round-trip
$l = new SplDoublyLinkedList();
foreach (["a", "b", "c"] as $v) $l->push($v);
$s = serialize($l);
$r = unserialize($s);
echo $r->count(), ":";
foreach ($r as $v) echo "$v ";
echo "\n";

// ArrayIterator seek
$ai = new ArrayIterator([10, 20, 30, 40, 50]);
$ai->seek(2);
echo $ai->key(), "=", $ai->current(), "\n"; // 2=30

try { $ai->seek(99); echo "seeked\n"; } catch (\OutOfBoundsException $e) { echo "oob\n"; }

// IteratorIterator wrapping
$gen = (function () { yield 1; yield 2; yield 3; })();
$ii = new IteratorIterator($gen);
$ii->rewind();
while ($ii->valid()) { echo $ii->current(), " "; $ii->next(); }
echo "|\n";

// LimitIterator
$src = new ArrayIterator([10, 20, 30, 40, 50]);
$li = new LimitIterator($src, 1, 3);
foreach ($li as $k => $v) echo "$k=$v ";
echo "\n";
echo $li->getPosition(), "\n";

$li = new LimitIterator($src, 0, -1); // unlimited
foreach ($li as $v) echo "$v ";
echo "|\n";

// RegexIterator
$src = new ArrayIterator(["apple", "banana", "cherry", "avocado", "berry"]);
$rx = new RegexIterator($src, '/^a/');
foreach ($rx as $v) echo "$v ";
echo "\n";

$rx = new RegexIterator($src, '/(\w+)y$/', RegexIterator::GET_MATCH);
foreach ($rx as $m) echo $m[0], "|";
echo "\n";

$src = new ArrayIterator(["10-apple", "20-banana", "30-cherry"]);
$rx = new RegexIterator($src, '/-/', RegexIterator::SPLIT);
foreach ($rx as $parts) print_r($parts);

// AppendIterator
$ai = new AppendIterator();
$ai->append(new ArrayIterator([1, 2]));
$ai->append(new ArrayIterator(["a", "b", "c"]));
$ai->append(new ArrayIterator([100]));
foreach ($ai as $k => $v) echo "$k=$v ";
echo "\n";

// RecursiveIteratorIterator with depth
$nested = new RecursiveArrayIterator([
    "a" => 1,
    "b" => ["c" => 2, "d" => ["e" => 3, "f" => ["g" => 4]]],
    "h" => 5,
]);
$it = new RecursiveIteratorIterator($nested);
foreach ($it as $k => $v) echo "$k=$v ";
echo "\n";
echo $it->getDepth(), "\n";

$it = new RecursiveIteratorIterator($nested, RecursiveIteratorIterator::SELF_FIRST);
$it->setMaxDepth(1);
foreach ($it as $k => $v) {
    echo str_repeat("-", $it->getDepth()), "$k=";
    if (!is_array($v)) echo $v;
    echo " ";
}
echo "\n";

// RecursiveTreeIterator basic
$tree = new RecursiveTreeIterator(new RecursiveArrayIterator(["a" => 1, "b" => ["c" => 2, "d" => 3]]));
$out = [];
foreach ($tree as $k => $v) $out[] = $v;
echo count($out), "\n";

// callbacks in array_walk_recursive
$data = ["a" => 1, "b" => ["c" => 2]];
$ok = array_walk_recursive($data, function (&$v, $k) { $v = "$k:$v"; });
var_dump($ok); // true
print_r($data);

// string indexing
$s = "hello";
echo $s[0], "|", $s[4], "|\n";
echo $s[-1], "|", $s[-5], "|\n";
// $s[OOB] ?? interaction with ?? requires distinct null-vs-empty semantics

// string assignment
$s = "abc";
$s[1] = "X";
echo $s, "\n"; // aXc
$s[5] = "Z"; // pads with spaces
echo "[$s]\n"; // [aXc  Z]
$s = "abc";
$s[-1] = "Y";
echo $s, "\n"; // abY

// isset on string offset
$s = "hello";
var_dump(isset($s[0]));
var_dump(isset($s[4]));
var_dump(isset($s[5])); // beyond → false
var_dump(isset($s[-1])); // true
var_dump(isset($s[-100])); // false
