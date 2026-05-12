<?php
// covers: Closure::bind / bindTo for scope changes, Closure::call ad-hoc binding,
//   ReflectionFunction on closures, ReflectionMethod->getClosure(),
//   static closures, $this-less arrow funcs, closure use vs auto-capture

class Wallet {
    private int $cents = 0;
    public function __construct(int $cents = 0) { $this->cents = $cents; }
    public function balance(): int { return $this->cents; }
}

echo "=== Closure::bind changes scope ===\n";
$peek = Closure::bind(
    fn(Wallet $w) => $w->cents,
    null,
    Wallet::class,
);
$w = new Wallet(500);
echo "private peek: " . $peek($w) . "\n";

echo "\n=== closure->bindTo binds \$this + scope ===\n";
$mutate = function (int $delta): int {
    $this->cents += $delta;
    return $this->cents;
};
$bound = $mutate->bindTo($w, Wallet::class);
echo "after +100: " . $bound(100) . "\n";
echo "after -50: " . $bound(-50) . "\n";
echo "balance via public: " . $w->balance() . "\n";

echo "\n=== Closure::call: bind for a single invocation ===\n";
$probe = function (): int { return $this->cents; };
echo "via call: " . $probe->call(new Wallet(999)) . "\n";

echo "\n=== arrow function auto-captures by value ===\n";
$tax = 0.10;
$with_tax = fn(int $cents) => (int)round($cents * (1 + $tax));
$tax = 0.50;
echo "with tax: " . $with_tax(100) . "\n"; // captured 0.10

echo "\n=== use(...) captures by value vs by ref ===\n";
$counter = 0;
$increment_val = function () use ($counter) { return $counter + 1; };
$increment_ref = function () use (&$counter) { return ++$counter; };
$increment_val(); $increment_val();
echo "by-value didn't mutate: $counter\n";
$increment_ref(); $increment_ref();
echo "by-ref mutated: $counter\n";

echo "\n=== ReflectionFunction on closure ===\n";
$adder = fn(int $a, int $b = 5): int => $a + $b;
$rf = new ReflectionFunction($adder);
echo "isClosure: " . ($rf->isClosure() ? "yes" : "no") . "\n";
echo "params: " . $rf->getNumberOfParameters() . " required: " . $rf->getNumberOfRequiredParameters() . "\n";
echo "return type: " . $rf->getReturnType()->getName() . "\n";

echo "\n=== ReflectionMethod::getClosure for instance method ===\n";
class Greeter {
    public function __construct(private string $greeting) {}
    public function say(string $name): string {
        return "{$this->greeting}, $name!";
    }
}
$rm = new ReflectionMethod(Greeter::class, 'say');
$g = new Greeter('Hola');
$bound_say = $rm->getClosure($g);
echo $bound_say('Alice') . "\n";
echo $bound_say('Bob') . "\n";

echo "\n=== closure stored on object property ===\n";
class Box {
    public ?Closure $on_change = null;
    public function __construct(public mixed $value = null) {}
    public function set(mixed $v): void {
        $old = $this->value;
        $this->value = $v;
        if ($this->on_change) ($this->on_change)($old, $v);
    }
}
$b = new Box(1);
$events = [];
$b->on_change = function ($old, $new) use (&$events) {
    $events[] = "$old -> $new";
};
$b->set(2);
$b->set(3);
$b->set(10);
foreach ($events as $e) echo "  $e\n";

echo "\n=== Closure::fromCallable ===\n";
function plainPlus7(int $x): int { return $x * 7; }
$c1 = Closure::fromCallable('plainPlus7');
$c2 = plainPlus7(...);
echo "fromCallable: " . $c1(3) . "\n";
echo "first-class:  " . $c2(3) . "\n";

echo "\n=== rebinding to a different class via bindTo ===\n";
class Aclass {
    protected int $val = 1;
}
class Bclass {
    protected int $val = 2;
}
$reader = function (): int { return $this->val; };
$as_a = $reader->bindTo(new Aclass(), Aclass::class);
$as_b = $reader->bindTo(new Bclass(), Bclass::class);
echo "as A: " . $as_a() . "\n";
echo "as B: " . $as_b() . "\n";

echo "\n=== closure chained through array_map keeps capture ===\n";
$factor = 10;
$mults = [];
foreach (range(1, 4) as $n) {
    $mults[] = fn(int $x) => $x * $n;
}
foreach ($mults as $i => $m) echo "  index $i: m(5) = " . $m(5) . "\n";

echo "\n=== static closure can't be \$this-bound ===\n";
$static = static function (): string { return 'no this'; };
$result = @$static->bindTo(new Wallet(), Wallet::class);
echo "static->bindTo: " . var_export($result, true) . "\n";
echo "still callable: " . $static() . "\n";

echo "\ndone\n";
