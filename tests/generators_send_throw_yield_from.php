<?php
function counter() {
    $i = 0;
    while (true) {
        $cmd = yield $i;
        if ($cmd === "stop") return $i;
        if ($cmd === "reset") $i = 0;
        else $i++;
    }
}

$g = counter();
echo $g->current(), "\n";
$g->send("inc");
echo $g->current(), "\n";
$g->send("inc");
echo $g->current(), "\n";
$g->send("reset");
echo $g->current(), "\n";
$g->send("stop");
echo $g->valid() ? "y" : "n", "\n";
echo $g->getReturn(), "\n";

function adder($init) {
    $sum = $init;
    while (true) {
        $v = yield $sum;
        if ($v === null) return $sum;
        $sum += $v;
    }
}

$g = adder(10);
echo $g->current(), "\n";
echo $g->send(5), "\n";
echo $g->send(7), "\n";
echo $g->send(3), "\n";
$g->send(null);
echo $g->getReturn(), "\n";

function thrower() {
    try {
        yield 1;
        yield 2;
    } catch (\Exception $e) {
        yield "caught:" . $e->getMessage();
    }
    yield 3;
}

$g = thrower();
echo $g->current(), "\n";
echo $g->throw(new \Exception("boom")), "\n";
$g->next();
echo $g->current(), "\n";

function inner() {
    yield 1;
    yield 2;
    yield 3;
    return "inner-done";
}

function outer() {
    yield 0;
    $r = yield from inner();
    yield "ret:" . $r;
    yield 99;
}

foreach (outer() as $v) echo $v, "\n";

function nestedDelegate() {
    yield from [10, 20, 30];
    yield from inner();
    yield "end";
}
foreach (nestedDelegate() as $k => $v) echo $k, "=>", $v, "\n";

function noReturn() {
    yield 1;
    yield 2;
}
$g = noReturn();
foreach ($g as $v);
echo var_export($g->getReturn(), true), "\n";

function withReturn() {
    yield 1;
    return "done";
}
$g = withReturn();
try { $g->getReturn(); echo "no\n"; } catch (\Exception $e) { echo "ex\n"; }
foreach ($g as $v);
echo $g->getReturn(), "\n";

function uncaught() {
    yield 1;
    yield 2;
}
$g = uncaught();
echo $g->current(), "\n";
try {
    $g->throw(new \RuntimeException("nope"));
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "got:", $e->getMessage(), "\n";
}
echo $g->valid() ? "y" : "n", "\n";

function pairs() {
    yield "a" => 1;
    yield "b" => 2;
    yield from ["c" => 3, "d" => 4];
}
foreach (pairs() as $k => $v) echo $k, "=", $v, "\n";

function forwardKeys() {
    yield "x" => "X";
    yield from forwardKeysInner();
}
function forwardKeysInner() {
    yield "y" => "Y";
    yield "z" => "Z";
}
foreach (forwardKeys() as $k => $v) echo $k, "=", $v, "\n";

function genReturn() {
    return;
    yield;
}
$g = genReturn();
foreach ($g as $v) echo "no\n";
echo "done\n";

function fromGen() {
    yield from genReturn();
    yield "after";
}
foreach (fromGen() as $v) echo $v, "\n";
