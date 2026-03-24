<?php

// php arrays have value semantics: assignment creates an independent copy

// basic assignment
$a = [1, 2, 3];
$b = $a;
$b[] = 4;
echo count($a) . "," . count($b) . "\n"; // 3,4

// element modification
$c = ["x", "y", "z"];
$d = $c;
$d[0] = "replaced";
echo $c[0] . "," . $d[0] . "\n"; // x,replaced

// function parameter isolation
function modify($arr) {
    $arr[] = "new";
    $arr[0] = "changed";
    return count($arr);
}
$orig = [1, 2, 3];
echo modify($orig) . "\n"; // 4
echo count($orig) . "," . $orig[0] . "\n"; // 3,1

// closure capture isolation
$arr = [10, 20];
$fn = function() use ($arr) {
    $arr[] = 30;
    return count($arr);
};
echo $fn() . "," . count($arr) . "\n"; // 3,2

// multiple copies are independent
$src = [1];
$x = $src;
$y = $src;
$x[] = 2;
$y[] = 3;
$y[] = 4;
echo count($src) . "," . count($x) . "," . count($y) . "\n"; // 1,2,3

// property assignment isolation
class Holder {
    public array $data = [];
    public function setData(array $d): void { $this->data = $d; }
}
$base = [1, 2, 3];
$h = new Holder();
$h->setData($base);
$h->data[] = 4;
echo count($base) . "," . count($h->data) . "\n"; // 3,4
