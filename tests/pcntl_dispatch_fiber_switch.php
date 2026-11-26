<?php
// a signal handler pcntl_signal_dispatch() runs may not switch fibers, and
// what it throws leaves the dispatch
pcntl_signal(SIGUSR1, function (): void {
    if (Fiber::getCurrent() !== null) {
        Fiber::suspend();
    }
});

$fiber = new Fiber(function (): void {
    echo "Fiber start\n";
    posix_kill(posix_getpid(), SIGUSR1);
    try {
        pcntl_signal_dispatch();
    } catch (FiberError $e) {
        Fiber::suspend($e);
    }
    echo "Fiber end\n";
});

$e = $fiber->start();
echo get_class($e), ": ", $e->getMessage(), "\n";
$fiber->resume();

pcntl_signal(SIGUSR2, function (int $signo): void {
    throw new RuntimeException("handler for $signo");
});
posix_kill(posix_getpid(), SIGUSR2);
try {
    pcntl_signal_dispatch();
    echo "not reached\n";
} catch (RuntimeException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump(pcntl_signal_dispatch());
