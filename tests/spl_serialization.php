<?php
// the SPL containers serialize in php's formats and restore from them; other
// objects serialize the properties php lists, never zphp's own state
$l = new SplDoublyLinkedList; $l->push(1); $l->push('a'); $l->x = 5;
echo serialize($l), "\n";
$q = new SplQueue; $q[] = 1; echo serialize($q), "\n";
$st = new SplStack; $st[] = 1; $st[] = 2; echo serialize($st), "\n";
$s = new SplObjectStorage; $o = new stdClass; $s[$o] = 'inf'; $s[new stdClass] = null; echo serialize($s), "\n";
$f = new SplFixedArray(2); $f[0] = 'z'; echo serialize($f), "\n";
foreach (['SplMinHeap', 'SplMaxHeap', 'SplPriorityQueue'] as $c) { $h = new $c; try { echo serialize($h), "\n"; } catch (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; } }
$ao = new ArrayObject([1]); echo serialize($ao), "\n";
echo serialize(new ArrayIterator(['k' => 'v'])), "\n";
var_dump(unserialize(serialize($l)) == $l, count(unserialize(serialize($s))), unserialize(serialize($f))[0]);
print_r(unserialize(serialize($st)));
foreach ([
    'O:19:"SplDoublyLinkedList":3:{i:0;s:1:"x";i:1;a:0:{}i:2;a:0:{}}',
    'O:16:"SplObjectStorage":1:{i:0;a:0:{}}',
    'O:16:"SplObjectStorage":2:{i:0;a:1:{i:0;i:1;}i:1;a:0:{}}',
    'O:16:"SplObjectStorage":2:{i:0;a:2:{i:0;i:1;i:1;i:2;}i:1;a:0:{}}',
    'O:10:"SplMinHeap":1:{i:0;a:0:{}}',
] as $payload) {
    try { var_dump(unserialize($payload)); } catch (Throwable $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}
class Base { private $hidden = 'b'; protected $shared = 's'; }
class Leaf extends Base { public $open = 'o'; public int $typed; private $own = 'l'; }
echo serialize(new Leaf), "\n";
print_r(unserialize(serialize(new Leaf)));
$h = new SplMaxHeap; foreach ([4, 9, 1, 7] as $n) $h->insert($n);
$copy = unserialize(serialize($h));
while (!$copy->isEmpty()) echo $copy->extract(), ' ';
echo "\n";
$pq = new SplPriorityQueue; $pq->insert('x', 1); $pq->insert('y', 3); $pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
print_r(unserialize(serialize($pq))->extract());
