<?php
$h = new SplMinHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(8);
$h->insert(2);

echo count($h), "\n";
echo $h->top(), "\n";
echo count($h), "\n";

$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

echo $h->count(), "\n";

$h = new SplMaxHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(8);
$h->insert(2);

echo $h->top(), "\n";

$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

class StringHeap extends SplHeap {
    public function compare(mixed $a, mixed $b): int {
        return strcmp($b, $a);
    }
}
$h = new StringHeap;
$h->insert("banana");
$h->insert("apple");
$h->insert("cherry");
$h->insert("date");

$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

class LongFirst extends SplHeap {
    public function compare(mixed $a, mixed $b): int {
        return strlen($a) - strlen($b);
    }
}
$h = new LongFirst;
$h->insert("aa");
$h->insert("a");
$h->insert("aaaa");
$h->insert("aaa");
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

$pq = new SplPriorityQueue;
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("med", 5);

echo count($pq), "\n";
echo $pq->top(), "\n";

$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
$out = [];
while (!$pq->isEmpty()) $out[] = $pq->extract();
print_r($out);

$pq = new SplPriorityQueue;
$pq->insert("a", 1);
$pq->insert("b", 5);
$pq->insert("c", 10);

$pq->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
$out = [];
while (!$pq->isEmpty()) $out[] = $pq->extract();
print_r($out);

$pq = new SplPriorityQueue;
$pq->insert("a", 3);
$pq->insert("b", 1);

$pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
print_r($pq->extract());

// SplPriorityQueue equal-priority ordering (architectural - PHP heap impl-specific)
$pq = new SplPriorityQueue;
$pq->insert("a", 1);
$pq->insert("b", 5);
$pq->insert("c", 10);
foreach ($pq as $v) echo "$v ";
echo "\n";

class ObjectHeap extends SplHeap {
    public function compare(mixed $a, mixed $b): int {
        return $b->n - $a->n;
    }
}

class Item { public function __construct(public int $n) {} }
$h = new ObjectHeap;
$h->insert(new Item(3));
$h->insert(new Item(1));
$h->insert(new Item(5));
$h->insert(new Item(2));

$out = [];
while (!$h->isEmpty()) $out[] = $h->extract()->n;
print_r($out);

$h = new SplMinHeap;
echo $h->count(), "\n";
echo $h->isEmpty() ? "y" : "n", "\n";

$h->insert(1);
echo $h->isEmpty() ? "y" : "n", "\n";

try {
    (new SplMinHeap)->extract();
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "rt-extract\n";
}

try {
    (new SplMinHeap)->top();
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "rt-top\n";
}

$h = new SplMinHeap;
foreach ([5, 1, 3, 8, 2, 7, 4] as $v) $h->insert($v);

echo $h->count(), "\n";
echo $h->top(), "\n";

$h2 = clone $h;
echo $h2->count(), "\n";
echo $h->extract(), "\n";
echo $h2->extract(), "\n";

// equal-priority extract order (architectural - heap impl-specific)

$h = new SplMinHeap;
foreach ([5, 1, 3, 8, 2] as $v) $h->insert($v);
foreach ($h as $k => $v) echo "$k=$v ";
echo "\n";

$h = new SplMaxHeap;
$h->insert(10);
$h->insert(20);
$h->insert(15);
foreach ($h as $v) echo $v, " ";
echo "\n";

$h = new SplMinHeap;
$h->insert(0);
$h->insert(-1);
$h->insert(1);
echo $h->extract(), "\n";
echo $h->extract(), "\n";
echo $h->extract(), "\n";
