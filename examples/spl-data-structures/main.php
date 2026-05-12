<?php
// covers: SplStack/SplQueue LIFO+FIFO, SplDoublyLinkedList, SplPriorityQueue,
//   SplHeap (min/max), SplFixedArray, ArrayObject

echo "=== SplStack LIFO ===\n";
$s = new SplStack();
$s->push('a'); $s->push('b'); $s->push('c');
echo "top: " . $s->top() . "\n";
echo "count: " . count($s) . "\n";
while (!$s->isEmpty()) echo "pop: " . $s->pop() . "\n";

echo "\n=== SplQueue FIFO ===\n";
$q = new SplQueue();
$q->enqueue('first'); $q->enqueue('second'); $q->enqueue('third');
while (!$q->isEmpty()) echo "deq: " . $q->dequeue() . "\n";

echo "\n=== SplDoublyLinkedList iteration both directions ===\n";
$dll = new SplDoublyLinkedList();
foreach (['x', 'y', 'z'] as $v) $dll->push($v);
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO | SplDoublyLinkedList::IT_MODE_KEEP);
foreach ($dll as $v) echo "fifo: $v\n";
$dll->rewind();
$dll->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO | SplDoublyLinkedList::IT_MODE_KEEP);
foreach ($dll as $v) echo "lifo: $v\n";

echo "\n=== SplPriorityQueue (distinct priorities) ===\n";
$pq = new SplPriorityQueue();
$pq->insert('low task', 1);
$pq->insert('critical task', 100);
$pq->insert('medium task', 50);
$pq->insert('background task', 5);
while (!$pq->isEmpty()) echo "next: " . $pq->extract() . "\n";

echo "\n=== SplMinHeap ===\n";
$h = new SplMinHeap();
foreach ([5, 1, 3, 8, 2, 7] as $n) $h->insert($n);
$ordered = [];
while (!$h->isEmpty()) $ordered[] = $h->extract();
echo implode(',', $ordered) . "\n";

echo "\n=== SplMaxHeap ===\n";
$h = new SplMaxHeap();
foreach ([5, 1, 3, 8, 2, 7] as $n) $h->insert($n);
$ordered = [];
while (!$h->isEmpty()) $ordered[] = $h->extract();
echo implode(',', $ordered) . "\n";

echo "\n=== SplFixedArray ===\n";
$arr = new SplFixedArray(5);
$arr[0] = 'a'; $arr[1] = 'b'; $arr[4] = 'e';
echo "size: " . $arr->getSize() . "\n";
foreach ($arr as $i => $v) echo "  [$i]: " . var_export($v, true) . "\n";

echo "\n=== ArrayObject behaves like an array ===\n";
$ao = new ArrayObject(['a' => 1, 'b' => 2, 'c' => 3]);
$ao['d'] = 4;
echo "count: " . count($ao) . "\n";
echo "has b: " . (isset($ao['b']) ? "yes" : "no") . "\n";
unset($ao['a']);
echo "after unset a: " . count($ao) . "\n";

$ao->ksort();
foreach ($ao as $k => $v) echo "  $k => $v\n";

echo "\n=== SplObjectStorage as object-keyed map ===\n";
$store = new SplObjectStorage();
$o1 = new stdClass();
$o2 = new stdClass();
$o3 = new stdClass();
$store[$o1] = 'first';
$store[$o2] = 'second';
$store->offsetSet($o3, 'third');
echo "count: " . count($store) . "\n";
echo "has o2: " . (isset($store[$o2]) ? "yes" : "no") . "\n";
echo "value o1: " . $store[$o1] . "\n";

unset($store[$o2]);
echo "count after unset: " . count($store) . "\n";

echo "\n=== SplPriorityQueue with extract flags ===\n";
$pq = new SplPriorityQueue();
$pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
$pq->insert('task A', 50);
$pq->insert('task B', 100);
$first = $pq->extract();
echo "data: " . $first['data'] . " priority: " . $first['priority'] . "\n";

echo "\n=== sorting with closures ===\n";
$people = [
    ['name' => 'Alice', 'age' => 30],
    ['name' => 'Bob', 'age' => 25],
    ['name' => 'Carol', 'age' => 35],
];
usort($people, fn($a, $b) => $a['age'] <=> $b['age']);
foreach ($people as $p) echo "  $p[name] ($p[age])\n";

echo "\ndone\n";
