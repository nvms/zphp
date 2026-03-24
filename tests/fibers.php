<?php

// basic fiber: start, suspend, resume, getReturn
$fiber = new Fiber(function() {
    Fiber::suspend('first');
    Fiber::suspend('second');
    return 'final';
});

echo $fiber->start() . "\n";      // first
echo $fiber->resume('a') . "\n";  // second
echo $fiber->resume('b') . "\n";  // (empty - fiber completed, returns null)
echo $fiber->getReturn() . "\n";  // final

// state queries
$f2 = new Fiber(function() {
    Fiber::suspend();
});
echo $f2->isStarted() ? "true" : "false";
echo "\n";  // false
$f2->start();
echo $f2->isSuspended() ? "true" : "false";
echo "\n";  // true
$f2->resume();
echo $f2->isTerminated() ? "true" : "false";
echo "\n";  // true

// suspend value passed to resume
$f3 = new Fiber(function() {
    $val = Fiber::suspend('hello');
    echo "received: $val\n";  // received: world
    return $val;
});
$suspended = $f3->start();
echo "suspended: $suspended\n";  // suspended: hello
$f3->resume('world');
echo "return: " . $f3->getReturn() . "\n";  // return: world

// fiber with arguments to start
$f4 = new Fiber(function($a, $b) {
    echo "args: $a $b\n";  // args: x y
    Fiber::suspend();
    return $a . $b;
});
$f4->start('x', 'y');
$f4->resume();
echo "concat: " . $f4->getReturn() . "\n";  // concat: xy

// deep suspension - suspend from nested function call
function inner() {
    Fiber::suspend('from inner');
}

function middle() {
    inner();
}

$f5 = new Fiber(function() {
    middle();
    return 'deep done';
});
echo "deep: " . $f5->start() . "\n";  // deep: from inner
$f5->resume();
echo "deep return: " . $f5->getReturn() . "\n";  // deep return: deep done

// multiple suspend/resume cycles
$f6 = new Fiber(function() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $val = Fiber::suspend($sum);
        $sum += $val;
    }
    return $sum;
});

echo $f6->start() . "\n";       // 0
echo $f6->resume(10) . "\n";    // 10
echo $f6->resume(20) . "\n";    // 30
$f6->resume(30);
echo "sum: " . $f6->getReturn() . "\n";  // sum: 60
