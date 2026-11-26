<?php
// each step of a foreach (a generator resumed, an iterator advanced) is
// reported on the line of the iterable, where php emits FE_FETCH
function g() { yield 1; throw new Exception; }
function h() { yield 1; echo (new Exception)->getTraceAsString(), "\n"; yield 2; }
foreach (h()
    as $v) {
    echo "body\n";
}
try {
    foreach (g() as $k => $v) {
        echo "body\n";
    }
} catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
class It implements Iterator {
    private $i = 0;
    function current(): mixed { return $this->i; }
    function key(): mixed { return $this->i; }
    function next(): void { $this->i++; echo (new Exception)->getTraceAsString(), "\n"; }
    function rewind(): void { $this->i = 0; }
    function valid(): bool { return $this->i < 2; }
}
foreach (new It as $v)
{
    echo "body\n";
}
