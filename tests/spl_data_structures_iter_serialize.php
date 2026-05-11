<?php
$s = new SplStack;
$s->push(1); $s->push(2); $s->push(3);
echo $s->count(), " ", $s->top(), "\n";
echo $s->pop(), " ", $s->pop(), "\n";
echo $s->count(), "\n";
foreach ($s as $v) echo $v, " "; echo "\n";

$q = new SplQueue;
$q->enqueue("a"); $q->enqueue("b"); $q->enqueue("c");
echo $q->count(), "\n";
echo $q->dequeue(), " ", $q->dequeue(), "\n";
foreach ($q as $v) echo $v, " "; echo "\n";

$pq = new SplPriorityQueue;
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("mid", 5);
while (!$pq->isEmpty()) echo $pq->extract(), " ";
echo "\n";

$pq2 = new SplPriorityQueue;
$pq2->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
$pq2->insert("a", 1);
$pq2->insert("b", 3);
$pq2->insert("c", 2);
while (!$pq2->isEmpty()) {
    $e = $pq2->extract();
    echo $e["data"], "=", $e["priority"], " ";
}
echo "\n";

$mh = new SplMinHeap;
$mh->insert(3); $mh->insert(1); $mh->insert(4); $mh->insert(5);
while (!$mh->isEmpty()) echo $mh->extract(), " ";
echo "\n";

class MyMaxHeap extends SplMaxHeap {
    protected function compare(mixed $a, mixed $b): int { return $a - $b; }
}
$h = new MyMaxHeap;
$h->insert(3); $h->insert(1); $h->insert(4); $h->insert(5);
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n";

$dll = new SplDoublyLinkedList;
$dll->push(1); $dll->push(2); $dll->push(3);
$dll->unshift(0);
echo $dll->count(), "\n";
foreach ($dll as $v) echo $v, " "; echo "\n";

$dll2 = new SplDoublyLinkedList;
$dll2->push("a"); $dll2->push("b"); $dll2->push("c");
$dll2->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
foreach ($dll2 as $v) echo $v, " "; echo "\n";
$dll2->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
foreach ($dll2 as $v) echo $v, " "; echo "\n";

$dll3 = new SplDoublyLinkedList;
$dll3->push(1); $dll3->push(2); $dll3->push(3); $dll3->push(4);
$dll3->setIteratorMode(SplDoublyLinkedList::IT_MODE_DELETE);
foreach ($dll3 as $v) echo $v, " "; echo "\n";
echo $dll3->count(), "\n";

$s2 = new SplStack;
$s2->push("x"); $s2->push("y"); $s2->push("z");
$un = unserialize(serialize($s2));
echo $un->count(), "\n";
foreach ($un as $v) echo $v, " "; echo "\n";

$q2 = new SplQueue;
$q2->enqueue(1); $q2->enqueue(2); $q2->enqueue(3);
$un = unserialize(serialize($q2));
foreach ($un as $v) echo $v, " "; echo "\n";

$dll4 = new SplDoublyLinkedList;
$dll4->push(10); $dll4->push(20); $dll4->push(30);
$un = unserialize(serialize($dll4));
foreach ($un as $v) echo $v, " "; echo "\n";

$s3 = new SplStack;
$s3->push("a"); $s3->push("b"); $s3->push("c");
echo $s3[0], " ", $s3[1], " ", $s3[2], "\n";

$dll5 = new SplDoublyLinkedList;
$dll5->push(1); $dll5->push(2); $dll5->push(3);
$dll5->offsetSet(1, 99);
foreach ($dll5 as $v) echo $v, " "; echo "\n";
$dll5->add(0, 100);
foreach ($dll5 as $v) echo $v, " "; echo "\n";

$h2 = new SplMaxHeap;
$h2->insert(5); $h2->insert(2); $h2->insert(8); $h2->insert(1);
echo $h2->top(), " ", $h2->count(), "\n";

$s4 = new SplStack;
echo $s4->isEmpty() ? "y" : "n", "\n";
$s4->push(1);
echo $s4->isEmpty() ? "y" : "n", "\n";
