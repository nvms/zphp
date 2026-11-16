<?php
// ReflectionFiber::getTrace() of a fiber that runs another fiber, of one
// suspended by a Fiber::suspend() a native called, and the object of an
// engine method (Fiber->start(), Generator->current()) in traces

function frames(array $trace): void {
    foreach ($trace as $f) {
        $where = isset($f["line"]) ? " line " . $f["line"] : "";
        $object = isset($f["object"]) ? " object " . get_class($f["object"]) : "";
        $name = preg_replace("/^\{closure:.*\}$/", "{closure}", $f["function"]);
        echo "  ", $f["class"] ?? "", $f["type"] ?? "", $name, $where, $object, "\n";
    }
}

function suspend_here() {
    Fiber::suspend();
}

function start_inner() {
    (new Fiber(function () {
        global $outer;
        echo "outer fiber from inside the inner one:\n";
        frames((new ReflectionFiber($outer))->getTrace());
    }))
        ->start();
}

$outer = new Fiber(function () {
    suspend_here();
    start_inner();
});
$outer->start();
$outer->resume();

$native = new Fiber(fn () => call_user_func(["Fiber", "suspend"]));
$native->start();
echo "suspended by a native:\n";
frames((new ReflectionFiber($native))->getTrace());
$native->resume();

$f = new Fiber(function () {
    echo "inside a fiber:\n";
    frames(debug_backtrace());
});
$f->start();

function gen() {
    echo "inside a generator:\n";
    frames(debug_backtrace());
    yield 1;
}
$g = gen();
$g->current();
