<?php
// the operand of |> is evaluated before the callable, and is passed as a value
function foo() { echo __FUNCTION__, PHP_EOL; return 1; }
function bar() { echo __FUNCTION__, PHP_EOL; return false; }
function baz($in) { echo __FUNCTION__, PHP_EOL; return $in; }
function quux($in) { echo __FUNCTION__, PHP_EOL; return $in + 10; }
$result = foo()
    |> (bar() ? baz(...) : quux(...))
    |> var_dump(...);

function addOne(int &$n): int { return ++$n; }
$n = 5;
try {
    $n |> addOne(...);
} catch (Error $e) {
    echo $e->getMessage(), PHP_EOL;
}
var_dump($n);
echo "hello" |> strtoupper(...) |> (fn($s) => "$s!"), PHP_EOL;
$double = fn($x) => $x * 2;
var_dump(21 |> $double);
