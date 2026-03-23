<?php
$counter = 10;

function readGlobal() {
    global $counter;
    return $counter;
}
echo readGlobal() . "\n";

function counting() {
    static $n = 0;
    $n++;
    return $n;
}
echo counting() . "\n";
echo counting() . "\n";
echo counting() . "\n";
