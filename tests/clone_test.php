<?php

class Point {
    public $x;
    public $y;

    public function __construct($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
}

$a = new Point(1, 2);
$b = clone $a;
$b->x = 10;

echo $a->x . "\n";
echo $b->x . "\n";
echo $a->y . "\n";
echo $b->y . "\n";
