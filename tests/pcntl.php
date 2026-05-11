<?php
// covers: pcntl_fork, pcntl_waitpid, pcntl_wifexited, pcntl_wexitstatus, pcntl_signal, pcntl_alarm, pcntl_signal_dispatch, pcntl_async_signals

assert(defined('SIGTERM'));
assert(defined('SIGUSR1'));
assert(defined('SIG_DFL'));
assert(defined('SIG_IGN'));
assert(defined('WNOHANG'));

// fork a child that exits with status 7
$pid = pcntl_fork();
assert($pid !== -1);
if ($pid === 0) {
    exit(7);
}
$status = 0;
$w = pcntl_waitpid($pid, $status);
assert($w === $pid);
assert(pcntl_wifexited($status));
assert(pcntl_wexitstatus($status) === 7);

// signal handler
$received = 0;
pcntl_signal(SIGUSR1, function ($sig) use (&$received) {
    $received = $sig;
});

posix_kill(posix_getpid(), SIGUSR1);
// give kernel a moment to deliver
usleep(10000);
pcntl_signal_dispatch();
assert($received === SIGUSR1);

// SIG_IGN
pcntl_signal(SIGUSR2, SIG_IGN);
posix_kill(posix_getpid(), SIGUSR2);
usleep(10000);
pcntl_signal_dispatch();

// alarm returns previous (was 0)
$prev = pcntl_alarm(0);
assert($prev === 0);

// async signals toggle returns previous state
$was = pcntl_async_signals(true);
assert($was === false);
$was = pcntl_async_signals(false);
assert($was === true);

// status decode helpers on a known fork result
$pid2 = pcntl_fork();
if ($pid2 === 0) {
    posix_kill(posix_getpid(), SIGTERM);
    exit(0);
}
$st = 0;
pcntl_waitpid($pid2, $st);
assert(pcntl_wifsignaled($st));
assert(pcntl_wtermsig($st) === SIGTERM);

echo "ok\n";
