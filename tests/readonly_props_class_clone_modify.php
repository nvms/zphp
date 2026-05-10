<?php
class Point {
    public function __construct(
        public readonly int $x,
        public readonly int $y,
    ) {}
}

$p = new Point(3, 4);
echo $p->x, ",", $p->y, "\n";

try {
    $p->x = 10;
    echo "no\n";
} catch (\Error $e) {
    echo "ro-error\n";
}

try {
    unset($p->x);
    echo "no\n";
} catch (\Error $e) {
    echo "ro-unset\n";
}

readonly class Config {
    public function __construct(
        public string $host,
        public int $port,
        public array $tags,
    ) {}
}

$c = new Config("localhost", 8080, ["a", "b"]);
echo $c->host, ":", $c->port, "\n";
print_r($c->tags);

try {
    $c->host = "other";
} catch (\Error $e) {
    echo "ro-class\n";
}

class Address {
    public function __construct(
        public readonly string $city,
        public readonly string $zip,
    ) {}
}

$a = new Address("Springfield", "12345");
echo $a->city, " ", $a->zip, "\n";

$b = clone $a;
echo $b->city, " ", $b->zip, "\n";
echo $a === $b ? "same" : "diff", "\n";

class Person {
    public function __construct(
        public readonly string $name,
        public readonly int $age,
    ) {}
}

$p = new Person("Alice", 30);
echo $p->name, " ", $p->age, "\n";
try { $p->name = "Bob"; } catch (\Error $e) { echo "ro\n"; }

class Mutable {
    public function __construct(
        public readonly array $items,
    ) {}
}

$m = new Mutable(["a", "b", "c"]);
print_r($m->items);

class WithDefaults {
    public function __construct(
        public readonly string $name = "default",
        public readonly int $value = 42,
    ) {}
}

$d = new WithDefaults;
echo $d->name, " ", $d->value, "\n";
$d2 = new WithDefaults("custom", 99);
echo $d2->name, " ", $d2->value, "\n";

readonly class Vector {
    public function __construct(
        public float $x,
        public float $y,
        public float $z,
    ) {}
    public function magnitude(): float {
        return sqrt($this->x ** 2 + $this->y ** 2 + $this->z ** 2);
    }
}

$v = new Vector(3.0, 4.0, 0.0);
echo $v->magnitude(), "\n";

readonly class Coordinate {
    public function __construct(public int $x, public int $y) {}
}

$c = new Coordinate(10, 20);
echo $c->x, " ", $c->y, "\n";
try { $c->x = 100; } catch (\Error $e) { echo "ro\n"; }

class WithNullable {
    public function __construct(
        public readonly ?string $hint = null,
    ) {}
}

$n = new WithNullable;
echo var_export($n->hint, true), "\n";
$n2 = new WithNullable("hint");
echo $n2->hint, "\n";

class HasReadonly {
    public function __construct(public readonly int $id, public string $name) {}
}

$h = new HasReadonly(1, "alice");
echo $h->id, " ", $h->name, "\n";
$h->name = "bob";
echo $h->id, " ", $h->name, "\n";
try { $h->id = 99; } catch (\Error $e) { echo "ro\n"; }

class Counter {
    private int $count = 0;
    public function __construct(public readonly int $start) { $this->count = $start; }
    public function get(): int { return $this->count; }
    public function inc(): void { $this->count++; }
}

$c = new Counter(10);
echo $c->start, " ", $c->get(), "\n";
$c->inc();
$c->inc();
echo $c->start, " ", $c->get(), "\n";
