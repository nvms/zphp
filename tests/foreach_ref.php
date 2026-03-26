<?php

// foreach with reference modification
$items = [1, 2, 3, 4, 5];
foreach ($items as &$item) {
    $item = $item * 2;
}
unset($item);
echo implode(",", $items) . "\n";

// reference with modification and immediate read
$data = [10, 20, 30];
foreach ($data as &$d) {
    $d = $d + 5;
}
unset($d);
echo $data[0] . "," . $data[2] . "\n";

// reference in foreach with string keys
$data = ["a" => 1, "b" => 2, "c" => 3];
foreach ($data as $k => &$v) {
    $v = $k . "=" . $v;
}
unset($v);
echo $data["b"] . "\n";

// foreach reference with conditional modification
$nums = [1, 2, 3, 4, 5, 6];
foreach ($nums as &$n) {
    if ($n % 2 === 0) {
        $n = $n * 10;
    }
}
unset($n);
echo implode(",", $nums) . "\n";

// foreach reference with objects
class Box { public $val; public function __construct($v) { $this->val = $v; } }
$boxes = [new Box(1), new Box(2), new Box(3)];
foreach ($boxes as &$box) {
    $box->val += 100;
}
unset($box);
echo $boxes[1]->val . "\n";

echo "done\n";
