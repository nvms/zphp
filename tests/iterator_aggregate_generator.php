<?php

// IteratorAggregate that yields a Generator from getIterator
class Range implements IteratorAggregate {
    public function __construct(private int $from, private int $to) {}
    public function getIterator(): Generator {
        for ($i = $this->from; $i <= $this->to; $i++) yield $i;
    }
}

$r = new Range(1, 5);
foreach ($r as $v) echo $v . " ";
echo "\n";

// foreach the same instance twice (each call to getIterator returns a fresh generator)
foreach ($r as $v) echo $v . " ";
echo "\n";

// IteratorAggregate yielding key=>value pairs
class Pairs implements IteratorAggregate {
    public function __construct(private array $data) {}
    public function getIterator(): Generator {
        foreach ($this->data as $k => $v) yield $k => $v;
    }
}

$p = new Pairs(['a' => 1, 'b' => 2, 'c' => 3]);
foreach ($p as $k => $v) echo "$k=$v ";
echo "\n";

// IteratorAggregate via direct getIterator() call
$g = $r->getIterator();
echo get_class($g) . "\n";
foreach ($g as $v) echo $v . " ";
echo "\n";

// nested foreach over different IteratorAggregates
class Tree implements IteratorAggregate {
    public function __construct(private array $children) {}
    public function getIterator(): Generator { yield from $this->children; }
}
$outer = new Tree([new Range(1, 2), new Range(10, 11), new Range(100, 102)]);
foreach ($outer as $inner) {
    foreach ($inner as $v) echo $v . " ";
    echo "| ";
}
echo "\n";
