<?php
// covers: readonly properties (PHP 8.1), readonly classes (PHP 8.2),
//   first-class callable syntax (PHP 8.1), named arguments, new in initializer,
//   constructor property promotion, enum-flavor traits

echo "=== readonly property ===\n";
class Point {
    public function __construct(
        public readonly float $x,
        public readonly float $y,
    ) {}
}
$p = new Point(1.5, 2.5);
echo "x=$p->x y=$p->y\n";
try {
    $p->x = 99;
    echo "wrote\n";
} catch (Error $e) {
    echo "blocked write to readonly\n";
}

echo "\n=== readonly class freezes all properties ===\n";
readonly class ImmutableUser {
    public function __construct(
        public string $name,
        public int $age,
        public array $tags = [],
    ) {}

    public function withAge(int $age): self {
        return new self($this->name, $age, $this->tags);
    }
}
$u = new ImmutableUser('Alice', 30, ['admin']);
echo "before: $u->name age=$u->age\n";
$u2 = $u->withAge(31);
echo "after: $u2->name age=$u2->age (orig still $u->age)\n";

try {
    $u->name = 'Bob';
} catch (Error $e) {
    echo "readonly class blocked: yes\n";
}

echo "\n=== first-class callable syntax ===\n";
$upper = strtoupper(...);
echo $upper('hello') . "\n";

$rev = strrev(...);
echo $rev('abcdef') . "\n";

class Math {
    public static function double(int $n): int { return $n * 2; }
    public function triple(int $n): int { return $n * 3; }
}
$d = Math::double(...);
echo "static: " . $d(7) . "\n";
$m = new Math();
$t = $m->triple(...);
echo "instance: " . $t(7) . "\n";

echo "\n=== first-class callable composes with array_map ===\n";
$names = ['alice', 'bob', 'carol'];
print_r(array_map(strtoupper(...), $names));

echo "\n=== named arguments ===\n";
class HttpRequest {
    public function __construct(
        public string $method = 'GET',
        public string $url = '/',
        public array $headers = [],
        public ?string $body = null,
        public int $timeout = 30,
    ) {}
}
$r = new HttpRequest(method: 'POST', url: '/users', body: '{"x":1}', timeout: 5);
echo "method: $r->method url: $r->url timeout: $r->timeout\n";
echo "body: $r->body\n";

echo "\n=== named args skip middle ===\n";
function greet(string $name, string $prefix = 'Mr', string $suffix = 'Esq', string $title = ''): string {
    return trim("$prefix $name $suffix $title");
}
echo greet('Smith', title: 'Dr') . "\n";
echo greet(name: 'Doe', suffix: 'III') . "\n";

echo "\n=== new in initializer (PHP 8.1) ===\n";
class Logger {
    public function __construct(public string $prefix = '[log]') {}
}
class Service {
    public function __construct(public Logger $log = new Logger('[svc]')) {}
}
$s = new Service();
echo "svc default log prefix: " . $s->log->prefix . "\n";
$s2 = new Service(new Logger('[custom]'));
echo "svc custom log prefix: " . $s2->log->prefix . "\n";

echo "\n=== Closure::fromCallable equivalence ===\n";
function add(int $a, int $b): int { return $a + $b; }
$c1 = Closure::fromCallable('add');
$c2 = add(...);
echo "from fromCallable: " . $c1(2, 3) . "\n";
echo "first-class:        " . $c2(2, 3) . "\n";

echo "\n=== arrow function + closure use ===\n";
$factor = 5;
$multiply = fn(int $n) => $n * $factor;
echo "arrow with auto-capture: " . $multiply(7) . "\n";

$accum = 0;
$add_to = function (int $n) use (&$accum) { $accum += $n; };
$add_to(10); $add_to(20); $add_to(5);
echo "accum: $accum\n";

echo "\n=== invokable object ===\n";
class Counter {
    private int $n = 0;
    public function __invoke(int $step = 1): int {
        $this->n += $step;
        return $this->n;
    }
}
$c = new Counter();
echo "call 1 -> " . $c() . "\n";
echo "call 5 -> " . $c(5) . "\n";
echo "call 2 -> " . $c(2) . "\n";

echo "\n=== match expression with array result ===\n";
function classify(int $score): array {
    return match (true) {
        $score >= 90 => ['grade' => 'A', 'pass' => true],
        $score >= 80 => ['grade' => 'B', 'pass' => true],
        $score >= 70 => ['grade' => 'C', 'pass' => true],
        $score >= 60 => ['grade' => 'D', 'pass' => true],
        default      => ['grade' => 'F', 'pass' => false],
    };
}
foreach ([95, 82, 71, 65, 40] as $s) {
    $r = classify($s);
    echo "  $s -> $r[grade] pass=" . ($r['pass'] ? 'y' : 'n') . "\n";
}

echo "\ndone\n";
