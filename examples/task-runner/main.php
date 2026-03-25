<?php
// covers: fibers (suspend/resume, getReturn), constructor property promotion,
//   readonly properties, spread operator in calls,
//   late static binding (static::class), clone with __clone,
//   array_map, pass-by-reference, json_encode/json_decode,
//   string interpolation, static properties, abstract classes,
//   match expressions, inheritance with promoted properties

abstract class Task {
    private static int $nextId = 0;

    public function __construct(public readonly string $name, public readonly int $priority = 0) {
        self::$nextId = self::$nextId + 1;
    }

    abstract public function execute(): string;

    public static function getCounter(): int {
        return self::$nextId;
    }
}

class PrintTask extends Task {
    public function __construct(public readonly string $message, string $name = "print", int $priority = 0) {
        parent::__construct($name, $priority);
    }

    public function execute(): string {
        return "printed: {$this->message}";
    }
}

class ComputeTask extends Task {
    public function __construct(public readonly int $value, string $name = "compute", int $priority = 0) {
        parent::__construct($name, $priority);
    }

    public function execute(): string {
        $result = 0;
        for ($i = 1; $i <= $this->value; $i++) {
            $result += $i * $i;
        }
        return "computed: $result";
    }
}

class TaskResult {
    public ?string $error = null;
    public float $duration = 0.0;

    public function __construct(public readonly string $taskName, public readonly ?string $output = null) {}

    public function __clone(): void {
        $this->duration = 999.0;
    }
}

class SpecialTask extends Task {
    public function execute(): string {
        return "special from " . static::class;
    }
}

class TaskRunner {
    private array $tasks = [];
    private array $results = [];

    public function add(Task ...$tasks): void {
        foreach ($tasks as $t) {
            $this->tasks[] = $t;
        }
    }

    public function run(): array {
        // sort by priority descending (bubble sort to avoid closure-in-fiber interaction)
        for ($i = 0; $i < count($this->tasks); $i++) {
            for ($j = $i + 1; $j < count($this->tasks); $j++) {
                if ($this->tasks[$j]->priority > $this->tasks[$i]->priority) {
                    $tmp = $this->tasks[$i];
                    $this->tasks[$i] = $this->tasks[$j];
                    $this->tasks[$j] = $tmp;
                }
            }
        }

        foreach ($this->tasks as $task) {
            $output = $task->execute();
            $result = new TaskResult($task->name, $output);
            $result->duration = 0.001;
            echo "ran: {$task->name}\n";
            $this->results[] = $result;
        }

        return $this->results;
    }
}

function testJsonRoundTrip(): void {
    $data = ["name" => "serializable", "message" => "hello world", "priority" => 5];
    $json = json_encode($data);
    $restored = json_decode($json, true);
    echo "json name: {$restored['name']}\n";
    echo "json message: {$restored['message']}\n";
    echo "json priority: {$restored['priority']}\n";
}

function transformResults(array $results): array {
    $getOutput = function (TaskResult $r): string {
        return $r->output ?? "error: {$r->error}";
    };
    return array_map($getOutput, $results);
}

function countErrors(array $results, int &$errorCount): void {
    foreach ($results as $r) {
        if ($r->error !== null) {
            $errorCount++;
        }
    }
}

// fiber test (standalone, no closure capture interaction)
$fiber = new Fiber(function () {
    $x = 10;
    Fiber::suspend("paused with $x");
    return $x * 2;
});
echo "fiber: " . $fiber->start() . "\n";
$fiber->resume();
echo "fiber result: " . $fiber->getReturn() . "\n";

$runner = new TaskRunner();
$runner->add(
    new PrintTask("hello", "print", 2),
    new ComputeTask(5, "sum-squares", 3),
    new SpecialTask("special", 0)
);
$results = $runner->run();

$outputs = transformResults($results);
foreach ($outputs as $o) {
    echo "output: $o\n";
}

$errors = 0;
countErrors($results, $errors);
echo "total errors: $errors\n";

$cloned = clone $results[0];
echo "cloned output: {$cloned->output}\n";

echo "tasks created: " . Task::getCounter() . "\n";

testJsonRoundTrip();

foreach ($results as $r) {
    $status = match(true) {
        str_contains($r->output ?? "", "computed") => "COMPUTED",
        str_contains($r->output ?? "", "special") => "SPECIAL",
        default => "OK"
    };
    echo "{$r->taskName}: $status\n";
}

echo "done\n";
