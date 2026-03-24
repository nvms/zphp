<?php

// lazy data pipeline using generators, closures, and chaining

function fromArray(array $items): Generator
{
    foreach ($items as $k => $v) {
        yield $k => $v;
    }
}

function mapGen(Generator $gen, callable $fn): Generator
{
    foreach ($gen as $k => $v) {
        yield $k => $fn($v);
    }
}

function filterGen(Generator $gen, callable $fn): Generator
{
    foreach ($gen as $k => $v) {
        if ($fn($v)) yield $k => $v;
    }
}

function takeGen(Generator $gen, int $n): Generator
{
    $i = 0;
    foreach ($gen as $k => $v) {
        if ($i >= $n) return;
        yield $k => $v;
        $i++;
    }
}

function toArray(Generator $gen): array
{
    $result = [];
    foreach ($gen as $v) {
        $result[] = $v;
    }
    return $result;
}

function reduce(Generator $gen, callable $fn, $initial)
{
    $acc = $initial;
    foreach ($gen as $v) {
        $acc = $fn($acc, $v);
    }
    return $acc;
}

// infinite sequence generators
function naturals(int $start = 1): Generator
{
    $n = $start;
    while (true) {
        yield $n;
        $n++;
    }
}

function fibonacci(): Generator
{
    $a = 0;
    $b = 1;
    while (true) {
        yield $a;
        $temp = $a + $b;
        $a = $b;
        $b = $temp;
    }
}

// === test: basic pipeline ===

$data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$result = toArray(
    filterGen(
        mapGen(
            fromArray($data),
            function ($x) { return $x * $x; }
        ),
        function ($x) { return $x > 10; }
    )
);
echo "squares > 10: " . implode(", ", $result) . "\n";

// === test: take from infinite sequence ===

$firstTen = toArray(takeGen(naturals(), 10));
echo "first 10: " . implode(", ", $firstTen) . "\n";

// === test: fibonacci ===

$fibs = toArray(takeGen(fibonacci(), 10));
echo "fibonacci: " . implode(", ", $fibs) . "\n";

// === test: reduce ===

$sum = reduce(fromArray([1, 2, 3, 4, 5]), function ($acc, $v) { return $acc + $v; }, 0);
echo "sum: $sum\n";

// === test: complex pipeline with records ===

$users = [
    ["name" => "Alice", "age" => 30, "active" => true],
    ["name" => "Bob", "age" => 17, "active" => true],
    ["name" => "Charlie", "age" => 45, "active" => false],
    ["name" => "Diana", "age" => 28, "active" => true],
    ["name" => "Eve", "age" => 15, "active" => true],
    ["name" => "Frank", "age" => 35, "active" => true],
];

// active adults
$activeAdults = toArray(
    mapGen(
        filterGen(
            filterGen(
                fromArray($users),
                function ($u) { return $u["active"]; }
            ),
            function ($u) { return $u["age"] >= 18; }
        ),
        function ($u) { return $u["name"]; }
    )
);
echo "active adults: " . implode(", ", $activeAdults) . "\n";

// === test: generator with send ===

function accumulator(): Generator
{
    $total = 0;
    while (true) {
        $value = yield $total;
        if ($value === null) return;
        $total += $value;
    }
}

$acc = accumulator();
$acc->current(); // init
$acc->send(10);
$acc->send(20);
$result = $acc->send(30);
echo "accumulated: " . $acc->current() . "\n";

// === test: yield from ===

function inner(): Generator
{
    yield 1;
    yield 2;
    yield 3;
}

function outer(): Generator
{
    yield 0;
    yield from inner();
    yield 4;
}

$combined = toArray(outer());
echo "yield from: " . implode(", ", $combined) . "\n";

// === test: generator as data transformer ===

function csvRows(array $lines): Generator
{
    foreach ($lines as $line) {
        yield str_getcsv($line);
    }
}

function withHeaders(Generator $rows): Generator
{
    $headers = null;
    foreach ($rows as $row) {
        if ($headers === null) {
            $headers = $row;
            continue;
        }
        $record = [];
        foreach ($headers as $i => $h) {
            $record[$h] = $row[$i] ?? "";
        }
        yield $record;
    }
}

$csv = [
    "name,age,city",
    "Alice,30,NYC",
    "Bob,25,LA",
    "Charlie,35,Chicago",
];

$records = toArray(withHeaders(csvRows($csv)));
foreach ($records as $r) {
    echo "{$r['name']} is {$r['age']} from {$r['city']}\n";
}

// === test: nested generators ===

function range2(int $start, int $end): Generator
{
    for ($i = $start; $i <= $end; $i++) {
        yield $i;
    }
}

function chunks(Generator $gen, int $size): Generator
{
    $chunk = [];
    foreach ($gen as $v) {
        $chunk[] = $v;
        if (count($chunk) === $size) {
            yield $chunk;
            $chunk = [];
        }
    }
    if (count($chunk) > 0) yield $chunk;
}

$batches = toArray(chunks(range2(1, 10), 3));
foreach ($batches as $batch) {
    echo "[" . implode(",", $batch) . "] ";
}
echo "\n";

// === test: exception in generator ===

function riskyGenerator(): Generator
{
    yield 1;
    yield 2;
    throw new RuntimeException("generator error");
}

try {
    foreach (riskyGenerator() as $v) {
        echo "got: $v\n";
    }
} catch (RuntimeException $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

echo "done\n";
