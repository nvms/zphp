<?php
// covers: generator edge cases - throw into generator, partial consumption,
//   getReturn after exception, valid()/current()/key()/send() interactions,
//   yield-from with array, multiple generators interleaved

echo "=== throw into generator handled internally ===\n";
function maybe_throws(): Generator {
    try {
        yield 'first';
        yield 'second';
    } catch (RuntimeException $e) {
        yield 'caught: ' . $e->getMessage();
        return 'recovered';
    }
    return 'normal-end';
}

$g = maybe_throws();
echo "1: " . $g->current() . "\n";
echo "2: " . $g->throw(new RuntimeException('boom')) . "\n";
$g->next();
echo "return: " . $g->getReturn() . "\n";

echo "\n=== throw into generator that doesn't handle ===\n";
function unhandled(): Generator {
    yield 1;
    yield 2;
}
$g = unhandled();
$g->current();
try {
    $g->throw(new LogicException('not caught'));
    echo "no propagate\n";
} catch (LogicException $e) {
    echo "propagated: " . $e->getMessage() . "\n";
}
echo "terminated valid: " . ($g->valid() ? "yes" : "no") . "\n";

echo "\n=== partial consumption then abandon ===\n";
function counter(): Generator {
    for ($i = 1; $i <= 100; $i++) yield $i;
    return 'count-finished';
}
$g = counter();
$first_three = [];
foreach ($g as $v) {
    $first_three[] = $v;
    if ($v >= 3) break;
}
echo "took: " . implode(',', $first_three) . "\n";
echo "still valid: " . ($g->valid() ? "yes" : "no") . "\n";
// drop reference; generator state cleaned up at end
unset($g);

echo "\n=== send() bi-directional ===\n";
function compute(): Generator {
    $sum = 0;
    while (true) {
        $n = yield $sum;
        if ($n === null) return;
        $sum += $n;
    }
}
$g = compute();
echo "initial: " . $g->current() . "\n";
echo "after send 5: " . $g->send(5) . "\n";
echo "after send 10: " . $g->send(10) . "\n";
echo "after send 7: " . $g->send(7) . "\n";
$g->send(null);
echo "final valid: " . ($g->valid() ? "yes" : "no") . "\n";

echo "\n=== yield from array preserves keys ===\n";
function delegating(): Generator {
    yield 'start' => 0;
    yield from ['a' => 1, 'b' => 2, 'c' => 3];
    yield 'end' => 99;
}
foreach (delegating() as $k => $v) echo "  $k => $v\n";

echo "\n=== interleaved generators ===\n";
function letters(): Generator {
    foreach (['a','b','c','d'] as $l) yield $l;
}
function numbers(): Generator {
    foreach ([1,2,3,4] as $n) yield $n;
}
$l = letters();
$n = numbers();
while ($l->valid() && $n->valid()) {
    echo $l->current() . $n->current() . " ";
    $l->next();
    $n->next();
}
echo "\n";

echo "\n=== rewind() on a started generator throws ===\n";
function gen_no_rewind(): Generator { yield 1; yield 2; }
$g = gen_no_rewind();
$g->current();
$g->next();
try {
    $g->rewind();
    echo "rewind allowed\n";
} catch (Exception $e) {
    echo "rewind rejected: " . get_class($e) . "\n";
}

echo "\n=== generator with file handle survives full consumption ===\n";
function lines(string $content): Generator {
    foreach (explode("\n", $content) as $line) {
        if ($line === '') continue;
        yield $line;
    }
}
$all = [];
foreach (lines("a\nb\nc\nd") as $line) $all[] = $line;
echo "lines: " . implode(',', $all) . "\n";

echo "\n=== chained pipeline (filter + map) ===\n";
function source(): Generator { foreach (range(1, 10) as $n) yield $n; }
function only_even(iterable $src): Generator {
    foreach ($src as $v) if ($v % 2 === 0) yield $v;
}
function squared(iterable $src): Generator {
    foreach ($src as $v) yield $v * $v;
}
$pipeline = squared(only_even(source()));
$result = iterator_to_array($pipeline, false);
echo implode(',', $result) . "\n";

echo "\ndone\n";
