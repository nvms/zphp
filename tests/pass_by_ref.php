<?php

// 1. basic function ref param
function increment(&$x) {
    $x++;
}
$a = 5;
increment($a);
echo $a . "\n";

// 2. multiple ref params
function swap(&$a, &$b) {
    $temp = $a;
    $a = $b;
    $b = $temp;
}
$x = "hello";
$y = "world";
swap($x, $y);
echo "$x $y\n";

// 3. ref param with non-ref param
function addTo(&$sum, $val) {
    $sum += $val;
}
$total = 0;
addTo($total, 10);
addTo($total, 20);
echo $total . "\n";

// 4. nested function calls with refs
function doubleIt(&$n) { $n *= 2; }
$val = 3;
doubleIt($val);
doubleIt($val);
echo $val . "\n";

// 5. closure use by reference
$counter = 0;
$inc = function() use (&$counter) {
    $counter++;
};
$inc();
$inc();
$inc();
echo $counter . "\n";

// 6. closure use by reference - write back visible to outer scope
$items = [];
$add = function($item) use (&$items) {
    $items[] = $item;
};
$add("a");
$add("b");
$add("c");
echo count($items) . "\n";
echo implode(",", $items) . "\n";

// 7. multiple closures sharing same ref
$value = 0;
$getter = function() use (&$value) { return $value; };
$setter = function($v) use (&$value) { $value = $v; };
$setter(42);
echo $getter() . "\n";
$setter(100);
echo $getter() . "\n";

// 8. closure ref with outer scope modification
$msg = "hello";
$read = function() use (&$msg) { return $msg; };
echo $read() . "\n";
$msg = "world";
echo $read() . "\n";

// 9. ref param in method
class Counter {
    private $count = 0;

    public function getCount(&$out) {
        $out = $this->count;
    }

    public function increment() {
        $this->count++;
    }
}

$c = new Counter();
$c->increment();
$c->increment();
$c->increment();
$result = 0;
$c->getCount($result);
echo $result . "\n";

// 10. ref param modifying arrays
function appendItem(&$arr, $item) {
    $arr[] = $item;
}
$list = [1, 2];
appendItem($list, 3);
appendItem($list, 4);
echo implode(",", $list) . "\n";

// 11. ref param with string modification
function appendStr(&$s, $suffix) {
    $s .= $suffix;
}
$greeting = "hello";
appendStr($greeting, " world");
echo $greeting . "\n";

// 12. sort (modifies array in place)
$arr = [3, 1, 4, 1, 5, 9];
sort($arr);
echo implode(",", $arr) . "\n";

echo "done\n";
