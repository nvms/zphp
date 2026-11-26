<?php
// with pcntl_async_signals() on, a signal's handler runs as the internal
// call that let it in returns, called by that function

pcntl_async_signals(true);

pcntl_signal(SIGUSR1, function (int $signo, array $info): void {
    echo "handler for ", $signo === SIGUSR1 ? "SIGUSR1" : $signo, "\n";
    foreach (debug_backtrace() as $frame) {
        echo "  ", $frame['function'], isset($frame['line']) ? " line {$frame['line']}" : "", "\n";
    }
});

function send() {
    posix_kill(posix_getpid(), SIGUSR1);
    echo "after posix_kill\n";
}
send();

// what a handler throws comes out of that call
pcntl_signal(SIGUSR2, function (): void {
    throw new RuntimeException("from the handler");
});
try {
    posix_kill(posix_getpid(), SIGUSR2);
    echo "not reached\n";
} catch (RuntimeException $e) {
    echo $e->getMessage(), "\n";
}

// a handler can't switch fibers
pcntl_signal(SIGUSR1, function (): void {
    try {
        Fiber::suspend();
    } catch (FiberError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
});
$fiber = new Fiber(function (): void {
    posix_kill(posix_getpid(), SIGUSR1);
    echo "fiber goes on\n";
});
$fiber->start();

// off again: the signal waits for pcntl_signal_dispatch()
pcntl_async_signals(false);
pcntl_signal(SIGUSR1, function (): void {
    echo "dispatched\n";
});
posix_kill(posix_getpid(), SIGUSR1);
echo "before dispatch\n";
pcntl_signal_dispatch();
echo "end\n";
