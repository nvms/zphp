<?php
// yield from runs the innermost generator directly, as php's generator tree
// does, so a long chain of delegations needs no native stack per level

function from($i)
{
    yield $i;
}

function gen($i = 0)
{
    if ($i < 20000) {
        yield from gen($i + 1);
    } else {
        yield $i;
        yield from from($i + 1);
    }
}

foreach (gen() as $v) {
    var_dump($v);
}

// return values come back up the chain
function depth($n)
{
    if ($n === 0) {
        yield "leaf";
        return 0;
    }
    $r = yield from depth($n - 1);
    return $r + 1;
}
$g = depth(5000);
foreach ($g as $k => $v) {
    var_dump($k, $v);
}
var_dump($g->getReturn());

// send() reaches the innermost generator
function echoer()
{
    while (true) {
        $got = yield;
        if ($got === null) {
            return "done";
        }
        echo "inner got $got\n";
    }
}
function relay($n)
{
    return $n === 0 ? yield from echoer() : yield from relay($n - 1);
}
$r = relay(100);
$r->current();
$r->send("a");
$r->send("b");
$r->send(null);
var_dump($r->valid(), $r->getReturn());

// an exception from a delegate is thrown at the yield from
function failsLater()
{
    yield 1;
    throw new RuntimeException("later");
}
function failsAtOnce()
{
    throw new RuntimeException("at once");
    yield 1;
}
function catcher($inner)
{
    try {
        yield from $inner();
    } catch (RuntimeException $e) {
        echo "caught ", $e->getMessage(), "\n";
        yield "after";
    }
}
foreach (catcher('failsLater') as $v) {
    var_dump($v);
}
foreach (catcher('failsAtOnce') as $v) {
    var_dump($v);
}
function uncaught()
{
    yield from catcher(function () {
        yield 1;
        throw new LogicException("not caught");
    });
}
try {
    foreach (uncaught() as $v) {
        var_dump($v);
    }
} catch (LogicException $e) {
    echo "outside: ", $e->getMessage(), "\n";
}

// throw() into the outer generator reaches the innermost one
function guarded()
{
    try {
        yield 1;
    } catch (Exception $e) {
        echo "inner caught ", $e->getMessage(), "\n";
        yield 2;
    }
}
function wrapper()
{
    yield from guarded();
    yield 3;
}
$w = wrapper();
var_dump($w->current());
var_dump($w->throw(new Exception("thrown in")));
$w->next();
var_dump($w->current());

// delegating to a generator that already started, and to arrays
function counter()
{
    yield 1;
    yield 2;
    yield 3;
}
$started = counter();
$started->next();
function takeOver($g)
{
    yield from $g;
    yield from [10, 20];
    yield from new ArrayIterator([30]);
}
foreach (takeOver($started) as $k => $v) {
    echo "$k => $v\n";
}

// backtraces list the generators waiting in yield from between the running
// delegate and the code that resumed them
function innerTrace()
{
    yield 1;
    throw new Exception("from the innermost");
}
function middleTrace()
{
    yield from innerTrace();
}
function outerTrace()
{
    yield from middleTrace();
}
function startsThrowing()
{
    throw new Exception("at the start");
    yield;
}
function wrapsStart()
{
    yield from startsThrowing();
}
foreach (['outerTrace', 'wrapsStart'] as $make) {
    try {
        // (one line: zphp places a foreach's advance on the body's line)
        foreach ($make() as $v) var_dump($v);
    } catch (Exception $e) {
        echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
    }
}
function printsTrace($n)
{
    yield 1;
    debug_print_backtrace();
    var_dump(count(debug_backtrace()), count(debug_backtrace(0, 2)));
    yield 2;
}
function delegatesTrace($n)
{
    yield from printsTrace($n);
}
foreach (delegatesTrace(7) as $v) var_dump($v);
// an exception's trace shows generator frames with their arguments
function leafWithArgs($a, $b)
{
    yield 1;
    throw new Exception("args");
}
function midWithArgs($c)
{
    yield from leafWithArgs($c, 2);
}
try {
    foreach (midWithArgs("q") as $v) var_dump($v);
} catch (Exception $e) {
    echo $e->getTraceAsString(), "\n";
}
