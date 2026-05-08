<?php
// getReturn() on completed generator
function gen() { yield 1; yield 2; return 'done'; }
$g = gen();
foreach ($g as $v) echo $v, "\n";
echo "ret:", $g->getReturn(), "\n";

// getReturn() on completed generator with array return
function gen2() { yield 'a'=>1; yield 'b'=>2; return ['done', 42]; }
$g2 = gen2();
foreach ($g2 as $k => $v) echo "$k=$v\n";
print_r($g2->getReturn());

// getReturn() with no return - returns null
function gen3() { yield 1; }
$g3 = gen3();
foreach ($g3 as $v) {}
var_dump($g3->getReturn());

// getReturn() before generator finishes throws Exception
function gen4() { yield 1; yield 2; return 'r'; }
$g4 = gen4();
$g4->current();
try {
    $g4->getReturn();
    echo "no exception\n";
} catch (\Exception $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// after finishing iteration getReturn works
foreach ($g4 as $v) {}
echo "now:", $g4->getReturn(), "\n";

// yield from with return value plumbed through
function inner() { yield 1; yield 2; return 'inner-ret'; }
function outer() {
    $ret = yield from inner();
    yield "got:$ret";
    return 'outer-ret';
}
$o = outer();
foreach ($o as $v) echo $v, "\n";
echo "outer ret:", $o->getReturn(), "\n";

// password_verify on bad input
var_dump(password_verify('hello', ''));
var_dump(password_verify('hello', 'not-a-hash'));

// array_map multi-array
print_r(array_map(fn($a, $b) => $a + $b, [1, 2, 3], [10, 20, 30]));
print_r(array_map(null, [1, 2, 3], ['a', 'b', 'c']));
print_r(array_map('strtoupper', ['x' => 'foo', 'y' => 'bar']));

// array_combine length mismatch
try {
    array_combine(['a', 'b'], [1, 2, 3]);
} catch (\ValueError $e) {
    echo "combine: ", $e->getMessage(), "\n";
}
print_r(array_combine([], []));
