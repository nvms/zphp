<?php

// SplPriorityQueue extracts highest priority first
$pq = new SplPriorityQueue();
$pq->insert('low', 1);
$pq->insert('high', 10);
$pq->insert('medium', 5);
$pq->insert('urgent', 100);

while (!$pq->isEmpty()) echo $pq->extract() . " ";
echo "\n";

// EXTR_BOTH returns ['data' => ..., 'priority' => ...]
$pq = new SplPriorityQueue();
$pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
$pq->insert('a', 3);
$pq->insert('b', 1);
$pq->insert('c', 5);

while (!$pq->isEmpty()) {
    $r = $pq->extract();
    echo "{$r['data']}@{$r['priority']} ";
}
echo "\n";

// EXTR_PRIORITY
$pq = new SplPriorityQueue();
$pq->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
$pq->insert('a', 3);
$pq->insert('b', 1);

while (!$pq->isEmpty()) echo $pq->extract() . " ";
echo "\n";

// distinct priorities extract in descending order
$pq = new SplPriorityQueue();
$pq->insert('low', 1);
$pq->insert('high', 5);
$pq->insert('mid', 3);
echo $pq->extract() . " " . $pq->extract() . " " . $pq->extract() . "\n";

// count, top, isEmpty
$pq = new SplPriorityQueue();
$pq->insert('a', 1);
$pq->insert('b', 2);
echo $pq->count() . " " . $pq->top() . "\n";

// iteration is destructive
$pq = new SplPriorityQueue();
$pq->insert('a', 3);
$pq->insert('b', 1);
$pq->insert('c', 2);
foreach ($pq as $v) echo $v . " ";
echo "\n";
echo $pq->count() . "\n"; // 0 after iteration
