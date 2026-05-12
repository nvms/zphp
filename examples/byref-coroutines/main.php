<?php
// covers: by-ref params interacting with generators, fibers, and closures.
//   pre-fix these patterns had subtle ref_slot/cell bugs; this example
//   pins down the matrix so future ref-handling regressions get caught.

echo "=== generator with by-ref param to outer state ===\n";
function pump(int &$counter): Generator {
    for ($i = 0; $i < 3; $i++) {
        $counter++;
        yield $counter;
    }
}
$n = 100;
foreach (pump($n) as $v) echo "  yielded $v\n";
echo "after pump: $n\n";

echo "\n=== two generator instances over distinct by-ref targets ===\n";
$a = 0; $b = 0;
function makeGen(int &$x): Generator {
    for ($i = 0; $i < 2; $i++) {
        $x++;
        yield $x;
    }
}
$ga = makeGen($a);
$gb = makeGen($b);
foreach ($ga as $v) echo "  a-gen: $v\n";
foreach ($gb as $v) echo "  b-gen: $v\n";
echo "a=$a, b=$b\n";

echo "\n=== yield-from with by-ref propagating mutations ===\n";
function inner(int &$n): Generator {
    yield $n;
    $n *= 2;
    yield $n;
}
function outer(int &$n): Generator {
    yield from inner($n);
    yield $n + 1000;
}
$m = 5;
foreach (outer($m) as $v) echo "  $v\n";
echo "final m: $m\n";

echo "\n=== function called by-ref inside generator body ===\n";
function inc(int &$x): void { $x++; }
function counterGen(int $start, int $count): Generator {
    $n = $start;
    for ($i = 0; $i < $count; $i++) {
        inc($n);
        yield $n;
    }
}
foreach (counterGen(10, 4) as $v) echo "  $v\n";

echo "\n=== fiber + function with by-ref array param survives suspend ===\n";
function mutateArray(array &$arr): void {
    $arr[] = 'before';
    Fiber::suspend();
    $arr[] = 'after';
}
$f = new Fiber(function () {
    $data = [];
    mutateArray($data);
    return $data;
});
$f->start();
$f->resume();
print_r($f->getReturn());

echo "=== fiber + generator that takes by-ref array ===\n";
function consumer(array &$buf): Generator {
    while (!empty($buf)) yield array_shift($buf);
}
$f = new Fiber(function () {
    $items = ['x', 'y', 'z', 'w'];
    $out = [];
    foreach (consumer($items) as $v) {
        $out[] = $v;
        if (count($out) === 2) Fiber::suspend("paused at 2");
    }
    return [$out, $items];
});
echo "start: " . $f->start() . "\n";
$f->resume();
print_r($f->getReturn());

echo "=== closure with use(&) inside generator body ===\n";
function chained(): Generator {
    $shared = 0;
    $bump = function () use (&$shared) { $shared++; };
    for ($i = 0; $i < 3; $i++) {
        $bump();
        yield $shared;
    }
}
foreach (chained() as $v) echo "  $v\n";

echo "\n=== nested by-ref through generator -> function -> array ===\n";
function pushTo(array &$arr, $v): void { $arr[] = $v; }
function builder(): Generator {
    $list = [];
    pushTo($list, 'a');
    yield count($list);
    pushTo($list, 'b');
    yield count($list);
    pushTo($list, 'c');
    yield $list;
}
foreach (builder() as $v) {
    if (is_array($v)) print_r($v); else echo "  count: $v\n";
}

echo "=== fiber holds a captured-by-ref state across multiple suspends ===\n";
function makeWorker(array &$state): Closure {
    return function ($delta) use (&$state) {
        $state['count'] += $delta;
        $state['history'][] = $delta;
    };
}
$f = new Fiber(function () {
    $state = ['count' => 0, 'history' => []];
    $w = makeWorker($state);
    $w(5);
    Fiber::suspend();
    $w(10);
    Fiber::suspend();
    $w(-3);
    return $state;
});
$f->start();
$f->resume();
$f->resume();
print_r($f->getReturn());

echo "=== matrix mutation with nested foreach by-ref (the synth-var-name bug) ===\n";
$grid = [[1, 2, 3], [4, 5, 6]];
foreach ($grid as &$row) {
    foreach ($row as &$cell) {
        $cell *= 10;
    }
}
unset($row, $cell);
print_r($grid);

echo "done\n";
