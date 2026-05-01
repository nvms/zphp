<?php

// MultipleIterator with generators
$g1 = function() { yield 1; yield 2; yield 3; };
$g2 = function() { yield 'a'; yield 'b'; yield 'c'; };

$mi = new MultipleIterator(MultipleIterator::MIT_NEED_ALL | MultipleIterator::MIT_KEYS_NUMERIC);
$mi->attachIterator($g1());
$mi->attachIterator($g2());
foreach ($mi as $values) {
    echo implode(",", $values) . "\n";
}

// MIT_NEED_ANY (length differs)
$g3 = function() { yield 'x'; yield 'y'; };
$g4 = function() { yield 1; yield 2; yield 3; };
$mi2 = new MultipleIterator(MultipleIterator::MIT_NEED_ANY);
$mi2->attachIterator($g3());
$mi2->attachIterator($g4());
foreach ($mi2 as $vs) echo implode("|", array_map(fn($v) => $v ?? "-", $vs)) . " ";
echo "\n";

// associative keys
$mi3 = new MultipleIterator(MultipleIterator::MIT_NEED_ALL | MultipleIterator::MIT_KEYS_ASSOC);
$g5 = function() { yield 1; yield 2; };
$g6 = function() { yield 'a'; yield 'b'; };
$mi3->attachIterator($g5(), 'num');
$mi3->attachIterator($g6(), 'letter');
foreach ($mi3 as $vs) {
    echo "num={$vs['num']} letter={$vs['letter']}\n";
}

// mix object iterator and generator
class CountUp implements Iterator {
    private int $i = 0;
    public function __construct(private int $max) {}
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < $this->max; }
    public function current(): int { return $this->i; }
    public function key(): int { return $this->i; }
    public function next(): void { $this->i++; }
}

$g7 = function() { yield 'a'; yield 'b'; yield 'c'; };
$mi4 = new MultipleIterator(MultipleIterator::MIT_NEED_ALL);
$mi4->attachIterator(new CountUp(3));
$mi4->attachIterator($g7());
foreach ($mi4 as $vs) echo $vs[0] . ":" . $vs[1] . " ";
echo "\n";
