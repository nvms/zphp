<?php

namespace App\Shapes;

use App\Geometry\Point;
use function App\Geometry\distance;
use const App\Geometry\ORIGIN_X;

abstract class Shape
{
    abstract public function area(): float;

    public function describe(): string
    {
        return static::class . ' area=' . round($this->area(), 2);
    }
}

class Circle extends Shape
{
    public function __construct(private Point $center, private float $radius)
    {
    }

    public function area(): float
    {
        return 3.14159 * $this->radius ** 2;
    }

    public function centerString(): string
    {
        return (string) $this->center;
    }

    public function covers(Point $p): bool
    {
        return distance($this->center, $p) <= $this->radius;
    }

    public function originX(): int
    {
        return ORIGIN_X;
    }
}

class Rectangle extends Shape
{
    public function __construct(private float $w, private float $h)
    {
    }

    public function area(): float
    {
        return $this->w * $this->h;
    }
}
