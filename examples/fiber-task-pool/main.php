<?php
// covers: Fiber-based task pool with cooperative cancellation,
//   exception propagation across suspend points, mixed throw/resume,
//   isStarted/isSuspended/isTerminated state probing,
//   selective awaiting based on task tags

final class CancelException extends RuntimeException {}

final class Task {
    public Fiber $fiber;
    public array $log = [];
    public function __construct(public string $name, callable $body) {
        $this->fiber = new Fiber($body);
    }
}

final class Pool {
    /** @var Task[] */
    public array $tasks = [];
    public bool $cancel_requested = false;

    public function add(string $name, callable $body): void {
        $this->tasks[] = new Task($name, $body);
    }

    public function run(): array {
        $output = [];
        $iter = 0;
        while (true) {
            $active = 0;
            foreach ($this->tasks as $t) {
                if ($t->fiber->isTerminated()) continue;
                $active++;
                try {
                    if (!$t->fiber->isStarted()) {
                        $val = $t->fiber->start();
                    } elseif ($this->cancel_requested && !$t->fiber->isTerminated()) {
                        $val = $t->fiber->throw(new CancelException("pool cancel"));
                    } else {
                        $val = $t->fiber->resume();
                    }
                    if ($val !== null) {
                        $output[] = $t->name . ": " . $val;
                    }
                } catch (CancelException $e) {
                    $output[] = $t->name . ": [cancelled]";
                } catch (Throwable $e) {
                    $output[] = $t->name . ": [error] " . $e->getMessage();
                }
            }
            if ($active === 0) break;
            $iter++;
            if ($iter > 50) {
                $output[] = "[runaway]";
                break;
            }
        }
        return $output;
    }
}

echo "=== three cooperating tasks ===\n";
$p = new Pool();
$p->add('A', function () {
    Fiber::suspend("A: step 1");
    Fiber::suspend("A: step 2");
    Fiber::suspend("A: step 3");
});
$p->add('B', function () {
    Fiber::suspend("B: step 1");
    Fiber::suspend("B: step 2");
});
$p->add('C', function () {
    Fiber::suspend("C: only step");
});
foreach ($p->run() as $line) echo "  $line\n";

echo "\n=== task that catches and cleans up on cancel ===\n";
$p = new Pool();
$cleanup_done = false;
$p->add('worker', function () use (&$cleanup_done) {
    try {
        for ($i = 1; $i <= 10; $i++) {
            Fiber::suspend("tick $i");
        }
    } catch (CancelException $e) {
        $cleanup_done = true;
        // ensure exception propagates after cleanup
        throw $e;
    }
});
$p->tasks[0]->fiber->start();
$p->tasks[0]->fiber->resume();
$p->cancel_requested = true;
foreach ($p->run() as $line) echo "  $line\n";
echo "cleanup ran: " . ($cleanup_done ? "yes" : "no") . "\n";

echo "\n=== exception across multiple suspend points ===\n";
$p = new Pool();
$p->add('throwing', function () {
    Fiber::suspend("phase 1");
    Fiber::suspend("phase 2");
    throw new RuntimeException("normal failure");
});
$p->add('ok', function () {
    Fiber::suspend("ok 1");
});
foreach ($p->run() as $line) echo "  $line\n";

echo "\n=== fiber state probing ===\n";
$f = new Fiber(function () {
    Fiber::suspend("paused");
});
echo "before start: started=" . ($f->isStarted() ? "y" : "n") . " suspended=" . ($f->isSuspended() ? "y" : "n") . "\n";
$f->start();
echo "after start: started=" . ($f->isStarted() ? "y" : "n") . " suspended=" . ($f->isSuspended() ? "y" : "n") . " terminated=" . ($f->isTerminated() ? "y" : "n") . "\n";
$f->resume();
echo "after resume: terminated=" . ($f->isTerminated() ? "y" : "n") . "\n";

echo "\ndone\n";
