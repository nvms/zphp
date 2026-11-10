<?php
// an arrow function whose expression yields is a generator

$numbers = fn ($n) => yield from range(1, $n);
foreach ($numbers(3) as $v) {
    echo $v, "\n";
}
$echo = fn () => yield;
$g = $echo();
$g->current();
$g->send("sent");
var_dump($g->getReturn());
var_dump((fn () => yield 1)() instanceof Generator);
