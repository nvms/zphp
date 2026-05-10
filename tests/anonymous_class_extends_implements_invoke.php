<?php
$o = new class {
    public int $x = 42;
    public function hello(): string { return "hi"; }
};
echo $o->x, "\n";
echo $o->hello(), "\n";

$o = new class("alice") {
    public function __construct(public string $name) {}
    public function greet(): string { return "hello, " . $this->name; }
};
echo $o->greet(), "\n";
echo $o->name, "\n";

abstract class Base {
    abstract public function describe(): string;
    public function intro(): string { return "I am: " . $this->describe(); }
}

$o = new class extends Base {
    public function describe(): string { return "anonymous"; }
};
echo $o->intro(), "\n";
echo $o->describe(), "\n";

interface Greeter {
    public function greet(): string;
}

$o = new class implements Greeter {
    public function greet(): string { return "hi from anon"; }
};
echo $o->greet(), "\n";
echo $o instanceof Greeter ? "y" : "n", "\n";

trait Tagged {
    public string $tag = "trait-tag";
    public function getTag(): string { return $this->tag; }
}

$o = new class {
    use Tagged;
};
echo $o->tag, "\n";
echo $o->getTag(), "\n";

class Outer {
    public function makeInner(int $start): object {
        return new class($start) {
            public int $n;
            public function __construct(int $n) { $this->n = $n; }
            public function inc(): int { return ++$this->n; }
        };
    }
}

$inner = (new Outer)->makeInner(10);
echo $inner->n, "\n";
echo $inner->inc(), "\n";
echo $inner->inc(), "\n";

$counter = 0;
$inc = new class(0) {
    public int $n;
    public function __construct(int $n) { $this->n = $n; }
    public function __invoke(): int { return ++$this->n; }
};
echo $inc(), " ", $inc(), " ", $inc(), "\n";

interface Iface1 { public function a(): int; }
interface Iface2 { public function b(): int; }
$o = new class implements Iface1, Iface2 {
    public function a(): int { return 1; }
    public function b(): int { return 2; }
};
echo $o->a(), " ", $o->b(), "\n";
echo ($o instanceof Iface1) && ($o instanceof Iface2) ? "y" : "n", "\n";

class WithStatic {
    public static int $shared = 100;
}
$o = new class extends WithStatic {
    public function get(): int { return self::$shared; }
};
echo $o->get(), "\n";

$arr = [];
for ($i = 0; $i < 3; $i++) {
    $arr[] = new class($i) {
        public function __construct(public int $id) {}
    };
}
foreach ($arr as $o) echo $o->id, " ";
echo "\n";

$first = $arr[0];
$second = $arr[1];
echo get_class($first) === get_class($second) ? "same" : "diff", "\n";

echo str_contains(get_class($o), "class@anonymous") ? "y" : "n", "\n";

$factory = function (int $n): object {
    return new class($n) {
        public int $v;
        public function __construct(int $n) { $this->v = $n * 2; }
    };
};
$a = $factory(5);
$b = $factory(10);
echo $a->v, " ", $b->v, "\n";

class Service {
    private array $handlers = [];
    public function register(callable $h): void { $this->handlers[] = $h; }
    public function run(int $x): array {
        return array_map(fn($h) => $h($x), $this->handlers);
    }
}

$s = new Service;
$s->register(new class { public function __invoke(int $x): int { return $x * 2; } });
$s->register(new class { public function __invoke(int $x): int { return $x + 10; } });
print_r($s->run(5));

$obj = new class {
    public string $a = "A";
    public string $b = "B";
};
print_r((array)$obj);

$o = new class {
    public function whoami(): string { return static::class; }
};
echo str_contains($o->whoami(), "class@anonymous") ? "y" : "n", "\n";

interface Sized { public function size(): int; }

function takesSized(Sized $s): int { return $s->size(); }

echo takesSized(new class implements Sized {
    public function size(): int { return 99; }
}), "\n";

$factory = function (int $base) {
    return new class($base) {
        private int $base;
        public function __construct(int $b) { $this->base = $b; }
        public function multiply(int $n): int { return $this->base * $n; }
    };
};
$five = $factory(5);
echo $five->multiply(7), "\n";
