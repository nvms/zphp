<?php
// covers: SplDoublyLinkedList, SplObjectStorage, closures with use(&$ref), ob_start, ob_get_clean, nested output buffering, named regex captures (?P<name>), preg_match_all PREG_SET_ORDER, generators with send(), priority queue insertion, exception handling in generators
error_reporting(E_ALL & ~E_DEPRECATED);

// DSL parser with named regex
function parseJobDef(string $line): ?array {
    $pattern = '/^(?P<name>[a-z_]+)\s*\[(?P<priority>\d+)\]\s*:\s*(?P<action>.+)$/';
    if (preg_match($pattern, $line, $m)) {
        return ['name' => $m['name'], 'priority' => (int)$m['priority'], 'action' => trim($m['action'])];
    }
    return null;
}

function parseAllTags(string $text): array {
    $pattern = '/\{(?P<tag>[a-z]+):(?P<value>[^}]+)\}/';
    preg_match_all($pattern, $text, $matches, PREG_SET_ORDER);
    $result = [];
    foreach ($matches as $m) { $result[$m['tag']] = $m['value']; }
    return $result;
}

$defs = ['send_email [10] : notify user', 'generate_report [5] : monthly stats', 'cleanup [1] : remove temp files', 'invalid', 'deploy [8] : push to prod'];
$parsed = [];
foreach ($defs as $line) { $r = parseJobDef($line); if ($r !== null) $parsed[] = $r; }
echo count($parsed) . " parsed\n";
foreach ($parsed as $p) echo $p['name'] . ":" . $p['priority'] . "\n";
$tags = parseAllTags("Hello {name:World} at {time:noon}");
echo $tags['name'] . "," . $tags['time'] . "\n";

// now the job queue (same as gen_test7 but with regex stuff first)
class Job {
    public string $name;
    public int $priority;
    public $handler;
    public string $status = 'pending';
    public ?string $output = null;
    public ?string $error = null;
    public function __construct(string $name, int $priority, callable $handler) {
        $this->name = $name; $this->priority = $priority; $this->handler = $handler;
    }
}

class Queue {
    private SplDoublyLinkedList $pending;
    private SplDoublyLinkedList $completed;
    private SplObjectStorage $metadata;
    private array $stats = ['processed' => 0, 'failed' => 0, 'total_output_bytes' => 0];

    public function __construct() {
        $this->pending = new SplDoublyLinkedList();
        $this->completed = new SplDoublyLinkedList();
        $this->metadata = new SplObjectStorage();
    }
    public function enqueue(Job $job): void {
        $inserted = false;
        for ($i = 0; $i < $this->pending->count(); $i++) {
            if ($job->priority > $this->pending[$i]->priority) {
                $this->pending->add($i, $job); $inserted = true; break;
            }
        }
        if (!$inserted) $this->pending->push($job);
        $this->metadata->attach($job, ['enqueued_at' => time(), 'attempts' => 0]);
    }
    private function bumpAttempts(Job $job): void {
        $info = $this->metadata[$job];
        if (is_array($info)) { $info['attempts']++; $this->metadata[$job] = $info; }
    }
    public function processNext(): ?Job {
        if ($this->pending->isEmpty()) return null;
        $job = $this->pending->shift(); $this->bumpAttempts($job);
        ob_start();
        try { ($job->handler)($job); $job->status = 'done'; $job->output = ob_get_clean(); $this->stats['processed']++; }
        catch (\Exception $e) { $job->output = ob_get_clean(); $job->status = 'failed'; $job->error = $e->getMessage(); $this->stats['failed']++; }
        if ($job->output !== null) $this->stats['total_output_bytes'] += strlen($job->output);
        $this->completed->push($job); return $job;
    }
    public function processAll(): void { while (!$this->pending->isEmpty()) $this->processNext(); }
    public function recentFirst(): array {
        $this->completed->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
        $result = [];
        for ($this->completed->rewind(); $this->completed->valid(); $this->completed->next()) $result[] = $this->completed->current()->name;
        $this->completed->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
        return $result;
    }
    public function trackedJobs(): array {
        $names = [];
        $this->metadata->rewind();
        while ($this->metadata->valid()) { $names[] = $this->metadata->current()->name; $this->metadata->next(); }
        return $names;
    }
    public function scheduler(): Generator {
        while (!$this->pending->isEmpty()) {
            $job = $this->pending->shift();
            $command = yield $job;
            if ($command === 'skip') { $job->status = 'skipped'; $this->completed->push($job); continue; }
            $this->bumpAttempts($job);
            ob_start();
            try { ($job->handler)($job); $job->status = 'done'; $job->output = ob_get_clean(); $this->stats['processed']++; }
            catch (\Exception $e) { $job->output = ob_get_clean(); $job->status = 'failed'; $job->error = $e->getMessage(); $this->stats['failed']++; }
            $this->completed->push($job);
        }
    }
    public function completedCount(): int { return $this->completed->count(); }
    public function pendingCount(): int { return $this->pending->count(); }
    public function getStats(): array { return $this->stats; }
}

$executionOrder = [];
$q = new Queue();
$q->enqueue(new Job('low', 1, function($j) use (&$executionOrder) { $executionOrder[] = $j->name; echo "lo"; }));
$q->enqueue(new Job('high', 10, function($j) use (&$executionOrder) { $executionOrder[] = $j->name; echo "hi"; }));
$q->enqueue(new Job('mid', 5, function($j) use (&$executionOrder) { $executionOrder[] = $j->name; echo "mi"; }));
$q->enqueue(new Job('fail', 7, function($j) { throw new \RuntimeException("boom"); }));
echo "pending: " . $q->pendingCount() . "\n";
$q->processAll();
echo "\npending: " . $q->pendingCount() . "\n";
echo "completed: " . $q->completedCount() . "\n";
echo "order: " . implode(",", $executionOrder) . "\n";
$stats = $q->getStats();
echo "processed: " . $stats['processed'] . "\n";
echo "failed: " . $stats['failed'] . "\n";
echo "recent: " . implode(",", $q->recentFirst()) . "\n";
echo "tracked: " . count($q->trackedJobs()) . "\n";

// generator on queue2
$q2 = new Queue();
$order2 = [];
$q2->enqueue(new Job('task_a', 3, function($j) use (&$order2) { $order2[] = $j->name; echo "A"; }));
$q2->enqueue(new Job('task_b', 2, function($j) use (&$order2) { $order2[] = $j->name; echo "B"; }));
$q2->enqueue(new Job('task_c', 1, function($j) use (&$order2) { $order2[] = $j->name; echo "C"; }));

$gen = $q2->scheduler();
$gen->rewind();
while ($gen->valid()) {
    $job = $gen->current();
    if ($job->name === 'task_b') { $gen->send('skip'); } else { $gen->send('run'); }
}
echo "\nscheduler order: " . implode(",", $order2) . "\n";
echo "scheduler completed: " . $q2->completedCount() . "\n";

// nested output buffering
ob_start();
echo "outer";
ob_start();
echo "inner";
$inner = ob_get_clean();
echo "+captured";
$outer = ob_get_clean();
echo "inner=" . $inner . "\n";
echo "outer=" . $outer . "\n";
echo "DONE\n";
