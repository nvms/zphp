<?php
// SplStack
$s = new SplStack();
$s->push(1); $s->push(2); $s->push(3);
echo count($s), "\n";
echo $s->top(), "\n";
echo $s->pop(), "\n";
echo $s->pop(), "\n";
echo count($s), "\n";

// SplQueue
$q = new SplQueue();
$q->enqueue("a");
$q->enqueue("b");
$q->enqueue("c");
echo $q->dequeue(), "\n";
echo $q->dequeue(), "\n";
echo count($q), "\n";

// SplDoublyLinkedList
$l = new SplDoublyLinkedList();
$l->push(1); $l->push(2); $l->push(3);
$l->unshift(0);
echo count($l), "\n";
foreach ($l as $v) echo $v, " ";
echo "\n";
echo $l->shift(), "\n"; // 0
echo $l->pop(), "\n";   // 3

// SplFixedArray
$fa = new SplFixedArray(5);
$fa[0] = "a"; $fa[2] = "c"; $fa[4] = "e";
echo $fa[0], " ", $fa[1] ?? "null", " ", $fa[2], " ", $fa[3] ?? "null", " ", $fa[4], "\n";
echo count($fa), "\n";
echo $fa->getSize(), "\n";
$fa->setSize(3);
echo count($fa), "\n";
$arr = $fa->toArray();
print_r($arr);
$fa2 = SplFixedArray::fromArray(["x", "y", "z"]);
echo $fa2[0], " ", $fa2[1], " ", $fa2[2], "\n";

// SplPriorityQueue
$pq = new SplPriorityQueue();
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("medium", 5);
while (!$pq->isEmpty()) {
    echo $pq->extract(), "\n";
}

// ArrayObject
$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);
echo count($ao), "\n";
echo $ao["a"], "\n";
$ao["d"] = 4;
echo $ao->count(), "\n";
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
$ao->asort();
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
$ao->ksort();
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
print_r($ao->getArrayCopy());

// ArrayObject ARRAY_AS_PROPS
$ao = new ArrayObject(["x" => 10, "y" => 20], ArrayObject::ARRAY_AS_PROPS);
echo $ao->x, " ", $ao->y, "\n";
$ao->x = 100;
echo $ao["x"], "\n";

// SplObjectStorage iteration order
$s = new SplObjectStorage();
$o1 = new stdClass; $o1->id = 1;
$o2 = new stdClass; $o2->id = 2;
$o3 = new stdClass; $o3->id = 3;
$s[$o1] = "a"; $s[$o2] = "b"; $s[$o3] = "c";
foreach ($s as $obj) echo $obj->id, "=", $s[$obj], " ";
echo "\n";

// SplHeap
class MaxHeap extends SplHeap {
    protected function compare($a, $b): int { return $a - $b; }
}
$h = new MaxHeap();
$h->insert(3); $h->insert(1); $h->insert(4); $h->insert(1); $h->insert(5);
foreach ($h as $v) echo $v, " ";
echo "\n";

// SplMinHeap / SplMaxHeap
$mn = new SplMinHeap();
$mn->insert(5); $mn->insert(3); $mn->insert(7); $mn->insert(1);
echo $mn->extract(), " ", $mn->extract(), "\n"; // 1 3
$mx = new SplMaxHeap();
$mx->insert(5); $mx->insert(3); $mx->insert(7); $mx->insert(1);
echo $mx->extract(), " ", $mx->extract(), "\n"; // 7 5
