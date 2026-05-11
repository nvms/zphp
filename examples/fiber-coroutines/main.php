<?php
// covers: Fiber start/resume/suspend, getReturn, isRunning/isSuspended/isTerminated,
//   getCurrent, suspend value pass-through, throw into fiber, scheduler pattern

echo "=== basic suspend / resume ===\n";
$f = new Fiber(function (): string {
    Fiber::suspend('first');
    Fiber::suspend('second');
    return 'done';
});
echo "isStarted before: " . ($f->isStarted() ? "yes" : "no") . "\n";
echo "value 1: " . $f->start() . "\n";
echo "isSuspended: " . ($f->isSuspended() ? "yes" : "no") . "\n";
echo "value 2: " . $f->resume() . "\n";
$f->resume();
echo "isTerminated: " . ($f->isTerminated() ? "yes" : "no") . "\n";
echo "return: " . $f->getReturn() . "\n";

echo "\n=== passing values into fiber via resume ===\n";
$f = new Fiber(function (): int {
    $a = Fiber::suspend('need a');
    $b = Fiber::suspend('need b');
    return $a + $b;
});
$req = $f->start();
echo "req: $req\n";
$req = $f->resume(10);
echo "req: $req\n";
$f->resume(32);
echo "result: " . $f->getReturn() . "\n";

echo "\n=== throw into fiber ===\n";
$f = new Fiber(function () {
    try {
        Fiber::suspend();
    } catch (RuntimeException $e) {
        return "caught: " . $e->getMessage();
    }
    return "no exception";
});
$f->start();
$f->throw(new RuntimeException("kaboom"));
echo $f->getReturn() . "\n";

echo "\n=== fiber-based cooperative scheduler ===\n";
class Scheduler {
    /** @var Fiber[] */
    private array $queue = [];

    public function spawn(Closure $task): void {
        $this->queue[] = new Fiber($task);
    }

    public function run(): array {
        $output = [];
        while ($this->queue) {
            $f = array_shift($this->queue);
            $value = $f->isStarted() ? $f->resume() : $f->start();
            if ($value !== null) $output[] = $value;
            if (!$f->isTerminated()) $this->queue[] = $f;
        }
        return $output;
    }
}

$s = new Scheduler();
$s->spawn(function () {
    Fiber::suspend("A: tick 1");
    Fiber::suspend("A: tick 2");
    Fiber::suspend("A: tick 3");
});
$s->spawn(function () {
    Fiber::suspend("B: tick 1");
    Fiber::suspend("B: tick 2");
});
$s->spawn(function () {
    Fiber::suspend("C: tick 1");
});

$events = $s->run();
foreach ($events as $e) echo "  $e\n";

echo "\n=== Fiber::getCurrent inside vs outside ===\n";
echo "outside: " . (Fiber::getCurrent() === null ? "null" : "not null") . "\n";
$f = new Fiber(function () {
    Fiber::suspend(Fiber::getCurrent() !== null ? "inside is non-null" : "inside is null");
});
echo $f->start() . "\n";

echo "\n=== nested fibers ===\n";
$inner_result = null;
$outer = new Fiber(function () use (&$inner_result) {
    $inner = new Fiber(function () {
        return 42;
    });
    $inner->start();
    $inner_result = $inner->getReturn();
    return $inner_result * 2;
});
$outer->start();
echo "inner: $inner_result\n";
echo "outer: " . $outer->getReturn() . "\n";
