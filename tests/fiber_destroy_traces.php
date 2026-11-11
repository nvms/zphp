<?php
// a fiber destroyed while suspended runs its finally blocks called from an
// internal function, and so does a fiber whose first call is rejected

function show(Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
}

$fiber = new Fiber(function (): void {
    try {
        Fiber::suspend();
    } finally {
        try {
            Fiber::suspend();
        } catch (FiberError $e) {
            show($e);
        }
    }
});
$fiber->start();
unset($fiber);

$fiber = new Fiber(function (): void {
    try {
        Fiber::suspend();
    } finally {
        throw new Exception("from finally");
    }
});
$fiber->start();
try {
    $fiber = null;
} catch (Exception $e) {
    show($e);
}

function takes_int(int $x) {
}
try {
    (new Fiber('takes_int'))->start("text");
} catch (TypeError $e) {
    show($e);
}
