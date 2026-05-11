<?php
$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");

$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_KEEP);
$result = [];
foreach ($dll as $k => $v) $result[] = "$k=$v";
echo implode(",", $result), "\n";
echo $dll->count(), "\n";

$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_KEEP);
$result = [];
foreach ($dll as $k => $v) $result[] = "$k=$v";
echo implode(",", $result), "\n";

$dll = new SplDoublyLinkedList;
$dll->push("x");
$dll->push("y");
$dll->push("z");
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_DELETE);
$result = [];
foreach ($dll as $v) $result[] = $v;
echo implode(",", $result), "\n";
echo $dll->count(), "\n";

$dll = new SplDoublyLinkedList;
$dll->push(1);
$dll->push(2);
$dll->push(3);
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_DELETE);
$result = [];
foreach ($dll as $v) $result[] = $v;
echo implode(",", $result), "\n";
echo $dll->count(), "\n";

$queue = new SplQueue;
$queue->enqueue("first");
$queue->enqueue("second");
$queue->enqueue("third");
echo $queue->getIteratorMode(), "\n";

$stack = new SplStack;
$stack->push("a");
$stack->push("b");
$stack->push("c");
echo $stack->getIteratorMode(), "\n";

$dll = new SplDoublyLinkedList;
$dll->push(10);
$dll->push(20);
$dll->push(30);
echo $dll->getIteratorMode(), "\n";

class MaxHeap extends SplMaxHeap {}
$h = new MaxHeap;
$h->insert(5);
$h->insert(1);
$h->insert(8);
$h->insert(3);
$h->insert(10);

$result = [];
foreach ($h as $v) $result[] = $v;
echo implode(",", $result), "\n";
echo $h->count(), "\n";

class MinHeap extends SplMinHeap {}
$h = new MinHeap;
foreach ([5, 1, 8, 3, 10] as $n) $h->insert($n);
$result = [];
foreach ($h as $v) $result[] = $v;
echo implode(",", $result), "\n";

class StringHeap extends SplHeap {
    protected function compare(mixed $a, mixed $b): int {
        return strcmp($b, $a);
    }
}
$h = new StringHeap;
foreach (["banana", "apple", "cherry"] as $s) $h->insert($s);
$result = [];
foreach ($h as $s) $result[] = $s;
echo implode(",", $result), "\n";

class ReversedNumHeap extends SplHeap {
    protected function compare(mixed $a, mixed $b): int {
        return $b - $a;
    }
}
$h = new ReversedNumHeap;
foreach ([10, 2, 5, 8, 1] as $n) $h->insert($n);
$result = [];
foreach ($h as $n) $result[] = $n;
echo implode(",", $result), "\n";

$dll = new SplDoublyLinkedList;
$dll->push("a");
echo $dll->isEmpty() ? "y" : "n", "\n";
echo $dll->count(), "\n";

$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_DELETE);
$dll->rewind();
echo $dll->valid() ? "y" : "n", "\n";
echo $dll->current(), "\n";
$dll->next();
echo $dll->valid() ? "y" : "n", "\n";

$dll = new SplDoublyLinkedList;
for ($i = 0; $i < 5; $i++) $dll->push($i * 10);
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_KEEP);
$result = [];
foreach ($dll as $k => $v) $result[] = "$k:$v";
echo implode(",", $result), "\n";

$dll = new SplDoublyLinkedList;
$dll->push("alpha");
$dll->push("beta");
$dll->push("gamma");

$mode = SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_KEEP;
$dll->setIteratorMode($mode);

$first = null;
foreach ($dll as $v) {
    $first = $v;
    break;
}
echo $first, "\n";

echo SplDoublyLinkedList::IT_MODE_LIFO, "\n";
echo SplDoublyLinkedList::IT_MODE_FIFO, "\n";
echo SplDoublyLinkedList::IT_MODE_KEEP, "\n";
echo SplDoublyLinkedList::IT_MODE_DELETE, "\n";

$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_DELETE);
echo $dll->count(), "\n";
foreach ($dll as $v) ;
echo $dll->count(), "\n";

$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_KEEP);
foreach ($dll as $v) ;
echo $dll->count(), "\n";

$h = new MinHeap;
foreach ([3, 1, 4, 1, 5, 9, 2, 6, 5, 3] as $n) $h->insert($n);
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
echo implode(",", $out), "\n";

$pq = new SplPriorityQueue;
$pq->insert("a", 1);
$pq->insert("b", 3);
$pq->insert("c", 2);
$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
$out = [];
foreach ($pq as $v) $out[] = $v;
echo implode(",", $out), "\n";
