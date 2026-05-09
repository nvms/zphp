<?php
// SplObjectStorage (use offsetSet to avoid 8.5 deprecation noise)
$s = new SplObjectStorage();
$o1 = new stdClass; $o2 = new stdClass; $o3 = new stdClass;
$s[$o1] = "data1";
$s[$o2] = "data2";
$s[$o3] = null;
foreach ($s as $obj) echo $s->getInfo() ?? "null", "|";
echo "\n";

echo isset($s[$o1]) ? "c1\n" : "n\n";
echo $s->count(), "\n";
unset($s[$o2]);
echo $s->count(), "\n";

$s[$o1] = "replaced";
echo $s[$o1], "\n";

$s2 = new SplObjectStorage();
$s2[$o2] = "from-s2";
$s->addAll($s2);
echo isset($s[$o2]) ? "y\n" : "n\n";
echo $s[$o2], "\n";

$rm = new SplObjectStorage();
$rm[$o1] = null;
$s->removeAll($rm);
echo isset($s[$o1]) ? "y\n" : "n\n";

// SplFixedArray
$fa = SplFixedArray::fromArray([10, 20, 30]);
echo $fa[0], "|", $fa[1], "|", $fa[2], "\n";
echo $fa->getSize(), "\n";
$fa->setSize(5);
echo $fa->getSize(), "\n";
var_dump($fa[3]); // null
$fa[4] = 99;
print_r($fa->toArray());

// SplPriorityQueue extract flags
$pq = new SplPriorityQueue();
$pq->insert("a", 5);
$pq->insert("b", 1);
$pq->insert("c", 3);
$pq->setExtractFlags(SplPriorityQueue::EXTR_DATA);
echo $pq->extract(), "|"; // a
$pq->setExtractFlags(SplPriorityQueue::EXTR_PRIORITY);
echo $pq->extract(), "|"; // 3
$pq->setExtractFlags(SplPriorityQueue::EXTR_BOTH);
print_r($pq->extract());

// SplHeap minimal compare
class MinHeap2 extends SplHeap {
    protected function compare($a, $b): int { return $b - $a; } // min-heap
}
$h = new MinHeap2();
foreach ([5, 1, 9, 3, 7] as $v) $h->insert($v);
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n";

// IteratorAggregate impl
class Range2 implements IteratorAggregate {
    public function __construct(private int $start, private int $end) {}
    public function getIterator(): Generator {
        for ($i = $this->start; $i <= $this->end; $i++) yield $i;
    }
}
$r = new Range2(3, 7);
foreach ($r as $v) echo "$v ";
echo "\n";
foreach ($r as $v) echo "$v ";
echo "\n";

// Countable
class Bag implements Countable {
    public function __construct(private array $items) {}
    public function count(): int { return count($this->items); }
}
echo count(new Bag([1,2,3])), "\n";

// ArrayAccess in foreach
class Indexed implements ArrayAccess, Countable, Iterator {
    private array $data = [];
    private int $pos = 0;
    private array $keys = [];
    public function set(string $k, $v): void { $this->data[$k] = $v; $this->keys = array_keys($this->data); }
    public function offsetExists($k): bool { return isset($this->data[$k]); }
    public function offsetGet($k): mixed { return $this->data[$k]; }
    public function offsetSet($k, $v): void { $this->set((string)$k, $v); }
    public function offsetUnset($k): void { unset($this->data[$k]); $this->keys = array_keys($this->data); }
    public function count(): int { return count($this->data); }
    public function current(): mixed { return $this->data[$this->keys[$this->pos]]; }
    public function key(): mixed { return $this->keys[$this->pos]; }
    public function next(): void { $this->pos++; }
    public function rewind(): void { $this->pos = 0; }
    public function valid(): bool { return $this->pos < count($this->keys); }
}
$ix = new Indexed;
$ix["a"] = 1;
$ix["b"] = 2;
$ix["c"] = 3;
echo count($ix), "\n";
foreach ($ix as $k => $v) echo "$k=$v ";
echo "\n";

// Exception getPrevious
try {
    try { throw new RuntimeException("inner"); }
    catch (Exception $e) { throw new LogicException("outer", 0, $e); }
} catch (Exception $e) {
    echo $e->getMessage(), "<-", $e->getPrevious()->getMessage(), "\n";
}

// chained Exception
class MyEx extends Exception {}
try { throw new MyEx("hi"); } catch (Exception $e) { echo get_class($e), ":", $e->getMessage(), "\n"; }

// Error vs Exception
try { throw new TypeError("type"); } catch (\Throwable $e) { echo get_class($e), "\n"; }
try { throw new ValueError("value"); } catch (\Error $e) { echo get_class($e), "\n"; }
echo (new TypeError) instanceof Error ? "y" : "n", "\n";
echo (new TypeError) instanceof Exception ? "y" : "n", "\n"; // n
echo (new TypeError) instanceof Throwable ? "y" : "n", "\n";

// finally with break in loop
function loopFinally() {
    foreach ([1, 2, 3] as $v) {
        try {
            if ($v === 2) break;
        } finally {
            echo "f$v|";
        }
    }
}
loopFinally();
echo "done\n";
