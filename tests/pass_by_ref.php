<?php

// === basic ref param ===

function increment(&$x) { $x++; }
$a = 5;
increment($a);
echo $a . "\n"; // 6

function swap(&$a, &$b) { $temp = $a; $a = $b; $b = $temp; }
$x = "hello";
$y = "world";
swap($x, $y);
echo "$x $y\n"; // world hello

// mixed ref and non-ref params
function addTo(&$sum, $val) { $sum += $val; }
$total = 0;
addTo($total, 10);
addTo($total, 20);
echo $total . "\n"; // 30

// multiple calls to same ref function
function doubleIt(&$n) { $n *= 2; }
$val = 3;
doubleIt($val);
doubleIt($val);
echo $val . "\n"; // 12

// ref param with string concat
function appendStr(&$s, $suffix) { $s .= $suffix; }
$greeting = "hello";
appendStr($greeting, " world");
echo $greeting . "\n"; // hello world

// ref param with array modification
function appendItem(&$arr, $item) { $arr[] = $item; }
$list = [1, 2];
appendItem($list, 3);
appendItem($list, 4);
echo implode(",", $list) . "\n"; // 1,2,3,4

// ref param that replaces value entirely
function resetTo(&$v, $newval) { $v = $newval; }
$thing = "old";
resetTo($thing, "new");
echo $thing . "\n"; // new

// ref param with null
function setNull(&$v) { $v = null; }
$notNull = 42;
setNull($notNull);
echo var_export($notNull, true) . "\n"; // NULL

// ref param where callee doesn't modify
function peekRef(&$v) { return $v + 1; }
$orig = 10;
$result = peekRef($orig);
echo "$orig $result\n"; // 10 11

// === closure use by reference ===

$counter = 0;
$inc = function() use (&$counter) { $counter++; };
$inc();
$inc();
$inc();
echo $counter . "\n"; // 3

// closure building an array
$items = [];
$add = function($item) use (&$items) { $items[] = $item; };
$add("a");
$add("b");
$add("c");
echo count($items) . "\n"; // 3
echo implode(",", $items) . "\n"; // a,b,c

// two closures sharing a ref
$value = 0;
$getter = function() use (&$value) { return $value; };
$setter = function($v) use (&$value) { $value = $v; };
$setter(42);
echo $getter() . "\n"; // 42
$setter(100);
echo $getter() . "\n"; // 100

// closure ref reflects outer scope changes
$msg = "hello";
$read = function() use (&$msg) { return $msg; };
echo $read() . "\n"; // hello
$msg = "world";
echo $read() . "\n"; // world

// closure modifies, outer scope sees it
$flag = false;
$toggle = function() use (&$flag) { $flag = !$flag; };
$toggle();
echo var_export($flag, true) . "\n"; // true
$toggle();
echo var_export($flag, true) . "\n"; // false

// mixed ref and non-ref captures
$refVar = 0;
$nonRef = "fixed";
$fn = function() use (&$refVar, $nonRef) {
    $refVar++;
    return $nonRef;
};
$fn();
$fn();
echo $refVar . "\n"; // 2
echo $fn() . "\n"; // fixed
echo $refVar . "\n"; // 3

// === method ref params ===

class Counter {
    private $count = 0;
    public function increment() { $this->count++; }
    public function getCount(&$out) { $out = $this->count; }
}

$c = new Counter();
$c->increment();
$c->increment();
$c->increment();
$result = 0;
$c->getCount($result);
echo $result . "\n"; // 3

// === ref param with default values ===

function optRef(&$x, $amount = 1) { $x += $amount; }
$n = 10;
optRef($n);
echo $n . "\n"; // 11
optRef($n, 5);
echo $n . "\n"; // 16

// === chained ref calls ===

function addOne(&$x) { $x += 1; }
$chain = 0;
addOne($chain);
addOne($chain);
addOne($chain);
addOne($chain);
addOne($chain);
echo $chain . "\n"; // 5

// === ref with boolean/type changes ===

function toArray(&$v) { $v = [$v]; }
$scalar = 42;
toArray($scalar);
echo var_export(is_array($scalar), true) . "\n"; // true
echo $scalar[0] . "\n"; // 42

// === sort (modifies array in place) ===

$arr = [3, 1, 4, 1, 5, 9];
sort($arr);
echo implode(",", $arr) . "\n"; // 1,1,3,4,5,9

$arr2 = ["banana", "apple", "cherry"];
sort($arr2);
echo implode(",", $arr2) . "\n"; // apple,banana,cherry

// === preg_match ref param ===

$matches = [];
preg_match('/(\d+)/', 'abc123def', $matches);
echo $matches[0] . "\n"; // 123
echo $matches[1] . "\n"; // 123

// === closure as callback with ref (e.g. array_map pattern) ===

$sum = 0;
$nums = [1, 2, 3, 4, 5];
foreach ($nums as $n) {
    $add = function() use (&$sum, $n) { $sum += $n; };
    $add();
}
echo $sum . "\n"; // 15

echo "done\n";
