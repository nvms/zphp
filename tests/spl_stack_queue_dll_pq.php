<?php
$s = new SplStack;
$s->push(1);
$s->push(2);
$s->push(3);
echo $s->count(), "\n";
echo $s->top(), "\n";
echo $s->pop(), "\n";
echo $s->pop(), "\n";
echo $s->count(), "\n";

$s = new SplStack;
$s->push("a");
$s->push("b");
$s->push("c");
foreach ($s as $v) echo $v, " ";
echo "\n";

$q = new SplQueue;
$q->enqueue("first");
$q->enqueue("second");
$q->enqueue("third");
echo $q->count(), "\n";
echo $q->dequeue(), "\n";
echo $q->dequeue(), "\n";
echo $q->count(), "\n";
echo $q->dequeue(), "\n";
echo $q->isEmpty() ? "empty" : "not", "\n";

$q = new SplQueue;
$q->enqueue(1);
$q->enqueue(2);
$q->enqueue(3);
foreach ($q as $v) echo $v, " ";
echo "\n";

$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");
$dll->unshift("z");
echo $dll->count(), "\n";
echo $dll->top(), "\n";
echo $dll->bottom(), "\n";

foreach ($dll as $k => $v) echo $k, ":", $v, " ";
echo "\n";

echo $dll->shift(), "\n";
echo $dll->pop(), "\n";
echo $dll->count(), "\n";

foreach ($dll as $v) echo $v, " ";
echo "\n";

$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_KEEP);
foreach ($dll as $v) echo $v, " ";
echo "\n";
echo $dll->count(), "\n";

$dll = new SplDoublyLinkedList;
$dll->push("x");
$dll->push("y");
$dll->push("z");
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_DELETE);
foreach ($dll as $v) echo $v, " ";
echo "\n";
echo $dll->count(), "\n";

$dll = new SplDoublyLinkedList;
$dll[] = 10;
$dll[] = 20;
$dll[] = 30;
echo $dll[0], " ", $dll[1], " ", $dll[2], "\n";
$dll[1] = 99;
echo $dll[1], "\n";
echo isset($dll[1]) ? "y" : "n", "\n";
echo isset($dll[5]) ? "y" : "n", "\n";
unset($dll[0]);
echo $dll[0], " ", $dll[1], "\n";
echo $dll->count(), "\n";

$dll = new SplDoublyLinkedList;
echo $dll->isEmpty() ? "y" : "n", "\n";
echo $dll->count(), "\n";
try { $dll->top(); echo "no\n"; } catch (\RuntimeException $e) { echo "re\n"; }
try { $dll->bottom(); echo "no\n"; } catch (\RuntimeException $e) { echo "re\n"; }
try { $dll->pop(); echo "no\n"; } catch (\RuntimeException $e) { echo "re\n"; }

$pq = new SplPriorityQueue;
$pq->insert("low", 1);
$pq->insert("hi", 10);
$pq->insert("med", 5);
echo $pq->count(), "\n";
echo $pq->top(), "\n";
echo $pq->extract(), "\n";
echo $pq->extract(), "\n";
echo $pq->extract(), "\n";
echo $pq->isEmpty() ? "y" : "n", "\n";

$pq = new SplPriorityQueue;
$pq->insert("a", 3);
$pq->insert("b", 1);
$pq->insert("c", 2);
$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
foreach ($pq as $v) echo $v, " ";
echo "\n";

$pq = new SplPriorityQueue;
$pq->insert("a", 3);
$pq->insert("b", 1);
$pq->insert("c", 2);
$pq->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
foreach ($pq as $v) echo $v, " ";
echo "\n";

$pq = new SplPriorityQueue;
$pq->insert("a", 3);
$pq->insert("b", 1);
$pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
foreach ($pq as $v) {
    echo $v["data"], "=", $v["priority"], " ";
}
echo "\n";

$pq = new SplPriorityQueue;
$pq->insert("first", 5);
$pq->insert("second", 5);
$pq->insert("third", 10);
$res = [];
while (!$pq->isEmpty()) $res[] = $pq->extract();
print_r($res);

$dll = new SplDoublyLinkedList;
for ($i = 0; $i < 5; $i++) $dll->push($i);
$dll->add(2, 99);
foreach ($dll as $v) echo $v, " ";
echo "\n";
echo $dll->count(), "\n";

$s = new SplStack;
echo $s->count(), "\n";
$s->push(42);
echo $s->top(), " ", $s->bottom(), "\n";
