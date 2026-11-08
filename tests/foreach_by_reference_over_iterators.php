<?php
// foreach by reference: php refuses iterators (an ArrayIterator whose
// current() is its own excepted) and generators that don't yield by reference
class It implements Iterator { private $i = 0; function valid(): bool { return $this->i < 2; } function next(): void { $this->i++; } function rewind(): void { $this->i = 0; } function current(): mixed { return $this->i; } function key(): mixed { return $this->i; } }
class Agg implements IteratorAggregate { function getIterator(): Iterator { return new It; } }
class AggA implements IteratorAggregate { function getIterator(): Iterator { return new ArrayIterator([1, 2]); } }
class MyAI extends ArrayIterator {}
class CurAI extends ArrayIterator { function current(): mixed { return parent::current(); } }
function gen() { yield 1; yield 2; }
function &rgen() { $a = 1; yield $a; }
$cases = [
  'iterator' => fn() => new It,
  'aggregate' => fn() => new Agg,
  'aggregate of ArrayIterator' => fn() => new AggA,
  'generator' => fn() => gen(),
  'ref generator' => fn() => rgen(),
  'ArrayIterator' => fn() => new ArrayIterator([1, 2]),
  'ArrayIterator subclass' => fn() => new MyAI([1, 2]),
  'ArrayIterator with current()' => fn() => new CurAI([1, 2]),
  'ArrayObject' => fn() => new ArrayObject([1, 2]),
  'SplFixedArray' => fn() => SplFixedArray::fromArray([1, 2]),
  'SplDoublyLinkedList' => function () { $l = new SplDoublyLinkedList; $l->push(1); return $l; },
  'SplObjectStorage' => fn() => new SplObjectStorage,
  'stdClass' => function () { $o = new stdClass; $o->a = 1; return $o; },
  'plain object' => fn() => new class { public $a = 1; public $b = 2; },
];
foreach ($cases as $name => $make) {
    $it = $make();
    try {
        foreach ($it as $k => &$v) { echo "$name: $k\n"; if ($k > 3) break; }
        unset($v);
        echo "$name: done\n";
    } catch (Throwable $e) {
        echo "$name: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
