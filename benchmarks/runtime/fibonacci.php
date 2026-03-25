<?php
// recursive fibonacci - tests function call overhead and recursion
function fib(int $n): int {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}

$result = fib(32);
echo "$result\n";
