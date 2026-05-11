<?php
// covers: generators with yield + yield-from delegation, generator return values,
//   sending values back into a generator, two-way coroutine pattern,
//   iterator_to_array with associative keys

echo "=== basic generator ===\n";
function counter(int $start, int $end): Generator {
    for ($i = $start; $i <= $end; $i++) yield $i;
}

foreach (counter(1, 5) as $n) echo "$n ";
echo "\n";

echo "\n=== yield with keys ===\n";
function fields(): Generator {
    yield 'name' => 'Alice';
    yield 'role' => 'admin';
    yield 'age' => 30;
}
foreach (fields() as $k => $v) echo "$k=$v\n";

echo "\n=== iterator_to_array preserves keys ===\n";
print_r(iterator_to_array(fields()));

echo "\n=== yield from (delegation) ===\n";
function inner(): Generator {
    yield 1; yield 2; yield 3;
}
function outer(): Generator {
    yield 0;
    yield from inner();
    yield 4;
}
foreach (outer() as $v) echo "$v ";
echo "\n";

echo "\n=== yield from with key delegation ===\n";
function inner_keys(): Generator {
    yield 'a' => 1;
    yield 'b' => 2;
}
function outer_keys(): Generator {
    yield 'x' => 9;
    yield from inner_keys();
    yield 'z' => 99;
}
foreach (outer_keys() as $k => $v) echo "$k=$v ";
echo "\n";

echo "\n=== generator return value ===\n";
function with_return(): Generator {
    yield 1; yield 2;
    return 'done';
}
$g = with_return();
foreach ($g as $v) echo "$v ";
echo "\n";
echo "return: " . $g->getReturn() . "\n";

echo "\n=== send values into generator ===\n";
function echoer(): Generator {
    while (true) {
        $msg = yield;
        if ($msg === null) return;
        echo "got: $msg\n";
    }
}
$g = echoer();
$g->current();
$g->send("hello");
$g->send("world");
$g->send(null);

echo "\n=== generator composing pipeline ===\n";
function source(): Generator {
    foreach (range(1, 10) as $n) yield $n;
}
function take(iterable $src, int $n): Generator {
    $i = 0;
    foreach ($src as $v) {
        if ($i++ >= $n) break;
        yield $v;
    }
}
function map_gen(iterable $src, callable $fn): Generator {
    foreach ($src as $v) yield $fn($v);
}
function filter_gen(iterable $src, callable $fn): Generator {
    foreach ($src as $v) if ($fn($v)) yield $v;
}

$pipeline = take(
    filter_gen(
        map_gen(source(), fn($x) => $x * $x),
        fn($x) => $x % 2 === 1,
    ),
    3,
);
foreach ($pipeline as $v) echo "$v ";
echo "\n";

echo "\n=== generator object lifecycle ===\n";
$g = counter(1, 3);
echo "valid before: " . ($g->valid() ? "yes" : "no") . "\n";
echo "current: " . $g->current() . "\n";
$g->next();
echo "after next: " . $g->current() . "\n";
$g->next();
$g->next();
echo "valid at end: " . ($g->valid() ? "yes" : "no") . "\n";
