<?php
// SplPriorityQueue
$pq = new SplPriorityQueue();
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("mid", 5);
echo "pq count: " . $pq->count() . "\n";
echo "pq top: " . $pq->extract() . "\n";
echo "pq top: " . $pq->extract() . "\n";
echo "pq top: " . $pq->extract() . "\n";
echo "pq empty: " . ($pq->isEmpty() ? "yes" : "no") . "\n";

// SplPriorityQueue extract flags
$pq2 = new SplPriorityQueue();
$pq2->insert("a", 3);
$pq2->insert("b", 1);
$pq2->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
echo "pq priority: " . $pq2->extract() . "\n";

// SplMinHeap
$min = new SplMinHeap();
$min->insert(5);
$min->insert(1);
$min->insert(3);
echo "min top: " . $min->top() . "\n";
echo "min extract: " . $min->extract() . "\n";
echo "min extract: " . $min->extract() . "\n";
echo "min extract: " . $min->extract() . "\n";

// SplMaxHeap
$max = new SplMaxHeap();
$max->insert(5);
$max->insert(1);
$max->insert(3);
echo "max top: " . $max->top() . "\n";
echo "max extract: " . $max->extract() . "\n";
echo "max extract: " . $max->extract() . "\n";
echo "max extract: " . $max->extract() . "\n";

// SplFixedArray
$fa = new SplFixedArray(3);
$fa[0] = "a";
$fa[1] = "b";
$fa[2] = "c";
echo "fa size: " . $fa->getSize() . "\n";
echo "fa count: " . count($fa) . "\n";
echo "fa[1]: " . $fa[1] . "\n";
$fa->setSize(5);
echo "fa new size: " . $fa->getSize() . "\n";
$arr = $fa->toArray();
echo "fa toArray count: " . count($arr) . "\n";

// SplQueue
$q = new SplQueue();
$q->enqueue("first");
$q->enqueue("second");
$q->enqueue("third");
echo "q count: " . $q->count() . "\n";
echo "q bottom: " . $q->bottom() . "\n";
echo "q dequeue: " . $q->dequeue() . "\n";
echo "q dequeue: " . $q->dequeue() . "\n";
echo "q count after: " . $q->count() . "\n";
echo "q empty: " . ($q->isEmpty() ? "yes" : "no") . "\n";
