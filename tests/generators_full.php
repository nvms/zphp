<?php
function nums() {
    yield 1;
    yield 2;
    yield 3;
}
foreach (nums() as $n) echo $n, " ";
echo "\n";

// yield key=>value
function kv() {
    yield "a" => 1;
    yield "b" => 2;
    yield "c" => 3;
}
foreach (kv() as $k => $v) echo "$k=$v ";
echo "\n";

// yield without key (auto-increment)
function nokey() {
    yield "a";
    yield "b";
}
foreach (nokey() as $k => $v) echo "$k=$v ";
echo "\n";

// mixed yield with explicit and implicit keys
function mixed() {
    yield 0 => "x";
    yield "k" => "y";
    yield "z";
}
foreach (mixed() as $k => $v) echo "$k=>$v ";
echo "\n";

// yield from array
function delegate() {
    yield 0;
    yield from [1, 2, 3];
    yield 4;
}
foreach (delegate() as $k => $v) echo "$k=$v ";
echo "\n";

// yield from generator
function inner() {
    yield "a" => 1;
    yield "b" => 2;
}
function outer() {
    yield "before" => "x";
    yield from inner();
    yield "after" => "y";
}
foreach (outer() as $k => $v) echo "$k=$v ";
echo "\n";

// yield from associative array
function fromAssoc() {
    yield from ["x" => 10, "y" => 20];
}
foreach (fromAssoc() as $k => $v) echo "$k=$v ";
echo "\n";

// yield from Generator (re-entrant)
function nested() {
    yield from [1, 2];
    yield from [3, 4];
}
foreach (nested() as $n) echo $n, " ";
echo "\n";

// Iterator API
function gen3() {
    yield "a";
    yield "b";
    yield "c";
}
$g = gen3();
echo $g->current(), "\n"; // a
echo $g->key(), "\n";     // 0
$g->next();
echo $g->current(), "\n"; // b
echo $g->key(), "\n";     // 1
var_dump($g->valid()); // true
$g->next();
echo $g->current(), "\n"; // c
$g->next();
var_dump($g->valid()); // false

// rewind on already-running generator throws
$g = gen3();
$g->next(); // start it
try { $g->rewind(); echo "no\n"; } catch (\Exception $e) { echo "rew-exc\n"; }

// send() into generator
function echoer() {
    while (true) {
        $x = yield;
        if ($x === null) return;
        echo "got $x\n";
    }
}
$e = echoer();
$e->current(); // start it
$e->send("hello");
$e->send("world");
$e->send(null);

// send() with returned value
function double_input() {
    while (true) {
        $x = yield;
        if ($x === null) return;
        yield $x * 2;
    }
}
$d = double_input();
$d->current();
echo $d->send(5), "\n"; // 10
$d->next();
echo $d->send(7), "\n"; // 14

// getReturn()
function withReturn() {
    yield 1;
    yield 2;
    return "done";
}
$g = withReturn();
foreach ($g as $v) echo $v, " ";
echo "\n";
echo $g->getReturn(), "\n";

// getReturn before generator finishes throws
$g = withReturn();
try { $g->getReturn(); echo "no\n"; } catch (\Exception $e) { echo "no-ret-exc\n"; }

// throw() into generator
function thrower() {
    try {
        yield 1;
        yield 2;
        yield 3;
    } catch (\RuntimeException $e) {
        yield "caught:" . $e->getMessage();
    }
}
$t = thrower();
echo $t->current(), "\n"; // 1
echo $t->throw(new \RuntimeException("oops")), "\n"; // caught:oops

// throw() out of generator (uncaught)
function notCatching() {
    yield 1;
    yield 2;
}
$g = notCatching();
$g->current();
try {
    $g->throw(new \LogicException("escaped"));
    echo "no\n";
} catch (\LogicException $e) {
    echo "outer:", $e->getMessage(), "\n";
}

// generator returning from yield from
function inner2() {
    yield 1;
    return "inner-done";
}
function outer2() {
    $r = yield from inner2();
    yield "got: $r";
}
foreach (outer2() as $v) echo $v, " ";
echo "\n";

// generator with foreach by ref (architectural - skip)

// generator memory: only first-N
function fib() {
    $a = 0; $b = 1;
    while (true) {
        yield $a;
        [$a, $b] = [$b, $a + $b];
    }
}
$f = fib();
$out = [];
$i = 0;
foreach ($f as $v) {
    if ($i++ >= 10) break;
    $out[] = $v;
}
print_r($out);

// Generator implements Iterator
$g = nums();
var_dump($g instanceof Iterator);
var_dump($g instanceof Generator);
var_dump($g instanceof Traversable);

// iterator_to_array
$g = kv();
print_r(iterator_to_array($g));

$g = nums();
print_r(iterator_to_array($g));

// preserve_keys=false
$g = kv();
print_r(iterator_to_array($g, false));

// duplicate keys throw with preserve_keys=true
function dup() {
    yield "a" => 1;
    yield "a" => 2;
}
$g = dup();
try {
    iterator_to_array($g);
    echo "no\n";
} catch (\Exception $e) {
    echo "dup-exc\n";
}

// duplicate keys ok with preserve_keys=false
$g = dup();
print_r(iterator_to_array($g, false));

// generator chaining
function pairs() {
    yield ["a", 1];
    yield ["b", 2];
    yield ["c", 3];
}
foreach (pairs() as [$k, $v]) echo "$k=$v ";
echo "\n";

// destructure in foreach with named
foreach (pairs() as [$letter, $num]) echo "$letter:$num ";
echo "\n";
