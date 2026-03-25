<?php
// object operations - tests class instantiation, method calls, property access
class Point {
    public float $x;
    public float $y;

    public function __construct(float $x, float $y) {
        $this->x = $x;
        $this->y = $y;
    }

    public function distanceTo(Point $other): float {
        $dx = $this->x - $other->x;
        $dy = $this->y - $other->y;
        return sqrt($dx * $dx + $dy * $dy);
    }

    public function add(Point $other): Point {
        return new Point($this->x + $other->x, $this->y + $other->y);
    }
}

$n = 50000;
$points = [];

// create objects
for ($i = 0; $i < $n; $i++) {
    $points[] = new Point($i * 0.1, $i * 0.2);
}

// method calls
$totalDist = 0.0;
for ($i = 1; $i < $n; $i++) {
    $totalDist += $points[$i]->distanceTo($points[$i - 1]);
}

// chained operations
$sum = new Point(0, 0);
for ($i = 0; $i < 1000; $i++) {
    $sum = $sum->add($points[$i]);
}

echo (int) $totalDist . "\n";
echo (int) $sum->x . "\n";
echo (int) $sum->y . "\n";
