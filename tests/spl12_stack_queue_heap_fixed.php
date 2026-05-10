<?php
// SplStack
$s = new SplStack;
$s->push("a");
$s->push("b");
$s->push("c");
echo count($s), "\n"; // 3
echo $s->top(), "\n"; // c
echo $s->pop(), "\n"; // c
echo $s->top(), "\n"; // b
echo $s->pop(), "\n"; // b
echo $s->pop(), "\n"; // a
echo count($s), "\n"; // 0

$s = new SplStack;
$s->push(1);
$s->push(2);
$s->push(3);
foreach ($s as $v) echo "$v ";
echo "\n"; // 3 2 1 (LIFO)

// SplQueue
$q = new SplQueue;
$q->enqueue("a");
$q->enqueue("b");
$q->enqueue("c");
echo count($q), "\n";
echo $q->dequeue(), "\n"; // a
echo $q->dequeue(), "\n"; // b
echo count($q), "\n"; // 1

$q = new SplQueue;
$q->enqueue(1);
$q->enqueue(2);
$q->enqueue(3);
foreach ($q as $v) echo "$v ";
echo "\n"; // 1 2 3 (FIFO)

// SplDoublyLinkedList
$l = new SplDoublyLinkedList;
$l->push(1);
$l->push(2);
$l->push(3);
echo count($l), "\n";
echo $l[0], " ", $l[1], " ", $l[2], "\n";
$l->unshift(0);
echo $l[0], " ", $l[1], "\n";

// SplPriorityQueue
$pq = new SplPriorityQueue;
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("med", 5);
echo count($pq), "\n";
echo $pq->extract(), "\n"; // high
echo $pq->extract(), "\n"; // med
echo $pq->extract(), "\n"; // low

// SplPriorityQueue iteration
$pq = new SplPriorityQueue;
$pq->insert("a", 3);
$pq->insert("b", 1);
$pq->insert("c", 2);
foreach ($pq as $v) echo "$v ";
echo "\n"; // a c b

// SplMinHeap
$h = new SplMinHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(7);
echo count($h), "\n";
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n"; // 1 3 5 7

// SplMaxHeap
$h = new SplMaxHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(7);
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n"; // 7 5 3 1

// custom heap via SplHeap
class ByLen extends SplHeap {
    public function compare(mixed $a, mixed $b): int {
        return strlen($a) - strlen($b);
    }
}
$h = new ByLen;
$h->insert("aaa");
$h->insert("a");
$h->insert("ab");
echo $h->extract(), "\n"; // aaa (longest first)
echo $h->extract(), "\n"; // ab
echo $h->extract(), "\n"; // a

// SplFixedArray
$fa = new SplFixedArray(5);
echo count($fa), "\n"; // 5
echo $fa->getSize(), "\n";
$fa[0] = "a";
$fa[1] = "b";
$fa[4] = "e";
echo $fa[0], " ", $fa[1], " ", $fa[2] ?? "null", " ", $fa[4], "\n";

// iteration
foreach ($fa as $k => $v) echo "$k=", $v ?? "null", " ";
echo "\n";

// resize
$fa->setSize(3);
echo count($fa), "\n";

// fromArray
$fa = SplFixedArray::fromArray(["x", "y", "z"]);
echo count($fa), "\n";
echo $fa[0], " ", $fa[1], " ", $fa[2], "\n";

// toArray
$a = $fa->toArray();
print_r($a);

// out-of-bounds (PHP throws RuntimeException)
$fa = new SplFixedArray(3);
try { echo $fa[10]; } catch (\RuntimeException $e) { echo "oob\n"; }

// SplObjectStorage as set
$s = new SplObjectStorage;
$o1 = new stdClass;
$o2 = new stdClass;
$s[$o1] = "x";
$s[$o2] = "y";
echo count($s), "\n";
echo $s[$o1], " ", $s[$o2], "\n";
var_dump(isset($s[$o1]));

// SplDoublyLinkedList iteration modes
$l = new SplDoublyLinkedList;
$l->push(1);
$l->push(2);
$l->push(3);
$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
foreach ($l as $v) echo "$v ";
echo "\n"; // 3 2 1

$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
foreach ($l as $v) echo "$v ";
echo "\n"; // 1 2 3

// SplStack inherits from SplDoublyLinkedList
var_dump(new SplStack instanceof SplDoublyLinkedList);
var_dump(new SplQueue instanceof SplDoublyLinkedList);

// SplStack pop on empty
$s = new SplStack;
try { $s->pop(); echo "no\n"; } catch (\Exception $e) { echo "pop-empty-exc\n"; }

// SplFixedArray invalid size
try { new SplFixedArray(-1); echo "no\n"; } catch (\ValueError $e) { echo "neg-ve\n"; }
