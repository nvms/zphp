<?php
// a generator that takes new variables after it started and ends with an
// exception releases them

function gen() {
    $g = yield;
    $more = [1, 2, 3];
    $other = "text";
    $g->send($g);
}
$gen = gen();
try {
    $gen->send($gen);
} catch (Throwable $e) {
    echo $e->getMessage(), "\n";
}
var_dump($gen->valid());
