<?php

namespace App\Geometry;

const ORIGIN_X = 0;

function distance(Point $a, Point $b): float
{
    return sqrt(($a->x - $b->x) ** 2 + ($a->y - $b->y) ** 2);
}

class Point
{
    public function __construct(public float $x, public float $y)
    {
    }

    public function __toString(): string
    {
        return "({$this->x}, {$this->y})";
    }
}
