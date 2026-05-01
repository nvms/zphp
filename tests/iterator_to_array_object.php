<?php

// iterator_to_array on Iterator-implementing object
class Range implements Iterator {
    private int $i = 0;
    public function __construct(private int $from, private int $to) {}
    public function rewind(): void { $this->i = $this->from; }
    public function valid(): bool { return $this->i <= $this->to; }
    public function current(): int { return $this->i; }
    public function key(): int { return $this->i - $this->from; }
    public function next(): void { $this->i++; }
}

print_r(iterator_to_array(new Range(1, 5)));
print_r(iterator_to_array(new Range(10, 13), false));

// IteratorAggregate
class Names implements IteratorAggregate {
    public function __construct(private array $items) {}
    public function getIterator(): Iterator { return new ArrayIterator($this->items); }
}
print_r(iterator_to_array(new Names(['a', 'b', 'c'])));

// SplFixedArray
$fa = SplFixedArray::fromArray([10, 20, 30, 40]);
print_r(iterator_to_array($fa));
echo array_sum(iterator_to_array($fa)) . "\n";

// generator (already worked)
function gen() { yield 'k1' => 1; yield 'k2' => 2; }
print_r(iterator_to_array(gen()));

// Generator instanceof Traversable / Iterator (LazyCollection-style chains)
function genFn() { yield 1; yield 2; }
$g = genFn();
echo ($g instanceof Traversable ? "yes" : "no") . "\n";
echo ($g instanceof Iterator ? "yes" : "no") . "\n";
echo ($g instanceof Generator ? "yes" : "no") . "\n";
