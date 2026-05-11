<?php
// covers: pcntl_fork + pcntl_waitpid worker pool, graceful shutdown via
//   pcntl_signal + signal_dispatch, exit-code based result collection.
//   "fork-per-task" pattern - parent dispatches work, children compute and exit.

function compute_task(int $n): int {
    // deterministic, side-effect-free: sum 1..n squared mod 256 so it fits in exit code
    $sum = 0;
    for ($i = 1; $i <= $n; $i++) $sum += $i * $i;
    return $sum % 256;
}

function run_pool(array $inputs, int $max_concurrent): array {
    $pending = $inputs;
    $running = []; // pid => input
    $results = [];

    while ($pending || $running) {
        while ($pending && count($running) < $max_concurrent) {
            $next = array_shift($pending);
            $pid = pcntl_fork();
            if ($pid === 0) {
                exit(compute_task($next));
            }
            $running[$pid] = $next;
        }

        if ($running) {
            $status = 0;
            $done = pcntl_waitpid(-1, $status);
            if ($done > 0 && isset($running[$done])) {
                $input = $running[$done];
                unset($running[$done]);
                if (pcntl_wifexited($status)) {
                    $results[$input] = pcntl_wexitstatus($status);
                } else {
                    $results[$input] = null;
                }
            }
        }
    }

    return $results;
}

echo "=== correctness: 4-way pool vs serial baseline ===\n";
$inputs = [3, 5, 7, 10, 13, 17, 20];
$results = run_pool($inputs, 4);
ksort($results);
foreach ($inputs as $n) {
    $expected = compute_task($n);
    $got = $results[$n] ?? -1;
    echo sprintf("  n=%-3d expected=%-3d got=%-3d %s\n", $n, $expected, $got, $expected === $got ? "ok" : "MISMATCH");
}

echo "\n=== concurrency: bigger batch ===\n";
$big = range(1, 20);
$big_results = run_pool($big, 6);
$correct = 0;
foreach ($big as $n) if (($big_results[$n] ?? -1) === compute_task($n)) $correct++;
echo "matched: $correct/" . count($big) . "\n";

echo "\n=== graceful shutdown via SIGUSR1 ===\n";
$shutdown_requested = false;
pcntl_signal(SIGUSR1, function () use (&$shutdown_requested) {
    $shutdown_requested = true;
});

$cycles = 0;
$max_cycles = 8;
while ($cycles < $max_cycles) {
    if ($cycles === 3) {
        posix_kill(posix_getpid(), SIGUSR1);
        usleep(5000);
    }
    pcntl_signal_dispatch();
    if ($shutdown_requested) {
        echo "shutdown after $cycles cycles\n";
        break;
    }
    $cycles++;
}
assert($cycles === 3);

echo "\n=== child failure surfaced through exit status ===\n";
$pid = pcntl_fork();
if ($pid === 0) {
    posix_kill(posix_getpid(), SIGTERM);
    exit(0);
}
$status = 0;
pcntl_waitpid($pid, $status);
echo "wifexited: " . (pcntl_wifexited($status) ? "yes" : "no") . "\n";
echo "wifsignaled: " . (pcntl_wifsignaled($status) ? "yes" : "no") . "\n";
echo "wtermsig matches SIGTERM: " . (pcntl_wtermsig($status) === SIGTERM ? "yes" : "no") . "\n";

echo "\n=== pool empty case ===\n";
$empty = run_pool([], 4);
echo "result count: " . count($empty) . "\n";
