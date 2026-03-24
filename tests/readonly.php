<?php

class Point {
    public function __construct(
        public readonly float $x,
        public readonly float $y
    ) {}
}

$p = new Point(1.5, 2.5);
echo $p->x . "," . $p->y . "\n";

try {
    $p->x = 99.0;
    echo "ERROR\n";
} catch (Error $e) {
    echo $e->getMessage() . "\n";
}

class Config {
    public readonly string $name;
    public readonly int $value;

    public function __construct(string $name, int $value) {
        $this->name = $name;
        $this->value = $value;
    }
}

$c = new Config("debug", 1);
echo $c->name . ":" . $c->value . "\n";

try {
    $c->value = 2;
    echo "ERROR\n";
} catch (Error $e) {
    echo $e->getMessage() . "\n";
}

// non-readonly properties still work normally
class Mutable {
    public string $name = "default";
}
$m = new Mutable();
$m->name = "changed";
echo $m->name . "\n";
