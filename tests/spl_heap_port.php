<?php
// SplHeap, SplMinHeap, SplMaxHeap and SplPriorityQueue as php's spl_heap has them

function show($label, $f) {
    try {
        $r = $f();
        echo $label, ': ';
        var_dump($r);
    } catch (Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}

$min = new SplMinHeap();
show('extract empty', fn() => $min->extract());
show('top empty', fn() => $min->top());
show('current empty', fn() => $min->current());
foreach ([5, 1, 3, 1, 4, 2, 9, 0] as $v) $min->insert($v);
var_dump($min);
foreach ($min as $k => $v) echo "$k=>$v ";
echo "\n", count($min), "\n";

$max = new SplMaxHeap();
foreach (['b', 'a', 'd', 'c', [1], [0, 1]] as $v) $max->insert($v);
while ($max->valid()) {
    echo json_encode($max->current()), ' ';
    $max->next();
}
echo "\n";

$pq = new SplPriorityQueue();
show('pq extract empty', fn() => $pq->extract());
show('pq top empty', fn() => $pq->top());
show('pq current empty', fn() => $pq->current());
show('flags zero', fn() => $pq->setExtractFlags(0));
foreach (['a' => 3, 'b' => 1, 'c' => 3, 'd' => 2, 'e' => 3] as $d => $p) $pq->insert($d, $p);
var_dump($pq->getExtractFlags(), count($pq));
$pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
var_dump($pq->top());
$pq->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
var_dump($pq->extract());
$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
foreach ($pq as $k => $v) echo "$k=>$v ";
echo "\n";
var_dump($pq->compare(1, 2), $pq->compare(2, 2), $pq->compare('b', 'a'));

echo "-- corruption\n";
class ThrowingHeap extends SplMinHeap {
    public $throw = false;
    protected function compare($a, $b): int {
        if ($this->throw) throw new Exception('compare failed');
        return parent::compare($a, $b);
    }
}
$h = new ThrowingHeap();
$h->insert(1);
$h->insert(2);
$h->throw = true;
show('insert', fn() => $h->insert(3));
var_dump($h->isCorrupted(), count($h));
show('top', fn() => $h->top());
show('extract', fn() => $h->extract());
show('serialize', fn() => serialize($h));
$h->recoverFromCorruption();
$h->throw = false;
var_dump($h->isCorrupted(), $h->extract());

echo "-- write lock\n";
class LockHeap extends SplMaxHeap {
    protected function compare($a, $b): int {
        try {
            $this->insert(0);
        } catch (RuntimeException $e) {
            echo $e->getMessage(), "\n";
        }
        return parent::compare($a, $b);
    }
}
$l = new LockHeap();
$l->insert(1);
$l->insert(2);
var_dump(count($l));

echo "-- serialization\n";
$pq2 = new SplPriorityQueue();
$pq2->insert('x', 1);
$pq2->insert('y', 2);
$s = serialize($pq2);
echo $s, "\n";
var_dump(unserialize($s));
$mh = new SplMaxHeap();
$mh->insert(3);
$mh->insert(7);
echo serialize($mh), "\n";
var_dump(unserialize(serialize($mh)));
show('bad flags', fn() => unserialize('O:16:"SplPriorityQueue":2:{i:0;a:0:{}i:1;a:2:{s:5:"flags";i:0;s:13:"heap_elements";a:0:{}}}'));
show('bad heap flags', fn() => unserialize('O:10:"SplMaxHeap":2:{i:0;a:0:{}i:1;a:2:{s:5:"flags";i:1;s:13:"heap_elements";a:0:{}}}'));
$c = clone $min;
$c->insert(-1);
var_dump(count($min), count($c), $c->top());

foreach ([new SplMinHeap, new SplPriorityQueue] as $x) {
    try {
        foreach ($x as &$ref) {}
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
show('abstract', fn() => new SplHeap());
