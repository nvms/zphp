<?php
$f = new Fiber(function () {
    echo "start\n";
    $v = Fiber::suspend(1);
    echo "resumed with $v\n";
    $v2 = Fiber::suspend(2);
    echo "resumed again with $v2\n";
    return "done";
});

echo $f->start(), "\n";
echo $f->resume("a"), "\n";
echo $f->resume("b"), "\n";
echo $f->getReturn(), "\n";

$f2 = new Fiber(function () {
    Fiber::suspend(10);
    throw new Exception("inner");
});
echo $f2->start(), "\n";
try { $f2->resume(); } catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }

$f3 = new Fiber(function () {
    while (true) {
        try { Fiber::suspend(null); } catch (Exception $e) { return "caught: " . $e->getMessage(); }
    }
});
$f3->start();
echo $f3->throw(new Exception("thrown into fiber")), "\n";
echo $f3->getReturn(), "\n";

$f5 = new Fiber(function () { return "no suspend"; });
$f5->start();
echo $f5->isTerminated() ? "t\n" : "n\n";
echo $f5->getReturn(), "\n";

$f6 = new Fiber(function () {
    Fiber::suspend();
});
echo $f6->isStarted() ? "y" : "n", "\n";
$f6->start();
echo $f6->isStarted() ? "y" : "n", "\n";
echo $f6->isSuspended() ? "y" : "n", "\n";
echo $f6->isRunning() ? "y" : "n", "\n";
echo $f6->isTerminated() ? "y" : "n", "\n";
$f6->resume();
echo $f6->isTerminated() ? "y" : "n", "\n";

$f7 = new Fiber(function ($x, $y) {
    Fiber::suspend($x + $y);
    return ($x + $y) * 2;
});
echo $f7->start(10, 20), "\n";
echo $f7->resume(), "\n";
echo $f7->getReturn(), "\n";

try {
    $bad = new Fiber(function () { return 42; });
    $bad->resume();
} catch (FiberError $e) { echo "FE1\n"; }

try {
    $bad2 = new Fiber(function () { Fiber::suspend(); });
    $bad2->start();
    $bad2->start();
} catch (FiberError $e) { echo $e->getMessage(), "\n"; }

$collector = [];
$f9 = new Fiber(function () use (&$collector) {
    foreach (range(1, 3) as $i) {
        $collector[] = $i;
        Fiber::suspend();
    }
});
$f9->start();
$f9->resume();
$f9->resume();
print_r($collector);
