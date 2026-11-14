<?php
// unpacking into a call or an array literal takes arrays and Traversables,
// int or string keys, and in a call no position after a name

function test(...$args) { return $args; }
function keyed() { yield 1.5 => 'a'; }
function numeric() { yield "42" => 42; yield "x" => 1; }

$null = null;
$int = 7;
$str = "foo";
$cases = [
    'call null' => fn() => test(...$null),
    'call int' => fn() => test(...$int),
    'call object' => fn() => test(...new stdClass),
    'call string' => fn() => test(1, ...$str),
    'array null' => fn() => [...$null],
    'array int' => fn() => [1, ...$int],
    'call float key' => fn() => test(...keyed()),
    'array float key' => fn() => [...keyed()],
    'call named then positional' => fn() => test(...new ArrayIterator([1, 'a' => 2, 3])),
    'call named arrays' => fn() => test(...['a' => 1], ...[2]),
    'array numeric string key' => fn() => [...numeric()],
    'array mixed' => fn() => [...[1, 2, 'foo' => 3, 4], ...new ArrayIterator(['foo' => 5, 6])],
    'call names' => fn() => test(1, ...['a' => 2, 'b' => 3]),
];
foreach ($cases as $name => $case) {
    try {
        $result = json_encode($case());
        echo $name, ": ", $result, "\n";
    } catch (Error $e) {
        echo $name, ": ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
