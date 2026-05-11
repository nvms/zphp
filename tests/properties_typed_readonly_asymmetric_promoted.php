<?php
class Plain {
    public int $a = 1;
    public string $b = "hello";
    public float $c = 3.14;
    public bool $d = true;
    public ?int $e = null;
    public array $f = [1, 2, 3];
}

$p = new Plain;
echo $p->a, " ", $p->b, " ", $p->c, " ", $p->d ? "1" : "0", " ", var_export($p->e, true), "\n";
print_r($p->f);

class Typed {
    public int $x;
    public string $y;
    public function __construct(int $x, string $y) {
        $this->x = $x;
        $this->y = $y;
    }
}
$t = new Typed(42, "ok");
echo $t->x, " ", $t->y, "\n";

$t->x = 100;
echo $t->x, "\n";

class Nullable {
    public ?string $name = null;
}

$n = new Nullable;
echo var_export($n->name, true), "\n";
$n->name = "alice";
echo $n->name, "\n";
$n->name = null;
echo var_export($n->name, true), "\n";

class ReadOnly1 {
    public readonly int $id;
    public readonly string $name;
    public function __construct(int $id, string $name) {
        $this->id = $id;
        $this->name = $name;
    }
}

$r = new ReadOnly1(1, "alice");
echo $r->id, " ", $r->name, "\n";

try {
    $r->id = 2;
    echo "no\n";
} catch (\Error $e) {
    echo "ro\n";
}

readonly class ReadOnlyClass {
    public function __construct(
        public int $x,
        public int $y,
    ) {}
}

$rc = new ReadOnlyClass(3, 4);
echo $rc->x, " ", $rc->y, "\n";

try {
    $rc->x = 99;
    echo "no\n";
} catch (\Error $e) {
    echo "ro\n";
}

class AsymmetricVis {
    public private(set) int $count = 0;
    public function inc(): void { $this->count++; }
}

$av = new AsymmetricVis;
echo $av->count, "\n";
$av->inc();
echo $av->count, "\n";

try {
    $av->count = 99;
    echo "no\n";
} catch (\Error $e) {
    echo "asym\n";
}

class ProtectedSet {
    public protected(set) string $tag = "init";
    public function setTag(string $t): void { $this->tag = $t; }
}

class Sub extends ProtectedSet {
    public function update(string $v): void { $this->tag = $v; }
}

$ps = new ProtectedSet;
echo $ps->tag, "\n";
$ps->setTag("changed");
echo $ps->tag, "\n";

$sub = new Sub;
$sub->update("from-sub");
echo $sub->tag, "\n";

try {
    $ps->tag = "direct";
    echo "no\n";
} catch (\Error $e) {
    echo "psprot\n";
}

class WithDefaults {
    public int $i = 10;
    public string $s = "default";
    public array $arr = ["a", "b", "c"];
    public ?stdClass $obj = null;
}

$d = new WithDefaults;
echo $d->i, " ", $d->s, "\n";
print_r($d->arr);
echo var_export($d->obj, true), "\n";

class WithComputed {
    public int $base = 10;
    public int $multiplied;
    public function __construct() {
        $this->multiplied = $this->base * 5;
    }
}

$c = new WithComputed;
echo $c->base, " ", $c->multiplied, "\n";

class Promoted {
    public function __construct(
        public int $a,
        public readonly string $b,
        public ?float $c = null,
    ) {}
}

$p = new Promoted(1, "two");
echo $p->a, " ", $p->b, " ", var_export($p->c, true), "\n";
$p->a = 99;
echo $p->a, "\n";
try { $p->b = "x"; } catch (\Error $e) { echo "ro-b\n"; }

class MultiType {
    public int|string $either = 0;
}

$m = new MultiType;
$m->either = 42;
echo $m->either, " (", gettype($m->either), ")\n";
$m->either = "hello";
echo $m->either, " (", gettype($m->either), ")\n";

class WithStatic {
    public static int $shared = 100;
    public int $instance = 1;
}

echo WithStatic::$shared, "\n";
WithStatic::$shared = 200;
echo WithStatic::$shared, "\n";
echo (new WithStatic)->instance, "\n";

class Const1 {
    public const VERSION = "1.0";
    public const MAX = 100;
    final public const SECRET = "hidden";
}

echo Const1::VERSION, " ", Const1::MAX, " ", Const1::SECRET, "\n";

class Counter {
    private int $n = 0;
    public function inc(): int { return ++$this->n; }
    public function get(): int { return $this->n; }
}

$c = new Counter;
$c->inc();
$c->inc();
$c->inc();
echo $c->get(), "\n";

class ImmutablePoint {
    public function __construct(
        public readonly float $x,
        public readonly float $y,
    ) {}
    public function distance(self $other): float {
        return sqrt(($this->x - $other->x) ** 2 + ($this->y - $other->y) ** 2);
    }
}

$a = new ImmutablePoint(0, 0);
$b = new ImmutablePoint(3, 4);
echo $a->distance($b), "\n";

class WithDates {
    public function __construct(
        public readonly DateTimeImmutable $created,
    ) {}
}

$d = new WithDates(new DateTimeImmutable("2025-01-01", new DateTimeZone("UTC")));
echo $d->created->format("Y-m-d"), "\n";

class Settings {
    public readonly array $config;
    public function __construct(array $cfg) {
        $this->config = $cfg;
    }
}

$s = new Settings(["host" => "localhost", "port" => 8080]);
echo $s->config["host"], " ", $s->config["port"], "\n";

try {
    $s->config = [];
    echo "no\n";
} catch (\Error $e) {
    echo "ro-cfg\n";
}
