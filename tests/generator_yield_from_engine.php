<?php
// yield from follows php's ZEND_YIELD_FROM: its errors, a Traversable
// iterated as the generator runs (an exception from the iterator reaches
// the generator at the yield from), a delegate already started keeping its
// current value, and an aborted delegate shared by two generators

function attempt(Generator $g) {
    try {
        foreach ($g as $k => $v) {
            echo "$k => $v\n";
        }
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

function from_value($v) {
    yield from $v;
}
attempt(from_value(42));
attempt(from_value(new stdClass));

function aborted() {
    yield 1;
    throw new Exception("aborted");
}
$a = aborted();
foreach ($a as $v) {
    try {
        $a->next();
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
    }
}
attempt(from_value($a));

function self_delegating() {
    yield from yield;
}
try {
    ($g = self_delegating())->send($g);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

class Counting implements Iterator {
    private $i = 0;
    function __construct(private $throwAt) {}
    function rewind(): void { echo "rewind\n"; $this->i = 0; }
    function valid(): bool {
        echo "valid\n";
        if ($this->i === $this->throwAt) throw new RuntimeException("valid at {$this->i}");
        return $this->i < 3;
    }
    function current(): mixed { echo "current\n"; return $this->i * 10; }
    function key(): mixed { echo "key\n"; return "k{$this->i}"; }
    function next(): void { echo "next\n"; $this->i++; }
}
function over_iterator($it) {
    try {
        $result = yield from $it;
        var_dump($result);
    } catch (RuntimeException $e) {
        echo "generator caught ", $e->getMessage(), "\n";
    }
    yield "after" => "done";
}
attempt(over_iterator(new Counting(-1)));
attempt(over_iterator(new Counting(2)));

class Aggregate implements IteratorAggregate {
    function getIterator(): Iterator {
        echo "getIterator\n";
        return new ArrayIterator(["x" => 1, "y" => 2]);
    }
}
attempt(from_value(new Aggregate));

function counter() {
    yield 1;
    yield 2;
}
$c = counter();
$c->valid();
attempt(from_value($c));

function from_shared($g) {
    try {
        var_dump(yield from $g);
    } catch (Exception $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$shared = aborted();
$gens = [from_shared($shared), from_shared($shared)];
foreach ($gens as $g) {
    $g->current();
}
foreach ($gens as $i => $g) {
    echo "generator $i\n";
    var_dump($g->current());
    $g->next();
}
var_dump($gens[0]->valid(), $gens[1]->valid());
