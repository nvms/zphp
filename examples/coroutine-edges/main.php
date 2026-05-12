<?php
// covers: fiber+generator interactions, exception across suspends,
//   nested fibers, generator with by-ref param, fiber-throw semantics.
//   (fiber + by-ref function param is a known limitation - see CLAUDE.md)

echo "=== generator with by-ref param mutates caller across yields ===\n";
function progressLog(array &$log): Generator {
    $log[] = 'start';
    yield 'first';
    $log[] = 'middle';
    yield 'second';
    $log[] = 'end';
}
$entries = [];
foreach (progressLog($entries) as $step) echo "  step: $step\n";
print_r($entries);

echo "=== fiber + generator: generator runs inside fiber body ===\n";
function genN(int $n): Generator {
    for ($i = 1; $i <= $n; $i++) yield $i;
}
$f = new Fiber(function () {
    $sum = 0;
    foreach (genN(5) as $v) {
        $sum += $v;
        Fiber::suspend("running total = $sum");
    }
    return $sum;
});
while (!$f->isTerminated()) {
    $val = $f->isStarted() ? $f->resume() : $f->start();
    if ($val !== null) echo "  $val\n";
}
echo "final: " . $f->getReturn() . "\n";

echo "\n=== exception thrown after suspend, caught inside fiber ===\n";
$f = new Fiber(function () {
    try {
        Fiber::suspend('about to throw');
        throw new RuntimeException('post-suspend');
    } catch (RuntimeException $e) {
        return "caught: " . $e->getMessage();
    }
});
echo $f->start() . "\n";
$f->resume();
echo $f->getReturn() . "\n";

echo "\n=== nested fibers ===\n";
$outer = new Fiber(function () {
    $inner = new Fiber(function () {
        Fiber::suspend('inner-1');
        return 'inner-done';
    });
    $v = $inner->start();
    echo "  outer got: $v\n";
    Fiber::suspend('outer-middle');
    $inner->resume();
    return $inner->getReturn();
});
echo "first: " . $outer->start() . "\n";
echo "resume: " . $outer->resume() . "\n";
echo "outer ret: " . $outer->getReturn() . "\n";

echo "\n=== Fiber::throw routes through fiber's catch ===\n";
$f = new Fiber(function () {
    try {
        Fiber::suspend('waiting');
        return 'no-throw';
    } catch (LogicException $e) {
        return 'caught: ' . $e->getMessage();
    }
});
$f->start();
echo $f->throw(new LogicException('cancel')) . "\n";
echo $f->getReturn() . "\n";

echo "\n=== captured-by-ref closure modifies outer across nested calls ===\n";
function makeAcc(): array {
    $total = 0;
    $count = 0;
    return [
        'add' => function (int $n) use (&$total, &$count) {
            $total += $n;
            $count++;
        },
        'stats' => function () use (&$total, &$count) {
            return ['total' => $total, 'count' => $count, 'avg' => $count > 0 ? $total / $count : 0];
        },
    ];
}
$acc = makeAcc();
foreach ([10, 20, 30, 40] as $n) $acc['add']($n);
print_r($acc['stats']());

echo "=== closure with \$this is bound late (live object reference) ===\n";
class Stamper {
    public string $prefix = '>>';
    public function makeWrapper(): Closure {
        return fn(string $s) => $this->prefix . $s;
    }
}
$t = new Stamper();
$w = $t->makeWrapper();
echo $w('hello') . "\n";
$t->prefix = '!!';
echo $w('hello') . "\n";

echo "\ndone\n";
