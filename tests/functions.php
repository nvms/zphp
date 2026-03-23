<?php
function add($a, $b) {
    return $a + $b;
}
echo add(3, 4);
echo "\n";

function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}
echo factorial(5);
echo "\n";

function greet($name) {
    return 'Hello ' . $name;
}
echo greet('World');
echo "\n";

function noreturn() {
    $x = 42;
}
$r = noreturn();
echo $r === null ? 'null' : 'not null';
echo "\n";
