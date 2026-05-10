<?php
$s = new SplObjectStorage;
$o1 = new stdClass; $o1->name = "a";
$o2 = new stdClass; $o2->name = "b";
$o3 = new stdClass; $o3->name = "c";
$s[$o1] = "first";
$s[$o2] = "second";
$s[$o3] = "third";

foreach ($s as $obj) echo $obj->name, ":", $s[$obj], " ";
echo "\n";

unset($s[$o2]);
foreach ($s as $obj) echo $obj->name, ":", $s[$obj], " ";
echo "\n";

$s[$o2] = "new-second";
foreach ($s as $obj) echo $obj->name, ":", $s[$obj], " ";
echo "\n";

$s[$o1] = "updated-first";
foreach ($s as $obj) echo $obj->name, ":", $s[$obj], " ";
echo "\n";

$fa = SplFixedArray::fromArray([10, 20, 30]);
echo count($fa), "\n";
foreach ($fa as $k => $v) echo "$k=$v ";
echo "\n";

$fa = SplFixedArray::fromArray([0 => "a", 5 => "f", 10 => "k"]);
echo count($fa), "\n";
echo $fa[0] ?? "n", "/", $fa[5] ?? "n", "/", $fa[10] ?? "n", "\n";
echo $fa[1] ?? "null", "\n";
foreach ($fa as $k => $v) echo "$k=", $v ?? "null", " ";
echo "\n";

try { SplFixedArray::fromArray(["a" => 1, "b" => 2]); echo "no\n"; }
catch (\InvalidArgumentException $e) { echo "iae\n"; }

$d = new SplDoublyLinkedList;
$d->push(1);
$d->push(2);
$d->push(3);
$d[1] = "X";
echo $d[0], " ", $d[1], " ", $d[2], "\n";

$d[] = "appended";
echo count($d), "\n";

$d->unshift("front");
echo $d[0], " ", count($d), "\n";

$d->shift();
echo $d[0], "\n";

$d->push("end");
echo $d[count($d) - 1], "\n";

echo $d->top(), "\n";
echo $d->bottom(), "\n";

$d = new SplDoublyLinkedList;
$d->push("a");
$d->push("b");
$d->push("c");
$d->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
foreach ($d as $v) echo "$v ";
echo "\n";

$d->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
foreach ($d as $v) echo "$v ";
echo "\n";

$pq = new SplPriorityQueue;
$pq->insert("low", 1);
$pq->insert("med", 5);
$pq->insert("high", 10);
$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
echo $pq->extract(), "\n"; // high

$pq2 = new SplPriorityQueue;
$pq2->insert("a", 1);
$pq2->insert("b", 2);
$pq2->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
echo $pq2->extract(), "\n"; // 2

$pq3 = new SplPriorityQueue;
$pq3->insert("a", 1);
$pq3->insert("b", 2);
$pq3->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
$r = $pq3->extract();
print_r($r);

$pq4 = new SplPriorityQueue;
$pq4->insert("x", 1);
$pq4->insert("y", 2);
$pq4->insert("z", 3);
foreach ($pq4 as $v) echo "$v ";
echo "\n";
echo count($pq4), "\n";

$h = new SplMinHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(7);
echo count($h), "\n";
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

$h = new SplMaxHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(7);
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

class ByLen extends SplHeap {
    public function compare(mixed $a, mixed $b): int {
        return strlen($b) - strlen($a);
    }
}
$h = new ByLen;
$h->insert("a");
$h->insert("aaaa");
$h->insert("aa");
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

$s = new SplStack;
$s->push(1); $s->push(2); $s->push(3);
$out = [];
while (!$s->isEmpty()) $out[] = $s->pop();
print_r($out);

$q = new SplQueue;
$q->enqueue(1); $q->enqueue(2); $q->enqueue(3);
$out = [];
while (!$q->isEmpty()) $out[] = $q->dequeue();
print_r($out);

$ai = new ArrayIterator([10, 20, 30]);
$ai->seek(1);
echo $ai->current(), "/", $ai->key(), "\n";
$ai->seek(2);
echo $ai->current(), "/", $ai->key(), "\n";
$ai->seek(0);
echo $ai->current(), "\n";
