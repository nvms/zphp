<?php

// 1. $arr[] = value (array push syntax)
$items = [1, 2, 3];
$items[] = 4;
$items[] = 5;
echo count($items) . "\n";
echo $items[3] . "\n";
echo $items[4] . "\n";

// push to empty array
$empty = [];
$empty[] = "first";
$empty[] = "second";
echo $empty[0] . "\n";
echo $empty[1] . "\n";

// 2. ??= (null coalesce assignment)
$x = null;
$x ??= 42;
echo $x . "\n";

$y = "existing";
$y ??= "ignored";
echo $y . "\n";

$z = 0;
$z ??= "not null";
echo $z . "\n";

$w = false;
$w ??= "not null";
echo var_export($w, true) . "\n";

// 3. list() destructuring
list($a, $b, $c) = [10, 20, 30];
echo $a . "\n";
echo $b . "\n";
echo $c . "\n";

// short syntax destructuring
[$d, $e] = [40, 50];
echo $d . "\n";
echo $e . "\n";

// list with skip
list($f, , $g) = [60, 70, 80];
echo $f . "\n";
echo $g . "\n";

// 4. pass-by-reference
function increment(&$val) {
    $val = $val + 1;
}

$num = 10;
increment($num);
echo $num . "\n";

function swap(&$a, &$b) {
    $tmp = $a;
    $a = $b;
    $b = $tmp;
}

$p = "hello";
$q = "world";
swap($p, $q);
echo $p . "\n";
echo $q . "\n";
