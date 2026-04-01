<?php
// covers: generators, yield, yield from, send, getReturn, generator delegation,
//   yield from array, generator in class method, generator pipelines,
//   yield with keys, nested generators, try/catch/finally in generators,
//   complex control flow in generators, interleaved generators, round-robin

// === test: send and getReturn ===
echo "=== send and getReturn ===\n";

function collector(): Generator
{
    $items = [];
    while (true) {
        $value = yield count($items);
        if ($value === null) {
            break;
        }
        $items[] = $value;
    }
    return implode(',', $items);
}

$gen = collector();
echo "init: " . $gen->current() . "\n";
$gen->send('alpha');
echo "after alpha: " . $gen->current() . "\n";
$gen->send('beta');
echo "after beta: " . $gen->current() . "\n";
$gen->send('gamma');
echo "after gamma: " . $gen->current() . "\n";
$gen->send(null);
echo "return: " . $gen->getReturn() . "\n";

// === test: yield from delegation ===
echo "\n=== yield from delegation ===\n";

function innerGen(): Generator
{
    yield 'a';
    yield 'b';
    return 'inner-done';
}

function outerGen(): Generator
{
    yield 'start';
    $result = yield from innerGen();
    echo "delegated return: $result\n";
    yield 'end';
}

foreach (outerGen() as $v) {
    echo "val: $v\n";
}

// === test: yield from array ===
echo "\n=== yield from array ===\n";

function fromArrays(): Generator
{
    yield from [10, 20, 30];
    yield from ['x' => 40, 'y' => 50];
    yield 60;
}

foreach (fromArrays() as $k => $v) {
    echo "$k => $v\n";
}

// === test: generator in class method ===
echo "\n=== generator in class method ===\n";

class NumberRange
{
    private int $start;
    private int $end;

    public function __construct(int $start, int $end)
    {
        $this->start = $start;
        $this->end = $end;
    }

    public function even(): Generator
    {
        for ($i = $this->start; $i <= $this->end; $i++) {
            if ($i % 2 === 0) {
                yield $i;
            }
        }
    }

    public function odd(): Generator
    {
        for ($i = $this->start; $i <= $this->end; $i++) {
            if ($i % 2 !== 0) {
                yield $i;
            }
        }
    }
}

$range = new NumberRange(1, 10);
$evens = [];
foreach ($range->even() as $n) {
    $evens[] = $n;
}
echo "evens: " . implode(', ', $evens) . "\n";

$odds = [];
foreach ($range->odd() as $n) {
    $odds[] = $n;
}
echo "odds: " . implode(', ', $odds) . "\n";

// === test: generator pipeline ===
echo "\n=== generator pipeline ===\n";

function integers(int $from, int $to): Generator
{
    for ($i = $from; $i <= $to; $i++) {
        yield $i;
    }
}

function doubled(Generator $gen): Generator
{
    foreach ($gen as $v) {
        yield $v * 2;
    }
}

function onlyDivisibleBy(Generator $gen, int $d): Generator
{
    foreach ($gen as $v) {
        if ($v % $d === 0) {
            yield $v;
        }
    }
}

function take(Generator $gen, int $n): Generator
{
    $i = 0;
    foreach ($gen as $v) {
        if ($i >= $n) return;
        yield $v;
        $i++;
    }
}

$pipeline = take(
    onlyDivisibleBy(
        doubled(integers(1, 100)),
        6
    ),
    5
);

$results = [];
foreach ($pipeline as $v) {
    $results[] = $v;
}
echo "pipeline: " . implode(', ', $results) . "\n";

// === test: yield with keys ===
echo "\n=== yield with keys ===\n";

function indexedWords(): Generator
{
    $words = ['hello', 'world', 'foo', 'bar'];
    foreach ($words as $i => $w) {
        yield strtoupper($w) => strlen($w);
    }
}

foreach (indexedWords() as $k => $v) {
    echo "$k: $v\n";
}

// === test: nested generators ===
echo "\n=== nested generators ===\n";

function matrix(): Generator
{
    for ($row = 0; $row < 3; $row++) {
        yield $row => rowGen($row);
    }
}

function rowGen(int $row): Generator
{
    for ($col = 0; $col < 3; $col++) {
        yield ($row * 3) + $col + 1;
    }
}

foreach (matrix() as $rowIdx => $rowGenerator) {
    $cells = [];
    foreach ($rowGenerator as $cell) {
        $cells[] = $cell;
    }
    echo "row $rowIdx: " . implode(', ', $cells) . "\n";
}

// === test: try/catch/finally in generator ===
echo "\n=== try/catch/finally ===\n";

function guardedGen(): Generator
{
    try {
        yield 'before';
        yield 'middle';
        yield 'after';
    } catch (Exception $e) {
        yield 'caught: ' . $e->getMessage();
    } finally {
        yield 'finally';
    }
}

$g = guardedGen();
$vals = [];
foreach ($g as $v) {
    $vals[] = $v;
}
echo "guarded: " . implode(', ', $vals) . "\n";

function throwingGen(): Generator
{
    try {
        yield 'step1';
        throw new RuntimeException('boom');
    } catch (RuntimeException $e) {
        yield 'handled: ' . $e->getMessage();
    } finally {
        yield 'cleanup';
    }
}

$out4 = [];
foreach (throwingGen() as $v) {
    $out4[] = $v;
}
echo "throwing: " . implode(', ', $out4) . "\n";

// === test: complex control flow ===
echo "\n=== complex control flow ===\n";

function controlFlow(array $items): Generator
{
    foreach ($items as $item) {
        if ($item < 0) {
            continue;
        }
        if ($item > 100) {
            break;
        }

        switch (true) {
            case $item < 10:
                yield "small:$item";
                break;
            case $item < 50:
                yield "medium:$item";
                break;
            default:
                yield "large:$item";
                break;
        }
    }
}

$items = [5, -3, 25, 75, -1, 8, 200, 42];
$out = [];
foreach (controlFlow($items) as $v) {
    $out[] = $v;
}
echo implode(', ', $out) . "\n";

function loopYield(): Generator
{
    for ($i = 0; $i < 5; $i++) {
        if ($i === 2) continue;
        if ($i === 4) break;
        yield $i;
    }
    yield 99;
}

$out2 = [];
foreach (loopYield() as $v) {
    $out2[] = $v;
}
echo implode(', ', $out2) . "\n";

// === test: interleaved generators (round-robin) ===
echo "\n=== interleaved generators ===\n";

function letters(): Generator
{
    yield 'A';
    yield 'B';
    yield 'C';
}

function numbers(): Generator
{
    yield 1;
    yield 2;
    yield 3;
    yield 4;
}

function symbols(): Generator
{
    yield '@';
    yield '#';
}

function roundRobin(array $generators): Generator
{
    $active = $generators;
    foreach ($active as $g) {
        $g->current();
    }
    while (count($active) > 0) {
        $next = [];
        foreach ($active as $g) {
            if ($g->valid()) {
                yield $g->current();
                $g->next();
                if ($g->valid()) {
                    $next[] = $g;
                }
            }
        }
        $active = $next;
    }
}

$rr = roundRobin([letters(), numbers(), symbols()]);
$out3 = [];
foreach ($rr as $v) {
    $out3[] = $v;
}
echo implode(', ', $out3) . "\n";

echo "\ndone\n";
