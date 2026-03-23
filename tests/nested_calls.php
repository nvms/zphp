<?php
function double($n) {
    return $n * 2;
}

function square($n) {
    return $n * $n;
}

echo double(5);
echo "\n";
echo square(4);
echo "\n";
echo double(square(3));
echo "\n";
echo square(double(3));
echo "\n";

function fib($n) {
    if ($n <= 1) {
        return $n;
    }
    return fib($n - 1) + fib($n - 2);
}
echo fib(10);
echo "\n";
