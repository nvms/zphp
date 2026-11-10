<?php
// Fiber's methods follow php's zend_fibers.c: error messages, the
// Fiber->method() frames in traces, and callables that aren't closures
// running as the fiber's own frames

function attempt(callable $f) {
    try {
        $f();
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$fiber = new Fiber(function (int $x) {
    $y = Fiber::suspend($x * 2);
    return $y + 1;
});
attempt(fn () => $fiber->getReturn());
var_dump($fiber->start(21));
attempt(fn () => $fiber->getReturn());
attempt(fn () => $fiber->start());
var_dump($fiber->resume(10));
var_dump($fiber->getReturn());
attempt(fn () => $fiber->resume());
attempt(fn () => $fiber->throw(new Exception("late")));
attempt(fn () => $fiber->__construct(fn () => 1));

$failing = new Fiber(function () {
    Fiber::suspend();
    throw new RuntimeException("failed");
});
$failing->start();
attempt(fn () => $failing->resume());
attempt(fn () => $failing->getReturn());

attempt(fn () => Fiber::suspend(1));
attempt(fn () => new FiberError("nope"));
attempt(fn () => new Generator);
attempt(fn () => new Fiber("no_such_function"));
function takes_int(int $x) {
    return $x;
}
attempt(fn () => (new Fiber('takes_int'))->start("text"));

class Task {
    public function __invoke($label) {
        $got = Fiber::suspend("$label suspended");
        echo "$label got $got\n";
        return "$label done";
    }
    public function run($label) {
        return $this($label);
    }
}
$f = new Fiber(new Task);
var_dump($f->start("invokable"));
$f->resume("value");
var_dump($f->getReturn());
$f = new Fiber([new Task, 'run']);
var_dump($f->start("method"));
$f->resume("value");
var_dump($f->getReturn());

function inner_function() {
    debug_print_backtrace();
    throw new LogicException("traced");
}
$f = new Fiber(function () {
    Fiber::suspend();
    inner_function();
});
$f->start();
try {
    $f->resume();
} catch (LogicException $e) {
    echo $e->getTraceAsString(), "\n";
}
