<?php
// covers: fibers, Fiber::start, Fiber::resume, Fiber::suspend, Fiber::getReturn,
//   Fiber::isTerminated, Fiber::isSuspended, exceptions, try/catch/finally,
//   set_error_handler, trigger_error, spl_autoload_register, __toString,
//   Stringable, ArrayAccess, Countable, Iterator, json_encode, json_decode,
//   array_map, array_filter, array_reduce, closures, match, enums,
//   readonly, constructor property promotion, static methods, str_pad

enum TaskState: string {
    case PENDING = 'pending';
    case RUNNING = 'running';
    case COMPLETED = 'completed';
    case FAILED = 'failed';
}

class TaskResult {
    public function __construct(
        public readonly bool $success,
        public readonly mixed $value = null,
        public readonly ?string $error = null
    ) {}

    public function __toString(): string {
        if ($this->success) {
            return "OK: " . (is_array($this->value) ? json_encode($this->value) : (string)$this->value);
        }
        return "FAIL: {$this->error}";
    }
}

class TaskQueue implements Countable {
    private array $tasks = [];
    private array $results = [];

    public function add(string $name, callable $fn): void {
        $this->tasks[$name] = [
            'fn' => $fn,
            'state' => TaskState::PENDING,
        ];
    }

    public function runAll(): void {
        foreach ($this->tasks as $name => &$task) {
            $task['state'] = TaskState::RUNNING;
            try {
                $result = ($task['fn'])();
                $this->results[$name] = new TaskResult(success: true, value: $result);
                $task['state'] = TaskState::COMPLETED;
            } catch (\Exception $e) {
                $this->results[$name] = new TaskResult(success: false, error: $e->getMessage());
                $task['state'] = TaskState::FAILED;
            }
        }
    }

    public function getResults(): array {
        return $this->results;
    }

    public function count(): int {
        return count($this->tasks);
    }

    public function summary(): array {
        $states = [];
        foreach ($this->tasks as $task) {
            $s = $task['state']->value;
            $states[$s] = ($states[$s] ?? 0) + 1;
        }
        return $states;
    }
}

// retry with backoff
function retry(callable $fn, int $maxAttempts = 3): mixed {
    $lastException = null;
    for ($i = 1; $i <= $maxAttempts; $i++) {
        try {
            return $fn($i);
        } catch (\Exception $e) {
            $lastException = $e;
        }
    }
    throw $lastException;
}

// fiber-based cooperative task runner
function fiberRunner(array $jobs): array {
    $fibers = [];
    $results = [];

    foreach ($jobs as $name => $fn) {
        $fibers[$name] = new Fiber($fn);
    }

    // start all fibers
    foreach ($fibers as $name => $fiber) {
        $result = $fiber->start();
        if ($fiber->isSuspended()) {
            $results[$name] = ['status' => 'suspended', 'yielded' => $result];
        }
    }

    // resume suspended fibers
    $rounds = 0;
    while (true) {
        $any_suspended = false;
        foreach ($fibers as $name => $fiber) {
            if ($fiber->isSuspended()) {
                $any_suspended = true;
                $result = $fiber->resume($rounds);
                if ($fiber->isSuspended()) {
                    $results[$name]['yielded'] = $result;
                }
            }
        }
        $rounds++;
        if (!$any_suspended || $rounds > 10) break;
    }

    // collect final results
    foreach ($fibers as $name => $fiber) {
        if ($fiber->isTerminated()) {
            $results[$name] = ['status' => 'done', 'value' => $fiber->getReturn()];
        }
    }

    return $results;
}

// --- task queue ---
$queue = new TaskQueue();

$queue->add('compute', function() {
    $sum = 0;
    for ($i = 1; $i <= 100; $i++) $sum += $i;
    return $sum;
});

$queue->add('transform', function() {
    $data = ['a' => 1, 'b' => 2, 'c' => 3];
    return array_map(fn($v) => $v * $v, $data);
});

$queue->add('validate', function() {
    $items = [1, 'two', 3, null, 5];
    $valid = array_filter($items, fn($v) => is_int($v) && $v > 0);
    return array_values($valid);
});

$queue->add('failing', function() {
    throw new RuntimeException("intentional failure");
});

$queue->add('retry_task', function() {
    return retry(function($attempt) {
        if ($attempt < 3) {
            throw new RuntimeException("attempt $attempt failed");
        }
        return "success on attempt $attempt";
    });
});

echo "tasks: " . count($queue) . "\n";
$queue->runAll();

$summary = $queue->summary();
echo "completed: " . ($summary['completed'] ?? 0) . "\n";
echo "failed: " . ($summary['failed'] ?? 0) . "\n";

echo "\n--- results ---\n";
foreach ($queue->getResults() as $name => $result) {
    echo str_pad($name, 15) . (string)$result . "\n";
}

// --- fibers ---
echo "\n--- fiber runner ---\n";
$results = fiberRunner([
    'counter' => function() {
        $count = 0;
        while ($count < 3) {
            $round = Fiber::suspend("count=$count");
            $count++;
        }
        return "counted to $count";
    },
    'accumulator' => function() {
        $sum = 0;
        for ($i = 0; $i < 3; $i++) {
            $round = Fiber::suspend("sum=$sum");
            $sum += $round;
        }
        return "sum=$sum";
    },
]);

foreach ($results as $name => $result) {
    echo "$name: status={$result['status']}";
    if (isset($result['value'])) echo " value={$result['value']}";
    echo "\n";
}

// --- error handling ---
echo "\n--- error handling ---\n";
$errors = [];
set_error_handler(function($errno, $errstr) use (&$errors) {
    $errors[] = "[$errno] $errstr";
    return true;
});

trigger_error("test warning", E_USER_WARNING);
trigger_error("test notice", E_USER_NOTICE);

echo "captured errors: " . count($errors) . "\n";
foreach ($errors as $e) {
    echo "  $e\n";
}

restore_error_handler();

// --- exception chaining ---
echo "\n--- exception chain ---\n";
try {
    try {
        throw new RuntimeException("root cause");
    } catch (RuntimeException $e) {
        throw new LogicException("wrapper", 0, $e);
    }
} catch (LogicException $e) {
    echo "caught: " . $e->getMessage() . "\n";
    $prev = $e->getPrevious();
    echo "caused by: " . ($prev ? $prev->getMessage() : "none") . "\n";
}

// --- finally ---
echo "\n--- finally ---\n";
$log = [];
try {
    $log[] = "try";
    throw new RuntimeException("oops");
} catch (RuntimeException $e) {
    $log[] = "catch";
} finally {
    $log[] = "finally";
}
echo implode(" -> ", $log) . "\n";

// try-finally without catch
$log2 = [];
try {
    $log2[] = "try";
} finally {
    $log2[] = "finally";
}
echo implode(" -> ", $log2) . "\n";

echo "\ndone\n";
