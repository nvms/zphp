<?php
// covers: pcntl_fork, pcntl_waitpid, pcntl_wexitstatus, pcntl_wifexited,
//   pcntl_wifsignaled, pcntl_wtermsig, pcntl_signal, pcntl_signal_dispatch,
//   posix_getpid, posix_kill, SIGUSR1, SIGTERM

echo "=== fork + wait ===\n";
$children = [];
for ($i = 1; $i <= 3; $i++) {
    $pid = pcntl_fork();
    if ($pid === 0) {
        // child
        exit($i * 2);
    }
    $children[] = ['pid' => $pid, 'expected' => $i * 2];
}

$results = [];
foreach ($children as $c) {
    $status = 0;
    pcntl_waitpid($c['pid'], $status);
    $results[] = [
        'expected' => $c['expected'],
        'exited' => pcntl_wifexited($status),
        'status' => pcntl_wexitstatus($status),
    ];
}

// sort for deterministic output (children may finish in any order)
usort($results, fn($a, $b) => $a['expected'] <=> $b['expected']);
foreach ($results as $r) {
    echo sprintf(
        "  exit %d (wifexited=%s expected=%d)\n",
        $r['status'],
        $r['exited'] ? 'yes' : 'no',
        $r['expected'],
    );
}

echo "\n=== child terminated by signal ===\n";
$pid = pcntl_fork();
if ($pid === 0) {
    posix_kill(posix_getpid(), SIGTERM);
    exit(0);
}
$status = 0;
pcntl_waitpid($pid, $status);
echo "wifsignaled: " . (pcntl_wifsignaled($status) ? "yes" : "no") . "\n";
echo "termsig: " . pcntl_wtermsig($status) . " (SIGTERM=" . SIGTERM . ")\n";

echo "\n=== signal handler ===\n";
$caught = null;
pcntl_signal(SIGUSR1, function ($sig) use (&$caught) {
    $caught = $sig;
});
posix_kill(posix_getpid(), SIGUSR1);
usleep(10000);
pcntl_signal_dispatch();
echo "caught SIGUSR1: " . ($caught === SIGUSR1 ? "yes" : "no") . "\n";

echo "\n=== async signals flag toggle ===\n";
$was = pcntl_async_signals(true);
echo "previous: " . ($was ? "true" : "false") . "\n";
$was = pcntl_async_signals(false);
echo "now: " . ($was ? "true" : "false") . "\n";
