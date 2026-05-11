<?php
function g1() {
    yield from new ArrayIterator([1, 2, 3]);
    yield 4;
}
foreach (g1() as $k => $v) echo "$k=$v ";
echo "\n";

function g2() {
    yield from [10, 20];
    yield from new ArrayIterator([30, 40]);
    yield from [50];
}
print_r(iterator_to_array(g2(), false));

class Counter implements Iterator {
    private int $i = 0;
    public function __construct(private int $max) {}
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < $this->max; }
    public function current(): mixed { return $this->i * 10; }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
}
function g3() {
    yield from new Counter(4);
    yield from new Counter(2);
}
foreach (g3() as $k => $v) echo "$k=$v ";
echo "\n";

function inner() {
    yield "a";
    yield "b";
    return "done";
}
function outer() {
    $r = yield from inner();
    yield $r;
}
foreach (outer() as $v) echo $v, " ";
echo "\n";

function gsend() {
    $sum = 0;
    while (true) {
        $v = yield;
        if ($v === null) return $sum;
        $sum += $v;
    }
}
$g = gsend();
$g->current();
$g->send(5);
$g->send(10);
$g->send(15);
$g->send(null);
echo $g->getReturn(), "\n";

function gkeys() {
    yield "x" => 1;
    yield from ["y" => 2, "z" => 3];
}
foreach (gkeys() as $k => $v) echo "$k=$v ";
echo "\n";
